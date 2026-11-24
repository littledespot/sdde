const std = @import("std");
const log_binding = @import("../domain/feature_log_binding.zig");
const log_decisions = @import("../domain/feature_log_decisions.zig");
const log_format = @import("../domain/feature_log_format.zig");
const log_limits = @import("../domain/feature_log_limits.zig");
const log_rows = @import("../domain/feature_log_rows.zig");
const log_stop = @import("../domain/feature_log_stop.zig");
const log_stream = @import("../domain/feature_log_stream.zig");
const clock_port = @import("../ports/trusted_log_clock.zig");
const sink_port = @import("../ports/feature_log_sink.zig");

// ADR 0032, ADR 0018: closing a run's feature-log streams as one engine routine. For each stream it first recovers a
// stream whose cached state a cancelled step dropped, under the stream's lock, so the trailer follows the rows that
// really are on disk, then writes the stream's trailer under the lock and closes it, releasing the lock on every
// path. Every stream is closed even when the first stopped, and the first stop is the one reported. It is no
// pipeline node, writes no log row and reports nothing: a stop is its caller's to report. Cancellation reaches it
// only as the sink's `Cancelled`, so a finalization after a cancelled run still closes the streams.

/// The closed set of steps, in execution order. A stop records the step it belongs to in the caller's `Diagnostic`.
pub const Step = enum {
    validate_status,
    read_clock,
    acquire_recovery,
    recover_dropped,
    release_recovery,
    serialize_trailer,
    acquire_close,
    close_stream,
    release_close,
};

/// What a stopped run leaves beside its stop: the first step that stopped. No report reads it.
pub const Diagnostic = struct {
    step: ?Step = null,
};

/// The ports the routine's steps reach. No step receives this set; each takes the one port it uses.
pub const Ports = struct {
    clock: clock_port.Clock,
    acquirer: sink_port.LockAcquirer,
    recoverer: sink_port.StreamRecoverer,
    closer: sink_port.StreamCloser,
    releaser: sink_port.LockReleaser,
};

pub const Inputs = struct {
    allocator: std.mem.Allocator,
    binding: *const log_binding.ValidatedFeatureLogBinding,
};

/// What closes. The run's own end closes both streams of a prepared run and retires it. A stopped activation closes
/// the one stream it opened, with its own clock reading, and leaves the run as it was.
pub const Scope = union(enum) {
    finalize,
    abandon: struct { stream: log_stream.Stream, reading: log_stream.ClockReading },
};

pub const Outcome = union(enum) {
    closed,
    /// Only a prepared, live run is finalized.
    invalid,
    stopped: log_stream.Stop,
};

/// The entry function only sequences the steps and passes each port on. A stream's lock is acquired, used and
/// released in one straight line, and the labeled blocks leave through their end, never past the release.
pub fn run(ports: Ports, inputs: Inputs, runtime: *log_stream.Runtime, scope: Scope, diagnostic: *Diagnostic) Outcome {
    if (scope == .finalize and !steps.mayFinalize(runtime.status())) return invalid(diagnostic);
    const reading = switch (scope) {
        .finalize => steps.readClock(ports.clock) catch return stopped(diagnostic, .read_clock, log_stop.serialization),
        .abandon => |abandoned| abandoned.reading,
    };
    var scratch = std.heap.ArenaAllocator.init(inputs.allocator);
    defer scratch.deinit();
    const allocator = scratch.allocator();
    var abandoned_stream: [1]log_stream.Stream = undefined;
    const streams: []const log_stream.Stream = switch (scope) {
        .finalize => &.{ .event, .prompt },
        .abandon => |abandoned| one: {
            abandoned_stream[0] = abandoned.stream;
            break :one &abandoned_stream;
        },
    };
    var first: ?log_stream.Stop = null;
    for (streams) |kind| {
        const slot = runtime.slot(kind);
        // A stream a cancelled step dropped is recovered first. One that recovery finds closed, or without a segment,
        // has nothing to close.
        if (slot.* == .dropped) recovery: {
            if (steps.acquire(ports.acquirer, inputs.binding, kind)) |stop| {
                keep(&first, diagnostic, .acquire_recovery, stop);
                break :recovery;
            }
            const recovered = steps.recover(ports.recoverer, allocator, inputs.binding, kind);
            const released = steps.release(ports.releaser);
            switch (recovered) {
                .stopped => |stop| keep(&first, diagnostic, .recover_dropped, log_stop.releaseOutranks(stop, released).?),
                .recovered => |recovery| if (log_stop.releaseOutranks(null, released)) |stop| {
                    keep(&first, diagnostic, .release_recovery, stop);
                } else {
                    slot.* = switch (recovery) {
                        .active => |state| .{ .open = state },
                        .empty => .unopened,
                    };
                },
            }
        }
        const state = switch (slot.*) {
            .open => |open| open,
            .unopened, .dropped => continue,
        };
        const trailer = steps.serializeTrailer(allocator, kind, inputs.binding, state, reading) catch {
            keep(&first, diagnostic, .serialize_trailer, log_stop.serialization);
            continue;
        };
        if (steps.acquire(ports.acquirer, inputs.binding, kind)) |stop| {
            keep(&first, diagnostic, .acquire_close, stop);
            continue;
        }
        const closed = steps.closeStream(ports.closer, inputs.binding, kind, state, trailer);
        // The trailer may already be written, so a cancelled close drops the state whatever the release does next.
        if (closed) |stop| if (stop == .cancelled) {
            slot.* = .dropped;
        };
        const released = steps.release(ports.releaser);
        if (log_stop.releaseOutranks(closed, released)) |stop| {
            keep(&first, diagnostic, if (closed != null) .close_stream else .release_close, stop);
            continue;
        }
        slot.* = .unopened;
    }
    if (first) |stop| return .{ .stopped = stop };
    if (scope == .finalize) {
        runtime.prepared = false;
        runtime.retired = true;
    }
    return .closed;
}

fn invalid(diagnostic: *Diagnostic) Outcome {
    diagnostic.step = .validate_status;
    return .invalid;
}

fn stopped(diagnostic: *Diagnostic, step: Step, stop: log_stream.Stop) Outcome {
    diagnostic.step = step;
    return .{ .stopped = stop };
}

/// The first stop is the one reported; a later one is kept out.
fn keep(first: *?log_stream.Stop, diagnostic: *Diagnostic, step: Step, stop: log_stream.Stop) void {
    if (first.* != null) return;
    first.* = stop;
    diagnostic.step = step;
}

/// What recovering a dropped stream gives: its state or its seed, or the stop that kept it from recovering.
pub const Recovered = union(enum) { recovered: log_stream.Recovery, stopped: log_stream.Stop };

/// The steps. Each is one typed function; a step that reaches a port takes exactly that port, and none takes the
/// port set. The pure steps call their domain owners.
pub const steps = struct {
    pub fn mayFinalize(status: log_stream.RuntimeStatus) bool {
        return log_decisions.mayFinalize(status);
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

    pub fn closeStream(
        closer: sink_port.StreamCloser,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        kind: log_stream.Stream,
        state: log_stream.StreamState,
        trailer: []const u8,
    ) ?log_stream.Stop {
        closer.close(binding, kind, state, trailer) catch |failure| return log_stop.ofFlushing(failure);
        return null;
    }

    /// Whether the lock was released. A release is no cancellation point: a sink that reports `Cancelled` here has
    /// failed to release.
    pub fn release(releaser: sink_port.LockReleaser) bool {
        releaser.release() catch return false;
        return true;
    }
};
