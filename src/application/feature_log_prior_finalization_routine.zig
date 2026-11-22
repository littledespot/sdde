const std = @import("std");
const log_binding = @import("../domain/feature_log_binding.zig");
const log_format = @import("../domain/feature_log_format.zig");
const log_limits = @import("../domain/feature_log_limits.zig");
const log_rows = @import("../domain/feature_log_rows.zig");
const log_stop = @import("../domain/feature_log_stop.zig");
const log_stream = @import("../domain/feature_log_stream.zig");
const clock_port = @import("../ports/trusted_log_clock.zig");
const sink_port = @import("../ports/feature_log_sink.zig");

// ADR 0032, ADR 0026: closing one crashed prior run's open tail of one stream as one engine routine. Under that run's
// own stream lock it proves the group still ends in an active tail, recovers the tail by truncating it to its last
// complete row, writes one trailer stamped with the trusted clock's reading now and closes the segment, proves the
// group closed, and releases the lock on every path. It is no pipeline node, writes no log row and reports nothing: a
// stop is its caller's to report. A tail is crashed by assumption, since concurrent runs of one feature are unsupported
// (ADR 0026), so a group that is no longer an active tail under the lock stops the routine and is left as it is.
// Cancellation reaches it only as the sink's `Cancelled`, so the lock is released after a cancelled close; the next
// run finalizes what a partial trailer left, as recovery truncates it first.

/// The closed set of steps, in execution order. A stop records the step it belongs to in the caller's `Diagnostic`.
pub const Step = enum {
    read_clock,
    acquire,
    check_open,
    recover_tail,
    serialize_trailer,
    close_stream,
    verify_closed,
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
    inspector: sink_port.TailInspector,
    recoverer: sink_port.StreamRecoverer,
    closer: sink_port.StreamCloser,
    releaser: sink_port.LockReleaser,
};

/// The closed values the routine reads: the prior run's binding, as its header names it, and the stream whose tail
/// closes.
pub const Inputs = struct {
    allocator: std.mem.Allocator,
    historical: *const log_binding.ValidatedFeatureLogBinding,
    stream: log_stream.Stream,
};

pub const Outcome = union(enum) { closed, stopped: log_stream.Stop };

/// The entry function only sequences the steps and passes each port on. The lock is acquired, used and released in
/// one straight line, and the labeled block leaves through its end, never past the release.
pub fn run(ports: Ports, inputs: Inputs, diagnostic: *Diagnostic) Outcome {
    const reading = steps.readClock(ports.clock) catch return stopped(diagnostic, .read_clock, log_stop.serialization);
    var scratch = std.heap.ArenaAllocator.init(inputs.allocator);
    defer scratch.deinit();
    const allocator = scratch.allocator();
    if (steps.acquire(ports.acquirer, inputs.historical, inputs.stream)) |stop| return stopped(diagnostic, .acquire, stop);
    var earlier: ?log_stream.Stop = null;
    var at: Step = .check_open;
    closing: {
        if (steps.checkOpen(ports.inspector, inputs.historical, inputs.stream)) |stop| {
            earlier = stop;
            break :closing;
        }
        at = .recover_tail;
        const state = switch (steps.recoverTail(ports.recoverer, allocator, inputs.historical, inputs.stream)) {
            .recovered => |recovered| recovered,
            .stopped => |stop| {
                earlier = stop;
                break :closing;
            },
        };
        at = .serialize_trailer;
        const trailer = steps.serializeTrailer(allocator, inputs.stream, inputs.historical, state, reading) catch {
            earlier = log_stop.serialization;
            break :closing;
        };
        at = .close_stream;
        if (steps.closeStream(ports.closer, inputs.historical, inputs.stream, state, trailer)) |stop| {
            earlier = stop;
            break :closing;
        }
        at = .verify_closed;
        if (steps.verifyClosed(ports.inspector, inputs.historical, inputs.stream)) |stop| earlier = stop;
    }
    const released = steps.release(ports.releaser);
    if (log_stop.releaseOutranks(earlier, released)) |stop| return stopped(diagnostic, if (earlier != null) at else .release, stop);
    return .closed;
}

fn stopped(diagnostic: *Diagnostic, step: Step, stop: log_stream.Stop) Outcome {
    diagnostic.step = step;
    return .{ .stopped = stop };
}

/// What recovering the tail gives: the active state a trailer follows, or the stop that kept it from recovering. A group
/// recovery finds closed, or without a segment, is no tail to close.
pub const Recovered = union(enum) { recovered: log_stream.StreamState, stopped: log_stream.Stop };

/// The steps. Each is one typed function; a step that reaches a port takes exactly that port, and none takes the port
/// set. The pure steps call their domain owners.
pub const steps = struct {
    pub fn readClock(clock: clock_port.Clock) error{LogClockReadFailure}!log_stream.ClockReading {
        return clock.now() catch error.LogClockReadFailure;
    }

    pub fn acquire(
        acquirer: sink_port.LockAcquirer,
        historical: *const log_binding.ValidatedFeatureLogBinding,
        stream: log_stream.Stream,
    ) ?log_stream.Stop {
        acquirer.acquire(historical, stream, log_limits.stream_lock_deadline_ms) catch |failure| return log_stop.ofLock(failure);
        return null;
    }

    /// The group is read again under the lock: a tail another process closed or changed since discovery is not this
    /// routine's to touch.
    pub fn checkOpen(
        inspector: sink_port.TailInspector,
        historical: *const log_binding.ValidatedFeatureLogBinding,
        stream: log_stream.Stream,
    ) ?log_stream.Stop {
        return expect(inspector, historical, stream, .active);
    }

    pub fn recoverTail(
        recoverer: sink_port.StreamRecoverer,
        allocator: std.mem.Allocator,
        historical: *const log_binding.ValidatedFeatureLogBinding,
        stream: log_stream.Stream,
    ) Recovered {
        const recovery = recoverer.recover(historical, stream, log_format.segmentHeading(stream), allocator) catch |failure| return .{ .stopped = log_stop.ofSink(failure) };
        return switch (recovery) {
            .active => |state| .{ .recovered = state },
            .empty => .{ .stopped = log_stop.sink_failure },
        };
    }

    /// The trailer that follows the tail's last row, stamped with the reading taken now.
    pub fn serializeTrailer(
        allocator: std.mem.Allocator,
        stream: log_stream.Stream,
        historical: *const log_binding.ValidatedFeatureLogBinding,
        state: log_stream.StreamState,
        reading: log_stream.ClockReading,
    ) error{LogSerializationFailure}![]u8 {
        return log_rows.serializeControl(allocator, stream, .segment_trailer, historical, state.segment_ordinal, state.next_sequence - 1, reading.utc());
    }

    pub fn closeStream(
        closer: sink_port.StreamCloser,
        historical: *const log_binding.ValidatedFeatureLogBinding,
        stream: log_stream.Stream,
        state: log_stream.StreamState,
        trailer: []const u8,
    ) ?log_stream.Stop {
        closer.close(historical, stream, state, trailer) catch |failure| return log_stop.ofFlushing(failure);
        return null;
    }

    /// The group is read once more: it must end closed, so a trailer that did not land is a stop, not a success.
    pub fn verifyClosed(
        inspector: sink_port.TailInspector,
        historical: *const log_binding.ValidatedFeatureLogBinding,
        stream: log_stream.Stream,
    ) ?log_stream.Stop {
        return expect(inspector, historical, stream, .closed);
    }

    /// Whether the lock was released. A release is no cancellation point: a sink that reports `Cancelled` here has
    /// failed to release.
    pub fn release(releaser: sink_port.LockReleaser) bool {
        releaser.release() catch return false;
        return true;
    }

    fn expect(
        inspector: sink_port.TailInspector,
        historical: *const log_binding.ValidatedFeatureLogBinding,
        stream: log_stream.Stream,
        wanted: log_stream.TailState,
    ) ?log_stream.Stop {
        const found = inspector.inspect(historical, stream) catch |failure| return log_stop.ofSink(failure);
        return if (found == wanted) null else log_stop.sink_failure;
    }
};
