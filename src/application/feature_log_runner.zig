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
        return .{ .context = self, .process_fn = processBarrier };
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

    pub fn processPromptBatch(self: *Runner, owner: *prompt_log.BatchOwner) log_stream.Outcome {
        defer prompt_log.deinitBatch(owner);
        var last_persisted: ?log_stream.PersistedEvidence = null;
        for (prompt_log.batch(owner)) |fragment| switch (self.processPrompt(fragment)) {
            .dropped => {},
            .persisted => |evidence| last_persisted = evidence,
            .blocked => |failure| return .{ .blocked = failure },
        };
        return if (last_persisted) |evidence| .{ .persisted = evidence } else .dropped;
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
            if (self.prepareOne(.event, reading)) |failure| return self.block(shortcode, failure);
        }
        if (self.policy.prompt_capture.len != 0 and self.prompt_state == null) {
            if (self.prepareOne(.prompt, reading)) |failure| return self.block(shortcode, failure);
        }
        self.prepared = true;
        return .dropped;
    }

    fn invokeClose(self: *Runner, shortcode: telemetry.WorkflowShortcode) log_stream.Outcome {
        if (self.retired) return self.block(shortcode, .LOG_SINK_FAILURE);
        const reading = self.actions.read_clock.execute() catch return self.block(shortcode, .LOG_SERIALIZATION_FAILURE);
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

    fn prepareOne(self: *Runner, stream: log_stream.Stream, reading: log_stream.ClockReading) ?log_stream.FailureCode {
        self.actions.acquire_lock.execute(self.binding, stream) catch return .LOG_LOCK_TIMEOUT;
        var failure: ?log_stream.FailureCode = null;
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const state = switch (stream) {
            .event => self.openEventStream(scratch.allocator(), reading),
            .prompt => self.openPromptStream(scratch.allocator(), reading),
        } catch |open_failure| blk: {
            failure = failureCode(open_failure);
            break :blk null;
        };
        self.actions.release_lock.execute() catch return .LOG_RELEASE_FAILURE;
        if (failure) |code| return code;
        switch (stream) {
            .event => self.event_state = state.?,
            .prompt => self.prompt_state = state.?,
        }
        return null;
    }

    fn closeOne(self: *Runner, stream: log_stream.Stream, state: log_stream.StreamState, reading: log_stream.ClockReading) ?log_stream.FailureCode {
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
        self.actions.acquire_lock.execute(self.binding, stream) catch return .LOG_LOCK_TIMEOUT;
        var failure: ?log_stream.FailureCode = null;
        self.actions.close_stream.execute(self.binding, stream, state, trailer) catch |close_failure| {
            failure = if (close_failure == error.LogFlushFailure) .LOG_FLUSH_FAILURE else .LOG_SINK_FAILURE;
        };
        self.actions.release_lock.execute() catch return .LOG_RELEASE_FAILURE;
        return failure;
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
                state = self.actions.rotate_segment.execute(
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
        const evidence = self.actions.append_record.execute(
            self.binding,
            .event,
            state,
            row,
            force_flush,
        ) catch |failure| return switch (failure) {
            error.LogFlushFailure => error.FlushFailure,
            error.LogSinkFailure => error.AppendFailure,
        };
        if (self.policy.console) self.actions.write_console.execute(row) catch return error.ConsoleFailure;
        state = (advance_state.Action{}).execute(state, row.len, force_flush, reading.monotonic_ms);
        self.event_state = state;
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
                break :blk self.actions.create_segment.execute(
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
        fragment: prompt_log.SanitizedPromptFragment,
        reading: log_stream.ClockReading,
    ) PersistError!log_stream.PersistedEvidence {
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
                state = self.actions.rotate_segment.execute(
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
        const evidence = self.actions.append_record.execute(
            self.binding,
            .prompt,
            state,
            row,
            force_flush,
        ) catch |failure| return switch (failure) {
            error.LogFlushFailure => error.FlushFailure,
            error.LogSinkFailure => error.AppendFailure,
        };
        if (self.policy.console) self.actions.write_console.execute(row) catch return error.ConsoleFailure;
        state = (advance_state.Action{}).execute(state, row.len, force_flush, reading.monotonic_ms);
        self.prompt_state = state;
        return evidence;
    }

    fn openPromptStream(self: *Runner, allocator: std.mem.Allocator, reading: log_stream.ClockReading) PersistError!log_stream.StreamState {
        const recovered = self.actions.recover_stream.execute(
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
                break :blk self.actions.create_segment.execute(
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

    pub fn reportFailure(self: *Runner, shortcode: telemetry.WorkflowShortcode, failure: log_stream.FailureCode) log_stream.FailureCode {
        self.actions.emit_emergency.execute(shortcode, failure);
        return failure;
    }

    fn block(self: *Runner, shortcode: telemetry.WorkflowShortcode, failure: log_stream.FailureCode) log_stream.Outcome {
        return .{ .blocked = self.reportFailure(shortcode, failure) };
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
    return if ((threshold.Action{}).execute(castConst(context).policy.*, definition.level) == .emit) .emit else .drop;
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
    if ((select_prompt.Action{}).execute(self.policy.*, fragment) == .drop or
        (threshold.Action{}).execute(self.policy.*, .debug) == .drop) return .drop;
    return .emit;
}

fn readClockBinding(context: *anyopaque) child_bindings.ClockOutcome {
    const reading = cast(context).actions.read_clock.execute() catch {
        return .{ .failed = .LOG_SERIALIZATION_FAILURE };
    };
    return .{ .ready = reading };
}

fn acquireBinding(context: *anyopaque, stream: log_stream.Stream) child_bindings.StepOutcome {
    const self = cast(context);
    self.actions.acquire_lock.execute(self.binding, stream) catch return .{ .failed = .LOG_LOCK_TIMEOUT };
    return .ok;
}

fn persistEventBinding(
    context: *anyopaque,
    attributed: telemetry.WorkflowTelemetryFact,
    definition: log_event_registry.EventDefinition,
    reading: log_stream.ClockReading,
) child_bindings.PersistenceOutcome {
    const evidence = cast(context).persistEvent(attributed, definition, reading) catch |failure| {
        return .{ .failed = failureCode(failure) };
    };
    return .{ .persisted = evidence };
}

fn persistPromptBinding(
    context: *anyopaque,
    fragment: prompt_log.SanitizedPromptFragment,
    reading: log_stream.ClockReading,
) child_bindings.PersistenceOutcome {
    const evidence = cast(context).persistPrompt(fragment, reading) catch |failure| {
        return .{ .failed = failureCode(failure) };
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

fn failureCode(failure: PersistError) log_stream.FailureCode {
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
