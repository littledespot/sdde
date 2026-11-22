const std = @import("std");
const log_binding = @import("../domain/feature_log_binding.zig");
const log_format = @import("../domain/feature_log_format.zig");
const log_limits = @import("../domain/feature_log_limits.zig");
const log_policy = @import("../domain/log_policy.zig");
const log_rows = @import("../domain/feature_log_rows.zig");
const log_stop = @import("../domain/feature_log_stop.zig");
const log_stream = @import("../domain/feature_log_stream.zig");
const clock_port = @import("../ports/trusted_log_clock.zig");
const sink_port = @import("../ports/feature_log_sink.zig");

// ADR 0032, ADR 0018: preparing a run's feature-log streams as one engine routine, before the log can be the active
// observer. It recovers or creates the first segment of the event stream and, when the policy captures prompts, of
// the prompt stream, each under its own stream lock, released on every path. It is no pipeline node, writes no log row
// and reports nothing: a stop is its caller's to report. Cancellation reaches it only as the sink's `Cancelled`, so
// the lock is released after a cancelled open. A run whose activation stopped is never finalized, so a stopped prompt
// stream leaves its caller the event stream it opened to close, with the activation's own clock reading.

/// The closed set of steps, in execution order. A stop records the step it belongs to in the caller's `Diagnostic`.
pub const Step = enum { check_status, read_clock, acquire, recover, serialize_header, create, release };

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
    releaser: sink_port.LockReleaser,
};

pub const Inputs = struct {
    allocator: std.mem.Allocator,
    policy: *const log_policy.CompiledLoggingPolicy,
    binding: *const log_binding.ValidatedFeatureLogBinding,
};

/// The stream a stopped activation opened and must close, and the reading it closes with.
pub const Abandon = struct { stream: log_stream.Stream, reading: log_stream.ClockReading };

pub const Outcome = union(enum) {
    /// Every enabled stream is open, or the run was already prepared.
    prepared,
    stopped: struct { stop: log_stream.Stop, abandon: ?Abandon },
};

/// The entry function only sequences the steps and passes each port on. A stream's lock is acquired, used and
/// released in one straight line, and the labeled block leaves through its end, never past the release.
pub fn run(ports: Ports, inputs: Inputs, runtime: *log_stream.Runtime, diagnostic: *Diagnostic) Outcome {
    if (runtime.retired) return stopped(diagnostic, .check_status, log_stop.sink_failure, null);
    if (runtime.prepared) return .prepared;
    const reading = steps.readClock(ports.clock) catch return stopped(diagnostic, .read_clock, log_stop.serialization, null);
    var scratch = std.heap.ArenaAllocator.init(inputs.allocator);
    defer scratch.deinit();
    const allocator = scratch.allocator();
    const enabled = [_]bool{ true, steps.capturesPrompts(inputs.policy) };
    for ([_]log_stream.Stream{ .event, .prompt }, enabled) |kind, wanted| {
        const slot = runtime.slot(kind);
        if (!wanted or slot.* == .open) continue;
        // A stopped prompt stream leaves the event stream open, so its caller closes it.
        const abandon: ?Abandon = if (kind == .prompt) .{ .stream = .event, .reading = reading } else null;
        if (steps.acquire(ports.acquirer, inputs.binding, kind)) |stop| return stopped(diagnostic, .acquire, stop, abandon);
        var failure: ?log_stream.Stop = null;
        var failed_at: Step = .recover;
        var opened: ?log_stream.StreamState = null;
        open: {
            const recovery = switch (steps.recover(ports.recoverer, allocator, inputs.binding, kind)) {
                .recovered => |value| value,
                .stopped => |stop| {
                    failure = stop;
                    break :open;
                },
            };
            switch (recovery) {
                .active => |state| opened = state,
                .empty => |seed| {
                    const header = steps.serializeHeader(allocator, kind, inputs.binding, seed, reading) catch {
                        failure = log_stop.serialization;
                        failed_at = .serialize_header;
                        break :open;
                    };
                    switch (steps.create(ports.creator, inputs.binding, kind, seed, header)) {
                        .created => |state| opened = state,
                        .stopped => |stop| {
                            failure = stop;
                            failed_at = .create;
                        },
                    }
                },
            }
        }
        // The lock is released on every path, a cancelled open included; a release that fails outranks the open's stop.
        const released = steps.release(ports.releaser);
        if (log_stop.releaseOutranks(failure, released)) |stop| return stopped(diagnostic, if (failure != null) failed_at else .release, stop, abandon);
        slot.* = .{ .open = opened.? };
    }
    runtime.prepared = true;
    return .prepared;
}

fn stopped(diagnostic: *Diagnostic, step: Step, stop: log_stream.Stop, abandon: ?Abandon) Outcome {
    diagnostic.step = step;
    return .{ .stopped = .{ .stop = stop, .abandon = abandon } };
}

/// What recovering a stream gives: its state or its seed, or the stop that kept it from recovering.
pub const Recovered = union(enum) { recovered: log_stream.Recovery, stopped: log_stream.Stop };

/// What creating a stream's first segment gives: its state, or the stop that kept it from being created.
pub const Created = union(enum) { created: log_stream.StreamState, stopped: log_stream.Stop };

/// The steps. Each is one typed function; a step that reaches a port takes exactly that port, and none takes the
/// port set. The pure steps call their domain owners.
pub const steps = struct {
    pub fn readClock(clock: clock_port.Clock) error{LogClockReadFailure}!log_stream.ClockReading {
        return clock.now() catch error.LogClockReadFailure;
    }

    pub fn capturesPrompts(policy: *const log_policy.CompiledLoggingPolicy) bool {
        return log_policy.promptCaptureEnabled(policy.*);
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

    /// The header of the segment a stream with none opens with.
    pub fn serializeHeader(
        allocator: std.mem.Allocator,
        kind: log_stream.Stream,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        seed: log_stream.StreamSeed,
        reading: log_stream.ClockReading,
    ) error{LogSerializationFailure}![]u8 {
        return log_rows.serializeControl(allocator, kind, .segment_header, binding, seed.next_segment_ordinal, null, reading.utc());
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

    /// Whether the lock was released. A release is no cancellation point: a sink that reports `Cancelled` here has
    /// failed to release.
    pub fn release(releaser: sink_port.LockReleaser) bool {
        releaser.release() catch return false;
        return true;
    }
};
