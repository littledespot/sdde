const std = @import("std");
const log_binding = @import("../domain/feature_log_binding.zig");
const log_decisions = @import("../domain/feature_log_decisions.zig");
const log_event_registry = @import("../domain/log_event_registry.zig");
const log_format = @import("../domain/feature_log_format.zig");
const log_limits = @import("../domain/feature_log_limits.zig");
const log_policy = @import("../domain/log_policy.zig");
const log_rows = @import("../domain/feature_log_rows.zig");
const log_stop = @import("../domain/feature_log_stop.zig");
const log_stream = @import("../domain/feature_log_stream.zig");
const prompt_log = @import("../domain/sanitized_prompt_log.zig");
const telemetry = @import("../domain/telemetry.zig");
const clock_port = @import("../ports/trusted_log_clock.zig");
const console_port = @import("../ports/console_log_sink.zig");
const sink_port = @import("../ports/feature_log_sink.zig");

// ADR 0032, ADR 0018: persisting one fact or prompt fragment as one engine routine. It validates the input, decides
// whether the policy emits it, reads the clock, takes the stream's lock, opens the stream when it has no cached state,
// renders the row against the stream's state, rotates a full segment first, appends the row, advances the state,
// mirrors the row to the console, and releases the lock on every path. It is no pipeline node, writes no log row of
// its own and reports nothing: a stop is its caller's to report. Cancellation reaches it only as the sink's
// `Cancelled`; a stream whose step was cancelled drops its cached state, because the file may be ahead of it, and is
// recovered from its bytes the next time. A release failure is a logging failure of its own and outranks the stop
// that preceded it.

/// The closed set of steps, in execution order. A stop records the step it belongs to in the caller's `Diagnostic`.
pub const Step = enum {
    check_status,
    validate,
    select,
    read_clock,
    acquire,
    recover,
    serialize_header,
    create,
    render,
    measure,
    rotate,
    append,
    mirror,
    release,
};

/// What a stopped run leaves beside its stop: the step. No report reads it.
pub const Diagnostic = struct {
    step: ?Step = null,
};

/// The ports the routine's steps reach. No step receives this set; each takes the one port it uses.
pub const Ports = struct {
    clock: clock_port.Clock,
    acquirer: sink_port.LockAcquirer,
    recoverer: sink_port.StreamRecoverer,
    creator: sink_port.SegmentCreator,
    rotator: sink_port.SegmentRotator,
    appender: sink_port.RecordAppender,
    console: console_port.Sink,
    releaser: sink_port.LockReleaser,
};

pub const Inputs = struct {
    allocator: std.mem.Allocator,
    policy: *const log_policy.CompiledLoggingPolicy,
    binding: *const log_binding.ValidatedFeatureLogBinding,
};

/// What is persisted. The tag is the stream, so an input cannot meet the other stream's state or heading.
pub const Input = union(log_stream.Stream) {
    event: telemetry.WorkflowTelemetryFact,
    prompt: prompt_log.SanitizedPromptFragment,
};

const Failed = struct { step: Step, stop: log_stream.Stop };

/// The entry function only sequences the steps and passes each port on. The stream's lock is acquired, used and
/// released in one straight line, and the labeled block leaves through its end, never past the release.
pub fn run(ports: Ports, inputs: Inputs, runtime: *log_stream.Runtime, input: Input, diagnostic: *Diagnostic) log_stream.Result {
    if (runtime.retired) return stopped(diagnostic, .check_status, log_stop.sink_failure);
    const kind: log_stream.Stream = input;
    const row: log_rows.Row = switch (input) {
        .event => |attributed| event: {
            const definition = steps.validateEvent(attributed.fact) catch return stopped(diagnostic, .validate, log_stop.serialization);
            if (!steps.emits(inputs.policy, definition)) return .dropped;
            break :event .{ .event = .{ .attributed = attributed, .definition = definition } };
        },
        .prompt => |fragment| prompt: {
            steps.validatePrompt(fragment) catch return stopped(diagnostic, .validate, log_stop.serialization);
            if (!steps.captures(inputs.policy)) return .dropped;
            break :prompt .{ .prompt = fragment };
        },
    };
    const reading = steps.readClock(ports.clock) catch return stopped(diagnostic, .read_clock, log_stop.serialization);
    if (steps.acquire(ports.acquirer, inputs.binding, kind)) |stop| return stopped(diagnostic, .acquire, stop);
    var scratch = std.heap.ArenaAllocator.init(inputs.allocator);
    defer scratch.deinit();
    const allocator = scratch.allocator();
    const slot = runtime.slot(kind);
    var evidence: log_stream.PersistedEvidence = undefined;
    const failed: ?Failed = work: {
        var state: log_stream.StreamState = switch (slot.*) {
            .open => |open| open,
            // A stream with no cached state is recovered from its bytes, or given its first segment.
            .unopened, .dropped => opened: {
                const recovery = switch (steps.recover(ports.recoverer, allocator, inputs.binding, kind)) {
                    .recovered => |value| value,
                    .stopped => |stop| break :work .{ .step = .recover, .stop = stop },
                };
                break :opened switch (recovery) {
                    .active => |active| active,
                    .empty => |seed| created: {
                        const header = steps.serializeHeader(allocator, kind, inputs.binding, seed.next_segment_ordinal, reading) catch break :work .{ .step = .serialize_header, .stop = log_stop.serialization };
                        break :created switch (steps.create(ports.creator, inputs.binding, kind, seed, header)) {
                            .created => |created_state| created_state,
                            .stopped => |stop| break :work .{ .step = .create, .stop = stop },
                        };
                    },
                };
            },
        };
        var bytes = steps.render(allocator, inputs.binding, state, reading, row) catch break :work .{ .step = .render, .stop = log_stop.serialization };
        const trailer_length = steps.measureTrailer(kind, inputs.binding, state, reading) catch break :work .{ .step = .measure, .stop = log_stop.serialization };
        const next_header_length = steps.measureHeader(kind, inputs.binding, state.segment_ordinal + 1, reading) catch break :work .{ .step = .measure, .stop = log_stop.serialization };
        const heading = log_format.segmentHeading(kind);
        switch (steps.rotation(state, bytes.len, trailer_length, heading.len + next_header_length)) {
            .append => {},
            .exhausted => break :work .{ .step = .rotate, .stop = .{ .blocked = .LOG_SEGMENT_LIMIT_EXHAUSTED } },
            .rotate => {
                const trailer = steps.serializeTrailer(allocator, kind, inputs.binding, state, reading) catch break :work .{ .step = .rotate, .stop = log_stop.serialization };
                const next_header = steps.serializeHeader(allocator, kind, inputs.binding, state.segment_ordinal + 1, reading) catch break :work .{ .step = .rotate, .stop = log_stop.serialization };
                state = switch (steps.rotate(ports.rotator, inputs.binding, kind, state, trailer, heading, next_header)) {
                    .rotated => |rotated| rotated,
                    .stopped => |stop| break :work .{ .step = .rotate, .stop = stop },
                };
                // The file now holds the closed segment and the next one's header, so the cache names the next one even
                // when the append after it stops: a close then finds the segment the file is really in.
                slot.* = .{ .open = state };
                // The row names the segment it opens, not the full one it replaced.
                bytes = steps.render(allocator, inputs.binding, state, reading, row) catch break :work .{ .step = .render, .stop = log_stop.serialization };
            },
        }
        const flushes = steps.forcesFlush(inputs.policy, row, state, reading);
        evidence = switch (steps.append(ports.appender, inputs.binding, kind, state, bytes, flushes)) {
            .appended => |appended| appended,
            .stopped => |stop| break :work .{ .step = .append, .stop = stop },
        };
        // The row is on disk, so the state advances before the console mirror. A failed mirror (the console is only a
        // mirror, ADR 0018) then leaves the cached state level with the file, not one row behind it.
        slot.* = .{ .open = steps.advance(state, bytes.len, flushes, reading.monotonic_ms) };
        if (inputs.policy.console) {
            if (steps.mirror(ports.console, bytes)) |stop| break :work .{ .step = .mirror, .stop = stop };
        }
        break :work null;
    };
    // A cancelled step may have left the file ahead of the cache, so the stream's state is dropped.
    if (failed) |stop| if (stop.stop == .cancelled) {
        slot.* = .dropped;
    };
    // The lock is released whatever the work did, a cancelled step included.
    const released = steps.release(ports.releaser);
    const earlier: ?log_stream.Stop = if (failed) |stop| stop.stop else null;
    if (log_stop.releaseOutranks(earlier, released)) |stop| return stopped(diagnostic, if (failed) |step| step.step else .release, stop);
    return .{ .persisted = evidence };
}

fn stopped(diagnostic: *Diagnostic, step: Step, stop: log_stream.Stop) log_stream.Result {
    diagnostic.step = step;
    return .{ .stopped = stop };
}

/// What recovering a stream gives: its state or its seed, or the stop that kept it from recovering.
pub const Recovered = union(enum) { recovered: log_stream.Recovery, stopped: log_stream.Stop };

/// What creating a stream's first segment gives: its state, or the stop that kept it from being created.
pub const Created = union(enum) { created: log_stream.StreamState, stopped: log_stream.Stop };

/// What rotating a full segment gives: the next segment's state, or the stop that kept it from rotating.
pub const Rotated = union(enum) { rotated: log_stream.StreamState, stopped: log_stream.Stop };

/// What appending a row gives: its evidence, or the stop that kept it from being appended.
pub const Appended = union(enum) { appended: log_stream.PersistedEvidence, stopped: log_stream.Stop };

/// The steps. Each is one typed function; a step that reaches a port takes exactly that port, and none takes the
/// port set. The pure steps call their domain owners.
pub const steps = struct {
    pub fn validateEvent(fact: telemetry.TelemetryFact) error{InvalidLogEventFact}!log_event_registry.EventDefinition {
        return log_rows.validateEvent(fact);
    }

    pub fn validatePrompt(fragment: prompt_log.SanitizedPromptFragment) error{InvalidPromptLogFragment}!void {
        return log_rows.validatePrompt(fragment);
    }

    /// An ADR-required event is emitted at every threshold (§26.5); every other event follows the configured one.
    pub fn emits(policy: *const log_policy.CompiledLoggingPolicy, definition: log_event_registry.EventDefinition) bool {
        return log_decisions.emission(policy.*, definition) == .emit;
    }

    pub fn captures(policy: *const log_policy.CompiledLoggingPolicy) bool {
        return log_decisions.capture(policy.*) == .capture;
    }

    pub fn readClock(clock: clock_port.Clock) error{LogClockReadFailure}!log_stream.ClockReading {
        return clock.now() catch error.LogClockReadFailure;
    }

    pub fn acquire(
        acquirer: sink_port.LockAcquirer,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        kind: log_stream.Stream,
    ) ?log_stream.Stop {
        acquirer.acquire(binding, kind, log_limits.stream_lock_deadline_ms) catch |failure| return log_stop.ofLock(failure);
        return null;
    }

    pub fn recover(
        recoverer: sink_port.StreamRecoverer,
        allocator: std.mem.Allocator,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        kind: log_stream.Stream,
    ) Recovered {
        const recovery = recoverer.recover(binding, kind, log_format.segmentHeading(kind), allocator) catch |failure| return .{ .stopped = log_stop.ofSink(failure) };
        return .{ .recovered = recovery };
    }

    /// The header of a segment: the first of a stream with none, or the one a rotation opens.
    pub fn serializeHeader(
        allocator: std.mem.Allocator,
        kind: log_stream.Stream,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        segment_ordinal: u16,
        reading: log_stream.ClockReading,
    ) error{LogSerializationFailure}![]u8 {
        return log_rows.serializeControl(allocator, kind, .segment_header, binding, segment_ordinal, null, reading.utc());
    }

    /// The trailer that follows the stream's last row.
    pub fn serializeTrailer(
        allocator: std.mem.Allocator,
        kind: log_stream.Stream,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        state: log_stream.StreamState,
        reading: log_stream.ClockReading,
    ) error{LogSerializationFailure}![]u8 {
        return log_rows.serializeControl(allocator, kind, .segment_trailer, binding, state.segment_ordinal, state.next_sequence - 1, reading.utc());
    }

    pub fn measureTrailer(
        kind: log_stream.Stream,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        state: log_stream.StreamState,
        reading: log_stream.ClockReading,
    ) error{LogSerializationFailure}!usize {
        return log_rows.measureControl(kind, .segment_trailer, binding, state.segment_ordinal, state.next_sequence - 1, reading.utc());
    }

    pub fn measureHeader(
        kind: log_stream.Stream,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        segment_ordinal: u16,
        reading: log_stream.ClockReading,
    ) error{LogSerializationFailure}!usize {
        return log_rows.measureControl(kind, .segment_header, binding, segment_ordinal, null, reading.utc());
    }

    pub fn create(
        creator: sink_port.SegmentCreator,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        kind: log_stream.Stream,
        seed: log_stream.StreamSeed,
        header: []const u8,
    ) Created {
        const state = creator.create(binding, kind, seed.next_segment_ordinal, seed, log_format.segmentHeading(kind), header) catch |failure| return .{ .stopped = log_stop.ofSink(failure) };
        return .{ .created = state };
    }

    /// Builds the row against the stream's state and serialises it into `allocator`'s memory.
    pub fn render(
        allocator: std.mem.Allocator,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        state: log_stream.StreamState,
        reading: log_stream.ClockReading,
        row: log_rows.Row,
    ) error{LogSerializationFailure}![]u8 {
        return log_rows.render(allocator, binding, state, &reading, row);
    }

    pub fn rotation(state: log_stream.StreamState, row_bytes: usize, trailer_bytes: usize, next_header_bytes: usize) log_decisions.Rotation {
        return log_decisions.rotation(state, row_bytes, trailer_bytes, next_header_bytes);
    }

    pub fn rotate(
        rotator: sink_port.SegmentRotator,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        kind: log_stream.Stream,
        state: log_stream.StreamState,
        trailer: []const u8,
        heading: []const u8,
        header: []const u8,
    ) Rotated {
        const next = rotator.rotate(binding, kind, state, trailer, heading, header) catch |failure| return .{ .stopped = log_stop.ofSink(failure) };
        return .{ .rotated = next };
    }

    /// Whether the row forces a flush (26-security.md): an event carries its own level and type, a prompt fragment is
    /// a debug-level `model.prompt_fragment`.
    pub fn forcesFlush(
        policy: *const log_policy.CompiledLoggingPolicy,
        row: log_rows.Row,
        state: log_stream.StreamState,
        reading: log_stream.ClockReading,
    ) bool {
        const key = log_rows.flushKey(row);
        return log_decisions.flush(policy.*, key.level, key.event_type, state, reading.monotonic_ms) == .flush;
    }

    pub fn append(
        appender: sink_port.RecordAppender,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        kind: log_stream.Stream,
        state: log_stream.StreamState,
        row_bytes: []const u8,
        flush: bool,
    ) Appended {
        const evidence = appender.append(binding, kind, state, row_bytes, flush) catch |failure| return .{ .stopped = log_stop.ofFlushing(failure) };
        return .{ .appended = evidence };
    }

    /// The stream's state after the row reached its file.
    pub fn advance(state: log_stream.StreamState, row_bytes: usize, flushed: bool, monotonic_ms: u64) log_stream.StreamState {
        return log_decisions.advance(state, row_bytes, flushed, monotonic_ms);
    }

    /// The console is only a mirror: a failed write is a sink failure, and a cancellation is none.
    pub fn mirror(console: console_port.Sink, row_bytes: []const u8) ?log_stream.Stop {
        console.write(row_bytes) catch |failure| return switch (failure) {
            error.Cancelled => .cancelled,
            error.ConsoleWriteFailure => log_stop.sink_failure,
        };
        return null;
    }

    /// Whether the lock was released. A release is no cancellation point: a sink that reports `Cancelled` here has
    /// failed to release.
    pub fn release(releaser: sink_port.LockReleaser) bool {
        releaser.release() catch return false;
        return true;
    }
};
