const std = @import("std");
const build_event = @import("../actions/log/build_log_event_record.zig");
const build_prompt = @import("../actions/log/build_prompt_log_record.zig");
const threshold = @import("../actions/log/evaluate_log_threshold.zig");
const rotation = @import("../actions/log/evaluate_feature_log_rotation_need.zig");
const serialize_event = @import("../actions/log/serialize_event_log_record.zig");
const serialize_prompt = @import("../actions/log/serialize_prompt_log_record.zig");
const serialize_control = @import("../actions/log/serialize_feature_log_control_record.zig");
const validate_fact = @import("../actions/log/validate_log_event_fact.zig");
const validate_prompt = @import("../actions/log/validate_prompt_log_fragment.zig");
const select_prompt = @import("../actions/log/evaluate_prompt_log_capture.zig");
const evaluate_flush = @import("../actions/log/evaluate_feature_log_flush_need.zig");
const advance_state = @import("../actions/log/advance_feature_log_stream_state.zig");
const feature_log_format = @import("../domain/feature_log_format.zig");
const runtime = @import("../domain/feature_log_runtime.zig");
const logging = @import("../domain/logging.zig");
const telemetry = @import("../domain/telemetry.zig");
const barrier_port = @import("../ports/telemetry_barrier.zig");
const child_actions = @import("feature_log_child_actions.zig");

pub const Runner = struct {
    allocator: std.mem.Allocator,
    policy: *const logging.CompiledLoggingPolicy,
    binding: *const runtime.ValidatedFeatureLogBinding,
    children: child_actions.ChildActions,
    event_state: ?runtime.StreamState = null,
    prompt_state: ?runtime.StreamState = null,
    prepared: bool = false,
    retired: bool = false,

    pub fn barrier(self: *Runner) barrier_port.Barrier {
        return .{ .context = self, .process_fn = processBarrier };
    }

    pub fn process(
        self: *Runner,
        attributed: telemetry.WorkflowTelemetryFact,
    ) runtime.BarrierOutcome {
        if (self.retired) return self.block(attributed.workflow_shortcode, .LOG_SINK_FAILURE);
        const definition = (validate_fact.Action{}).execute(attributed.fact) catch {
            return self.block(attributed.workflow_shortcode, .LOG_SERIALIZATION_FAILURE);
        };
        if ((threshold.Action{}).execute(self.policy.*, definition.level) == .drop) return .dropped;

        const reading = self.children.read_clock.execute() catch {
            return self.block(attributed.workflow_shortcode, .LOG_SERIALIZATION_FAILURE);
        };
        self.children.acquire_lock.execute(self.binding, .event) catch {
            return self.block(attributed.workflow_shortcode, .LOG_LOCK_TIMEOUT);
        };
        var terminal_failure: ?runtime.FailureCode = null;

        const result = self.persistEvent(attributed, definition, reading) catch |failure| blk: {
            terminal_failure = failureCode(failure);
            break :blk null;
        };
        self.children.release_lock.execute() catch {
            terminal_failure = .LOG_RELEASE_FAILURE;
        };
        if (terminal_failure) |failure| return self.block(attributed.workflow_shortcode, failure);
        const evidence = result.?;
        return .{ .persisted = evidence };
    }

    pub fn processPrompt(self: *Runner, fragment: runtime.SanitizedPromptFragment) runtime.BarrierOutcome {
        if (self.retired) return self.block(fragment.workflow_shortcode, .LOG_SINK_FAILURE);
        (validate_prompt.Action{}).execute(fragment) catch {
            return self.block(fragment.workflow_shortcode, .LOG_SERIALIZATION_FAILURE);
        };
        if ((select_prompt.Action{}).execute(self.policy.*, fragment) == .drop or
            (threshold.Action{}).execute(self.policy.*, .debug) == .drop) return .dropped;
        const reading = self.children.read_clock.execute() catch {
            return self.block(fragment.workflow_shortcode, .LOG_SERIALIZATION_FAILURE);
        };
        self.children.acquire_lock.execute(self.binding, .prompt) catch {
            return self.block(fragment.workflow_shortcode, .LOG_LOCK_TIMEOUT);
        };
        var terminal_failure: ?runtime.FailureCode = null;
        const result = self.persistPrompt(fragment, reading) catch |failure| blk: {
            terminal_failure = failureCode(failure);
            break :blk null;
        };
        self.children.release_lock.execute() catch {
            terminal_failure = .LOG_RELEASE_FAILURE;
        };
        if (terminal_failure) |failure| return self.block(fragment.workflow_shortcode, failure);
        return .{ .persisted = result.? };
    }

    pub fn processPromptBatch(self: *Runner, owner: *runtime.PromptBatchOwner) runtime.BarrierOutcome {
        defer runtime.deinitPromptBatch(owner);
        var last_persisted: ?runtime.PersistedEvidence = null;
        for (runtime.promptBatch(owner)) |fragment| switch (self.processPrompt(fragment)) {
            .dropped => {},
            .persisted => |evidence| last_persisted = evidence,
            .blocked => |failure| return .{ .blocked = failure },
        };
        return if (last_persisted) |evidence| .{ .persisted = evidence } else .dropped;
    }

    /// Recovers or initializes every enabled stream before this runner can be
    /// published as the active observer.
    pub fn prepare(self: *Runner, shortcode: telemetry.WorkflowShortcode) runtime.BarrierOutcome {
        if (self.retired) return self.block(shortcode, .LOG_SINK_FAILURE);
        if (self.prepared) return .dropped;
        const reading = self.children.read_clock.execute() catch return self.block(shortcode, .LOG_SERIALIZATION_FAILURE);
        if (self.event_state == null) {
            if (self.prepareOne(.event, reading)) |failure| return self.block(shortcode, failure);
        }
        if (self.policy.prompt_capture.len != 0 and self.prompt_state == null) {
            if (self.prepareOne(.prompt, reading)) |failure| return self.block(shortcode, failure);
        }
        self.prepared = true;
        return .dropped;
    }

    pub fn close(self: *Runner, shortcode: telemetry.WorkflowShortcode) runtime.BarrierOutcome {
        if (self.retired) return self.block(shortcode, .LOG_SINK_FAILURE);
        const reading = self.children.read_clock.execute() catch return self.block(shortcode, .LOG_SERIALIZATION_FAILURE);
        if (self.event_state) |state| {
            if (self.closeOne(.event, state, reading)) |failure| return self.block(shortcode, failure);
            self.event_state = null;
        }
        if (self.prompt_state) |state| {
            if (self.closeOne(.prompt, state, reading)) |failure| return self.block(shortcode, failure);
            self.prompt_state = null;
        }
        self.prepared = false;
        self.retired = true;
        return .dropped;
    }

    fn prepareOne(self: *Runner, stream: runtime.Stream, reading: runtime.ClockReading) ?runtime.FailureCode {
        self.children.acquire_lock.execute(self.binding, stream) catch return .LOG_LOCK_TIMEOUT;
        var failure: ?runtime.FailureCode = null;
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const state = switch (stream) {
            .event => self.openEventStream(scratch.allocator(), reading),
            .prompt => self.openPromptStream(scratch.allocator(), reading),
        } catch |open_failure| blk: {
            failure = failureCode(open_failure);
            break :blk null;
        };
        self.children.release_lock.execute() catch return .LOG_RELEASE_FAILURE;
        if (failure) |code| return code;
        switch (stream) {
            .event => self.event_state = state.?,
            .prompt => self.prompt_state = state.?,
        }
        return null;
    }

    fn closeOne(self: *Runner, stream: runtime.Stream, state: runtime.StreamState, reading: runtime.ClockReading) ?runtime.FailureCode {
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const allocator = scratch.allocator();
        const trailer = (serialize_control.Action{}).execute(
            allocator,
            stream,
            .segment_trailer,
            self.binding,
            state.segment_ordinal,
            state.next_sequence - 1,
            reading.utc(),
        ) catch return .LOG_SERIALIZATION_FAILURE;
        self.children.acquire_lock.execute(self.binding, stream) catch return .LOG_LOCK_TIMEOUT;
        var failure: ?runtime.FailureCode = null;
        self.children.close_stream.execute(self.binding, stream, state, trailer) catch |close_failure| {
            failure = if (close_failure == error.LogFlushFailure) .LOG_FLUSH_FAILURE else .LOG_SINK_FAILURE;
        };
        self.children.release_lock.execute() catch return .LOG_RELEASE_FAILURE;
        return failure;
    }

    fn persistEvent(
        self: *Runner,
        attributed: telemetry.WorkflowTelemetryFact,
        definition: logging.EventDefinition,
        reading: runtime.ClockReading,
    ) PersistError!runtime.PersistedEvidence {
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const allocator = scratch.allocator();
        var state = self.event_state orelse self.openEventStream(allocator, reading) catch |failure| return failure;

        var record = (build_event.Action{}).execute(allocator, self.binding, state, reading, attributed) catch {
            return error.SerializationFailure;
        };
        var row = (serialize_event.Action{}).execute(allocator, record) catch {
            return error.SerializationFailure;
        };
        const trailer = (serialize_control.Action{}).execute(
            allocator,
            .event,
            .segment_trailer,
            self.binding,
            state.segment_ordinal,
            state.next_sequence - 1,
            reading.utc(),
        ) catch return error.SerializationFailure;
        const next_header = (serialize_control.Action{}).execute(
            allocator,
            .event,
            .segment_header,
            self.binding,
            state.segment_ordinal + 1,
            null,
            reading.utc(),
        ) catch return error.SerializationFailure;
        switch ((rotation.Action{}).execute(
            state,
            row.len,
            trailer.len,
            feature_log_format.event_heading.len + next_header.len,
        )) {
            .append => {},
            .exhausted => return error.SegmentLimitExhausted,
            .rotate => {
                state = self.children.rotate_segment.execute(
                    self.binding,
                    .event,
                    state,
                    trailer,
                    feature_log_format.event_heading,
                    next_header,
                ) catch return error.RotateFailure;
                record = (build_event.Action{}).execute(allocator, self.binding, state, reading, attributed) catch {
                    return error.SerializationFailure;
                };
                row = (serialize_event.Action{}).execute(allocator, record) catch {
                    return error.SerializationFailure;
                };
            },
        }
        const force_flush = (evaluate_flush.Action{}).execute(
            self.policy.*,
            definition.level,
            attributed.fact.event_type,
            state,
            reading.monotonic_ms,
        ) == .flush;
        const evidence = self.children.append_record.execute(
            self.binding,
            .event,
            state,
            row,
            force_flush,
        ) catch |failure| return switch (failure) {
            error.LogFlushFailure => error.FlushFailure,
            error.LogSinkFailure => error.AppendFailure,
        };
        if (self.policy.console) self.children.write_console.execute(row) catch return error.ConsoleFailure;
        state = (advance_state.Action{}).execute(state, row.len, force_flush, reading.monotonic_ms);
        self.event_state = state;
        return evidence;
    }

    fn openEventStream(
        self: *Runner,
        allocator: std.mem.Allocator,
        reading: runtime.ClockReading,
    ) PersistError!runtime.StreamState {
        const recovered = self.children.recover_stream.execute(
            allocator,
            self.binding,
            .event,
            feature_log_format.event_heading,
        ) catch return error.RecoveryFailure;
        const state = switch (recovered) {
            .active => |active| active,
            .empty => |seed| blk: {
                const header = (serialize_control.Action{}).execute(
                    allocator,
                    .event,
                    .segment_header,
                    self.binding,
                    seed.next_segment_ordinal,
                    null,
                    reading.utc(),
                ) catch return error.SerializationFailure;
                break :blk self.children.create_segment.execute(
                    self.binding,
                    .event,
                    seed.next_segment_ordinal,
                    seed,
                    feature_log_format.event_heading,
                    header,
                ) catch return error.CreateFailure;
            },
        };
        return state;
    }

    fn persistPrompt(
        self: *Runner,
        fragment: runtime.SanitizedPromptFragment,
        reading: runtime.ClockReading,
    ) PersistError!runtime.PersistedEvidence {
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const allocator = scratch.allocator();
        var state = self.prompt_state orelse self.openPromptStream(allocator, reading) catch |failure| return failure;
        var record = (build_prompt.Action{}).execute(allocator, self.binding, state, reading, fragment) catch return error.SerializationFailure;
        var row = (serialize_prompt.Action{}).execute(allocator, record) catch return error.SerializationFailure;
        const trailer = (serialize_control.Action{}).execute(
            allocator,
            .prompt,
            .segment_trailer,
            self.binding,
            state.segment_ordinal,
            state.next_sequence - 1,
            reading.utc(),
        ) catch return error.SerializationFailure;
        const next_header = (serialize_control.Action{}).execute(
            allocator,
            .prompt,
            .segment_header,
            self.binding,
            state.segment_ordinal + 1,
            null,
            reading.utc(),
        ) catch return error.SerializationFailure;
        switch ((rotation.Action{}).execute(state, row.len, trailer.len, feature_log_format.prompt_heading.len + next_header.len)) {
            .append => {},
            .exhausted => return error.SegmentLimitExhausted,
            .rotate => {
                state = self.children.rotate_segment.execute(
                    self.binding,
                    .prompt,
                    state,
                    trailer,
                    feature_log_format.prompt_heading,
                    next_header,
                ) catch return error.RotateFailure;
                record = (build_prompt.Action{}).execute(allocator, self.binding, state, reading, fragment) catch return error.SerializationFailure;
                row = (serialize_prompt.Action{}).execute(allocator, record) catch return error.SerializationFailure;
            },
        }
        const force_flush = (evaluate_flush.Action{}).execute(
            self.policy.*,
            .debug,
            .model_prompt_fragment,
            state,
            reading.monotonic_ms,
        ) == .flush;
        const evidence = self.children.append_record.execute(
            self.binding,
            .prompt,
            state,
            row,
            force_flush,
        ) catch |failure| return switch (failure) {
            error.LogFlushFailure => error.FlushFailure,
            error.LogSinkFailure => error.AppendFailure,
        };
        if (self.policy.console) self.children.write_console.execute(row) catch return error.ConsoleFailure;
        state = (advance_state.Action{}).execute(state, row.len, force_flush, reading.monotonic_ms);
        self.prompt_state = state;
        return evidence;
    }

    fn openPromptStream(self: *Runner, allocator: std.mem.Allocator, reading: runtime.ClockReading) PersistError!runtime.StreamState {
        const recovered = self.children.recover_stream.execute(
            allocator,
            self.binding,
            .prompt,
            feature_log_format.prompt_heading,
        ) catch return error.RecoveryFailure;
        const state = switch (recovered) {
            .active => |active| active,
            .empty => |seed| blk: {
                const header = (serialize_control.Action{}).execute(
                    allocator,
                    .prompt,
                    .segment_header,
                    self.binding,
                    seed.next_segment_ordinal,
                    null,
                    reading.utc(),
                ) catch return error.SerializationFailure;
                break :blk self.children.create_segment.execute(
                    self.binding,
                    .prompt,
                    seed.next_segment_ordinal,
                    seed,
                    feature_log_format.prompt_heading,
                    header,
                ) catch return error.CreateFailure;
            },
        };
        return state;
    }

    pub fn reportFailure(self: *Runner, shortcode: telemetry.WorkflowShortcode, failure: runtime.FailureCode) runtime.FailureCode {
        self.children.emit_emergency.execute(shortcode, failure);
        self.children.stabilize_failure.execute() catch return .LOG_SINK_FAILURE;
        return failure;
    }

    fn block(self: *Runner, shortcode: telemetry.WorkflowShortcode, failure: runtime.FailureCode) runtime.BarrierOutcome {
        return .{ .blocked = self.reportFailure(shortcode, failure) };
    }
};

fn processBarrier(context: *anyopaque, fact: telemetry.WorkflowTelemetryFact) runtime.BarrierOutcome {
    const self: *Runner = @ptrCast(@alignCast(context));
    return self.process(fact);
}

const PersistError = error{
    SerializationFailure,
    RecoveryFailure,
    CreateFailure,
    RotateFailure,
    AppendFailure,
    ConsoleFailure,
    FlushFailure,
    SegmentLimitExhausted,
};

fn failureCode(failure: PersistError) runtime.FailureCode {
    return switch (failure) {
        error.SerializationFailure => .LOG_SERIALIZATION_FAILURE,
        error.RecoveryFailure,
        error.CreateFailure,
        error.RotateFailure,
        error.AppendFailure,
        error.ConsoleFailure,
        => .LOG_SINK_FAILURE,
        error.FlushFailure => .LOG_FLUSH_FAILURE,
        error.SegmentLimitExhausted => .LOG_SEGMENT_LIMIT_EXHAUSTED,
    };
}
