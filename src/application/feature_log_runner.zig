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
const acquire_lock = @import("../actions/log/acquire_feature_log_stream_lock.zig");
const feature_log_format = @import("../domain/feature_log_format.zig");
const log_binding = @import("../domain/feature_log_binding.zig");
const log_stream = @import("../domain/feature_log_stream.zig");
const prompt_log = @import("../domain/sanitized_prompt_log.zig");
const log_policy = @import("../domain/log_policy.zig");
const log_event_registry = @import("../domain/log_event_registry.zig");
const telemetry = @import("../domain/telemetry.zig");
const barrier_port = @import("../ports/telemetry_barrier.zig");
const child_bindings = @import("feature_log_child_bindings.zig");
const orchestrator = @import("feature_log_orchestrator.zig");
const action_set = @import("feature_log_actions.zig");

pub const Runner = struct {
    allocator: std.mem.Allocator,
    policy: *const log_policy.CompiledLoggingPolicy,
    binding: *const log_binding.ValidatedFeatureLogBinding,
    actions: action_set.Set,
    event_state: ?log_stream.StreamState = null,
    prompt_state: ?log_stream.StreamState = null,
    /// The streams whose cached state a cancellation dropped. A cancellation can land after bytes were
    /// written, so the file may be ahead of the cache; the next persist recovers such a stream from its
    /// bytes, as after a crash, and finalization recovers it before closing it.
    dropped: std.EnumSet(log_stream.Stream) = .initEmpty(),
    prepared: bool = false,
    retired: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        policy: *const log_policy.CompiledLoggingPolicy,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        actions: action_set.Set,
    ) Runner {
        return .{
            .allocator = allocator,
            .policy = policy,
            .binding = binding,
            .actions = actions,
        };
    }

    pub fn childBindings(self: *Runner) child_bindings.ChildBindings {
        return .{ .context = self, .vtable = &bindings_vtable };
    }

    pub fn barrier(self: *Runner) barrier_port.Barrier {
        return .{ .context = self, .process_fn = processBarrier, .select_prompt_fn = selectPromptBarrier, .process_prompt_fn = processPromptBarrier, .report_failure_fn = reportFailureBarrier };
    }

    pub fn process(
        self: *Runner,
        attributed: telemetry.WorkflowTelemetryFact,
    ) log_stream.Outcome {
        return orchestrator.processEvent(self.childBindings(), attributed);
    }

    pub fn processPrompt(self: *Runner, fragment: prompt_log.SanitizedPromptFragment) log_stream.Outcome {
        return orchestrator.processPrompt(self.childBindings(), fragment);
    }

    /// Recovers or initializes every enabled stream before this runner can be
    /// published as the active observer.
    pub fn prepare(self: *Runner, shortcode: telemetry.WorkflowShortcode) log_stream.Outcome {
        return orchestrator.prepare(self.childBindings(), shortcode);
    }

    pub fn close(self: *Runner, shortcode: telemetry.WorkflowShortcode) log_stream.Outcome {
        return orchestrator.close(self.childBindings(), shortcode);
    }

    fn invokePrepare(self: *Runner, shortcode: telemetry.WorkflowShortcode) log_stream.Outcome {
        if (self.retired) return self.block(shortcode, .LOG_SINK_FAILURE);
        if (self.prepared) return .dropped;
        const reading = self.actions.read_clock.execute() catch return self.block(shortcode, .LOG_SERIALIZATION_FAILURE);
        if (self.event_state == null) {
            if (self.prepareOne(.event, reading)) |stop| return self.stopped(shortcode, stop);
        }
        if (log_policy.promptCaptureEnabled(self.policy.*) and self.prompt_state == null) {
            if (self.prepareOne(.prompt, reading)) |stop| {
                // A run whose activation stopped is never finalized, so the event stream this prepare
                // opened is closed here instead of being left without a trailer. The prompt stop is the
                // one reported; a stop of this close is not, as the first stop is kept.
                if (self.closeStream(.event, reading)) |_| {}
                return self.stopped(shortcode, stop);
            }
        }
        self.prepared = true;
        return .dropped;
    }

    fn invokeClose(self: *Runner, shortcode: telemetry.WorkflowShortcode) log_stream.Outcome {
        if (self.retired) return self.block(shortcode, .LOG_SINK_FAILURE);
        const reading = self.actions.read_clock.execute() catch return self.block(shortcode, .LOG_SERIALIZATION_FAILURE);
        // Every stream is closed, the second even when the first stopped; the first stop is the one reported.
        var first: ?log_stream.Stop = null;
        for ([_]log_stream.Stream{ .event, .prompt }) |stream| {
            if (self.closeStream(stream, reading)) |stop| first = first orelse stop;
        }
        if (first) |stop| return self.stopped(shortcode, stop);
        self.prepared = false;
        self.retired = true;
        return .dropped;
    }

    /// Close one stream. A stream a cancelled step dropped is recovered first, so a trailer follows the rows
    /// that really are on disk.
    fn closeStream(self: *Runner, stream: log_stream.Stream, reading: log_stream.ClockReading) ?log_stream.Stop {
        if (self.recoverDropped(stream)) |stop| return stop;
        const state = (switch (stream) {
            .event => self.event_state,
            .prompt => self.prompt_state,
        }) orelse return null;
        if (self.closeOne(stream, state, reading)) |stop| return stop;
        switch (stream) {
            .event => self.event_state = null,
            .prompt => self.prompt_state = null,
        }
        return null;
    }

    /// Drop a stream's cached state because a cancelled step may have left its bytes ahead of it.
    fn forget(self: *Runner, stream: log_stream.Stream) void {
        switch (stream) {
            .event => self.event_state = null,
            .prompt => self.prompt_state = null,
        }
        self.dropped.insert(stream);
    }

    /// Recover a stream whose state was dropped, under its lock, so finalization can close it. A stream
    /// the recovery finds closed, or without a segment, has nothing to close.
    fn recoverDropped(self: *Runner, stream: log_stream.Stream) ?log_stream.Stop {
        if (!self.dropped.contains(stream)) return null;
        self.actions.acquire_lock.execute(self.binding, stream) catch |failure| return acquire_lock.stop(failure);
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const heading = if (stream == .event) feature_log_format.event_heading else feature_log_format.prompt_heading;
        var recover_stop: ?log_stream.Stop = null;
        const recovered = self.actions.recover_stream.execute(scratch.allocator(), self.binding, stream, heading) catch |failure| blk: {
            recover_stop = switch (failure) {
                error.LogSinkFailure => .{ .blocked = .LOG_SINK_FAILURE },
                error.Cancelled => .cancelled,
            };
            break :blk null;
        };
        self.actions.release_lock.execute() catch return .{ .blocked = .LOG_RELEASE_FAILURE };
        if (recover_stop) |stop| return stop;
        switch (recovered.?) {
            .active => |state| switch (stream) {
                .event => self.event_state = state,
                .prompt => self.prompt_state = state,
            },
            .empty => {},
        }
        self.dropped.remove(stream);
        return null;
    }

    fn prepareOne(self: *Runner, stream: log_stream.Stream, reading: log_stream.ClockReading) ?log_stream.Stop {
        self.actions.acquire_lock.execute(self.binding, stream) catch |failure| return acquire_lock.stop(failure);
        var open_stop: ?log_stream.Stop = null;
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const state = switch (stream) {
            .event => self.openEventStream(scratch.allocator(), reading),
            .prompt => self.openPromptStream(scratch.allocator(), reading),
        } catch |open_failure| blk: {
            open_stop = persistStop(open_failure);
            break :blk null;
        };
        // The lock is released on every path, a cancelled open included.
        self.actions.release_lock.execute() catch return .{ .blocked = .LOG_RELEASE_FAILURE };
        if (open_stop) |stop| return stop;
        switch (stream) {
            .event => self.event_state = state.?,
            .prompt => self.prompt_state = state.?,
        }
        self.dropped.remove(stream);
        return null;
    }

    fn closeOne(self: *Runner, stream: log_stream.Stream, state: log_stream.StreamState, reading: log_stream.ClockReading) ?log_stream.Stop {
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
        ) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        self.actions.acquire_lock.execute(self.binding, stream) catch |failure| return acquire_lock.stop(failure);
        var close_stop: ?log_stream.Stop = null;
        self.actions.close_stream.execute(self.binding, stream, state, trailer) catch |close_failure| {
            close_stop = switch (close_failure) {
                error.LogFlushFailure => .{ .blocked = .LOG_FLUSH_FAILURE },
                error.LogSinkFailure => .{ .blocked = .LOG_SINK_FAILURE },
                // The trailer may already be written, so the state is dropped whatever the release does next.
                error.Cancelled => cancelled: {
                    self.forget(stream);
                    break :cancelled .cancelled;
                },
            };
        };
        self.actions.release_lock.execute() catch return .{ .blocked = .LOG_RELEASE_FAILURE };
        return close_stop;
    }

    fn persistEvent(
        self: *Runner,
        attributed: telemetry.WorkflowTelemetryFact,
        definition: log_event_registry.EventDefinition,
        reading: log_stream.ClockReading,
    ) PersistError!log_stream.PersistedEvidence {
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const allocator = scratch.allocator();
        var state = self.event_state orelse self.openEventStream(allocator, reading) catch |failure| return failure;
        var event_id_buffer: [32]u8 = undefined;

        var record = (build_event.Action{}).execute(&event_id_buffer, self.binding, state, &reading, attributed) catch {
            return error.SerializationFailure;
        };
        var row = (serialize_event.Action{}).execute(allocator, record) catch {
            return error.SerializationFailure;
        };
        const control = serialize_control.Action{};
        const trailer_len = control.measure(
            .event,
            .segment_trailer,
            self.binding,
            state.segment_ordinal,
            state.next_sequence - 1,
            reading.utc(),
        ) catch return error.SerializationFailure;
        const next_header_len = control.measure(
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
            trailer_len,
            feature_log_format.event_heading.len + next_header_len,
        )) {
            .append => {},
            .exhausted => return error.SegmentLimitExhausted,
            .rotate => {
                const trailer = control.execute(allocator, .event, .segment_trailer, self.binding, state.segment_ordinal, state.next_sequence - 1, reading.utc()) catch return error.SerializationFailure;
                const next_header = control.execute(allocator, .event, .segment_header, self.binding, state.segment_ordinal + 1, null, reading.utc()) catch return error.SerializationFailure;
                state = self.actions.rotate_segment.execute(
                    self.binding,
                    .event,
                    state,
                    trailer,
                    feature_log_format.event_heading,
                    next_header,
                ) catch |failure| return if (failure == error.Cancelled) error.Cancelled else error.RotateFailure;
                record = (build_event.Action{}).execute(&event_id_buffer, self.binding, state, &reading, attributed) catch {
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
        const evidence = self.actions.append_record.execute(
            self.binding,
            .event,
            state,
            row,
            force_flush,
        ) catch |failure| return switch (failure) {
            error.LogFlushFailure => error.FlushFailure,
            error.LogSinkFailure => error.AppendFailure,
            error.Cancelled => error.Cancelled,
        };
        // The row is on disk, so the stream's state advances before the console mirror. A failed mirror (the console
        // is only a mirror, ADR 0018) then leaves the cached state level with the file, not one row behind it.
        state = (advance_state.Action{}).execute(state, row.len, force_flush, reading.monotonic_ms);
        self.event_state = state;
        self.dropped.remove(.event);
        if (self.policy.console) self.actions.write_console.execute(row) catch |failure| return switch (failure) {
            error.ConsoleLogWriteFailure => error.ConsoleFailure,
            error.Cancelled => error.Cancelled,
        };
        return evidence;
    }

    fn openEventStream(
        self: *Runner,
        allocator: std.mem.Allocator,
        reading: log_stream.ClockReading,
    ) PersistError!log_stream.StreamState {
        const recovered = self.actions.recover_stream.execute(
            allocator,
            self.binding,
            .event,
            feature_log_format.event_heading,
        ) catch |failure| return if (failure == error.Cancelled) error.Cancelled else error.RecoveryFailure;
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
                break :blk self.actions.create_segment.execute(
                    self.binding,
                    .event,
                    seed.next_segment_ordinal,
                    seed,
                    feature_log_format.event_heading,
                    header,
                ) catch |failure| return if (failure == error.Cancelled) error.Cancelled else error.CreateFailure;
            },
        };
        return state;
    }

    fn persistPrompt(
        self: *Runner,
        fragment: prompt_log.SanitizedPromptFragment,
        reading: log_stream.ClockReading,
    ) PersistError!log_stream.PersistedEvidence {
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const allocator = scratch.allocator();
        var state = self.prompt_state orelse self.openPromptStream(allocator, reading) catch |failure| return failure;
        var event_id_buffer: [32]u8 = undefined;
        var record = (build_prompt.Action{}).execute(&event_id_buffer, self.binding, state, &reading, fragment) catch return error.SerializationFailure;
        var row = (serialize_prompt.Action{}).execute(allocator, record) catch return error.SerializationFailure;
        const control = serialize_control.Action{};
        const trailer_len = control.measure(
            .prompt,
            .segment_trailer,
            self.binding,
            state.segment_ordinal,
            state.next_sequence - 1,
            reading.utc(),
        ) catch return error.SerializationFailure;
        const next_header_len = control.measure(
            .prompt,
            .segment_header,
            self.binding,
            state.segment_ordinal + 1,
            null,
            reading.utc(),
        ) catch return error.SerializationFailure;
        switch ((rotation.Action{}).execute(state, row.len, trailer_len, feature_log_format.prompt_heading.len + next_header_len)) {
            .append => {},
            .exhausted => return error.SegmentLimitExhausted,
            .rotate => {
                const trailer = control.execute(allocator, .prompt, .segment_trailer, self.binding, state.segment_ordinal, state.next_sequence - 1, reading.utc()) catch return error.SerializationFailure;
                const next_header = control.execute(allocator, .prompt, .segment_header, self.binding, state.segment_ordinal + 1, null, reading.utc()) catch return error.SerializationFailure;
                state = self.actions.rotate_segment.execute(
                    self.binding,
                    .prompt,
                    state,
                    trailer,
                    feature_log_format.prompt_heading,
                    next_header,
                ) catch |failure| return if (failure == error.Cancelled) error.Cancelled else error.RotateFailure;
                record = (build_prompt.Action{}).execute(&event_id_buffer, self.binding, state, &reading, fragment) catch return error.SerializationFailure;
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
        const evidence = self.actions.append_record.execute(
            self.binding,
            .prompt,
            state,
            row,
            force_flush,
        ) catch |failure| return switch (failure) {
            error.LogFlushFailure => error.FlushFailure,
            error.LogSinkFailure => error.AppendFailure,
            error.Cancelled => error.Cancelled,
        };
        // As for an event: the row is on disk, so the state advances before the console mirror.
        state = (advance_state.Action{}).execute(state, row.len, force_flush, reading.monotonic_ms);
        self.prompt_state = state;
        self.dropped.remove(.prompt);
        if (self.policy.console) self.actions.write_console.execute(row) catch |failure| return switch (failure) {
            error.ConsoleLogWriteFailure => error.ConsoleFailure,
            error.Cancelled => error.Cancelled,
        };
        return evidence;
    }

    fn openPromptStream(self: *Runner, allocator: std.mem.Allocator, reading: log_stream.ClockReading) PersistError!log_stream.StreamState {
        const recovered = self.actions.recover_stream.execute(
            allocator,
            self.binding,
            .prompt,
            feature_log_format.prompt_heading,
        ) catch |failure| return if (failure == error.Cancelled) error.Cancelled else error.RecoveryFailure;
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
                break :blk self.actions.create_segment.execute(
                    self.binding,
                    .prompt,
                    seed.next_segment_ordinal,
                    seed,
                    feature_log_format.prompt_heading,
                    header,
                ) catch |failure| return if (failure == error.Cancelled) error.Cancelled else error.CreateFailure;
            },
        };
        return state;
    }

    pub fn reportFailure(self: *Runner, shortcode: telemetry.WorkflowShortcode, failure: log_stream.FailureCode) log_stream.FailureCode {
        self.actions.emit_emergency.execute(shortcode, failure);
        return failure;
    }

    fn block(self: *Runner, shortcode: telemetry.WorkflowShortcode, failure: log_stream.FailureCode) log_stream.Outcome {
        return .{ .blocked = self.reportFailure(shortcode, failure) };
    }

    /// A failure is reported once through the emergency line; a cancellation is no logging failure and
    /// emits none.
    fn stopped(self: *Runner, shortcode: telemetry.WorkflowShortcode, stop: log_stream.Stop) log_stream.Outcome {
        return switch (stop) {
            .blocked => |failure| self.block(shortcode, failure),
            .cancelled => .cancelled,
        };
    }
};

fn retiredBinding(context: *const anyopaque) bool {
    return castConst(context).retired;
}

fn identityBinding(context: *const anyopaque) child_bindings.RuntimeIdentity {
    return context;
}

fn validateEventBinding(
    context: *anyopaque,
    attributed: telemetry.WorkflowTelemetryFact,
) child_bindings.EventValidationOutcome {
    _ = context;
    const definition = (validate_fact.Action{}).execute(attributed.fact) catch {
        return .{ .failed = .LOG_SERIALIZATION_FAILURE };
    };
    return .{ .valid = definition };
}

fn evaluateEventBinding(
    context: *const anyopaque,
    definition: log_event_registry.EventDefinition,
) child_bindings.Decision {
    return if ((threshold.Action{}).execute(castConst(context).policy.*, definition) == .emit) .emit else .drop;
}

fn validatePromptBinding(
    context: *anyopaque,
    fragment: prompt_log.SanitizedPromptFragment,
) child_bindings.StepOutcome {
    _ = context;
    (validate_prompt.Action{}).execute(fragment) catch return .{ .failed = .LOG_SERIALIZATION_FAILURE };
    return .ok;
}

fn evaluatePromptBinding(
    context: *const anyopaque,
    fragment: prompt_log.SanitizedPromptFragment,
) child_bindings.Decision {
    const self = castConst(context);
    if ((select_prompt.Action{}).execute(self.policy.*, fragment) == .drop) return .drop;
    return .emit;
}

fn readClockBinding(context: *anyopaque) child_bindings.ClockOutcome {
    const reading = cast(context).actions.read_clock.execute() catch {
        return .{ .failed = .LOG_SERIALIZATION_FAILURE };
    };
    return .{ .ready = reading };
}

fn acquireBinding(context: *anyopaque, stream: log_stream.Stream) child_bindings.SinkOutcome {
    const self = cast(context);
    self.actions.acquire_lock.execute(self.binding, stream) catch |failure| return child_bindings.SinkOutcome.of(acquire_lock.stop(failure));
    return .ok;
}

/// A cancelled persist drops the stream's cached state (see `Runner.dropped`). Any other failure keeps it: the state
/// already includes a row that reached the file, so only a failed append or flush leaves it behind the bytes.
fn persistEventBinding(
    context: *anyopaque,
    attributed: telemetry.WorkflowTelemetryFact,
    definition: log_event_registry.EventDefinition,
    reading: log_stream.ClockReading,
) child_bindings.PersistenceOutcome {
    const self = cast(context);
    const evidence = self.persistEvent(attributed, definition, reading) catch |failure| {
        if (failure == error.Cancelled) self.forget(.event);
        return child_bindings.PersistenceOutcome.of(persistStop(failure));
    };
    return .{ .persisted = evidence };
}

fn persistPromptBinding(
    context: *anyopaque,
    fragment: prompt_log.SanitizedPromptFragment,
    reading: log_stream.ClockReading,
) child_bindings.PersistenceOutcome {
    const self = cast(context);
    const evidence = self.persistPrompt(fragment, reading) catch |failure| {
        if (failure == error.Cancelled) self.forget(.prompt);
        return child_bindings.PersistenceOutcome.of(persistStop(failure));
    };
    return .{ .persisted = evidence };
}

fn releaseBinding(context: *anyopaque) child_bindings.StepOutcome {
    cast(context).actions.release_lock.execute() catch return .{ .failed = .LOG_RELEASE_FAILURE };
    return .ok;
}

fn prepareBinding(context: *anyopaque, shortcode: telemetry.WorkflowShortcode) log_stream.Outcome {
    return cast(context).invokePrepare(shortcode);
}

fn closeBinding(context: *anyopaque, shortcode: telemetry.WorkflowShortcode) log_stream.Outcome {
    return cast(context).invokeClose(shortcode);
}

fn reportFailureBinding(
    context: *anyopaque,
    shortcode: telemetry.WorkflowShortcode,
    failure: log_stream.FailureCode,
) log_stream.FailureCode {
    return cast(context).reportFailure(shortcode, failure);
}

fn cast(context: *anyopaque) *Runner {
    return @ptrCast(@alignCast(context));
}

fn castConst(context: *const anyopaque) *const Runner {
    return @ptrCast(@alignCast(context));
}

const bindings_vtable: child_bindings.ChildBindings.VTable = .{
    .identity = identityBinding,
    .retired = retiredBinding,
    .validate_event = validateEventBinding,
    .evaluate_event = evaluateEventBinding,
    .validate_prompt = validatePromptBinding,
    .evaluate_prompt = evaluatePromptBinding,
    .read_clock = readClockBinding,
    .acquire = acquireBinding,
    .persist_event = persistEventBinding,
    .persist_prompt = persistPromptBinding,
    .release = releaseBinding,
    .prepare = prepareBinding,
    .close = closeBinding,
    .report_failure = reportFailureBinding,
};

fn processBarrier(context: *anyopaque, fact: telemetry.WorkflowTelemetryFact) log_stream.Outcome {
    const self: *Runner = @ptrCast(@alignCast(context));
    return self.process(fact);
}
fn selectPromptBarrier(context: *anyopaque, fragment: prompt_log.SanitizedPromptFragment) bool {
    return evaluatePromptBinding(context, fragment) == .emit;
}
fn processPromptBarrier(context: *anyopaque, fragment: prompt_log.SanitizedPromptFragment) log_stream.Outcome {
    return cast(context).processPrompt(fragment);
}
fn reportFailureBarrier(context: *anyopaque, shortcode: telemetry.WorkflowShortcode, failure: log_stream.FailureCode) void {
    _ = cast(context).reportFailure(shortcode, failure);
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
    Cancelled,
};

fn persistStop(failure: PersistError) log_stream.Stop {
    return switch (failure) {
        error.SerializationFailure => .{ .blocked = .LOG_SERIALIZATION_FAILURE },
        error.RecoveryFailure,
        error.CreateFailure,
        error.RotateFailure,
        error.AppendFailure,
        error.ConsoleFailure,
        => .{ .blocked = .LOG_SINK_FAILURE },
        error.FlushFailure => .{ .blocked = .LOG_FLUSH_FAILURE },
        error.SegmentLimitExhausted => .{ .blocked = .LOG_SEGMENT_LIMIT_EXHAUSTED },
        error.Cancelled => .cancelled,
    };
}
