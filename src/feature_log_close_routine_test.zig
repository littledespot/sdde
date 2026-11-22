const std = @import("std");
const routine = @import("application/feature_log_close_routine.zig");
const feature_identity = @import("domain/feature_identity.zig");
const log_binding = @import("domain/feature_log_binding.zig");
const log_rows = @import("domain/feature_log_rows.zig");
const log_stream = @import("domain/feature_log_stream.zig");
const telemetry = @import("domain/telemetry.zig");
const clock_port = @import("ports/trusted_log_clock.zig");
const sink_port = @import("ports/feature_log_sink.zig");

const Kind = enum { clock, acquire, recover, close, release };
const Event = struct { kind: Kind, stream: ?log_stream.Stream };

const reading: log_stream.ClockReading = .{ .occurred_at_utc = "2026-08-30T10:15:30Z".*, .unix_ms = 1_788_087_330_000, .monotonic_ms = 1 };

fn stateAt(next_sequence: u64) log_stream.StreamState {
    return .{ .segment_ordinal = 1, .next_sequence = next_sequence, .segment_bytes = 500, .segment_count = 1, .total_segment_count = 1, .records_since_flush = 0, .last_flush_monotonic_ms = 0 };
}

/// Fake ports that record the order of their calls and fail where told, per stream.
const Fake = struct {
    events: [32]Event = undefined,
    count: usize = 0,
    locked: ?log_stream.Stream = null,
    clock_fails: bool = false,
    acquire_fails: [2]?sink_port.Error = .{ null, null },
    recover_fails: [2]?sink_port.Error = .{ null, null },
    recovery: [2]log_stream.Recovery = .{ .{ .active = stateAt(5) }, .{ .active = stateAt(5) } },
    close_fails: [2]?sink_port.Error = .{ null, null },
    release_fails: [2]?sink_port.Error = .{ null, null },
    trailers: [2][512]u8 = undefined,
    trailer_lengths: [2]usize = .{ 0, 0 },
    closed_state: [2]?log_stream.StreamState = .{ null, null },

    fn ports(self: *Fake) routine.Ports {
        return .{
            .clock = .{ .context = self, .now_fn = now },
            .acquirer = .{ .context = self, .acquire_fn = acquire },
            .recoverer = .{ .context = self, .recover_fn = recover },
            .closer = .{ .context = self, .close_fn = close },
            .releaser = .{ .context = self, .release_fn = release },
        };
    }

    fn record(self: *Fake, kind: Kind, stream: ?log_stream.Stream) void {
        self.events[self.count] = .{ .kind = kind, .stream = stream };
        self.count += 1;
    }

    fn kinds(self: *const Fake, out: *[32]Kind) []const Kind {
        for (self.events[0..self.count], 0..) |event, index| out[index] = event.kind;
        return out[0..self.count];
    }

    fn now(context: *anyopaque) clock_port.Error!log_stream.ClockReading {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.clock, null);
        if (self.clock_fails) return error.ClockFailure;
        return reading;
    }
    fn acquire(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, _: u16) sink_port.Error!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.acquire, stream);
        if (self.acquire_fails[@intFromEnum(stream)]) |failure| return failure;
        self.locked = stream;
    }
    fn recover(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, _: []const u8, _: std.mem.Allocator) sink_port.Error!log_stream.Recovery {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.recover, stream);
        if (self.recover_fails[@intFromEnum(stream)]) |failure| return failure;
        return self.recovery[@intFromEnum(stream)];
    }
    fn close(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, state: log_stream.StreamState, trailer: []const u8) sink_port.Error!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.close, stream);
        const index = @intFromEnum(stream);
        @memcpy(self.trailers[index][0..trailer.len], trailer);
        self.trailer_lengths[index] = trailer.len;
        self.closed_state[index] = state;
        if (self.close_fails[index]) |failure| return failure;
    }
    fn release(context: *anyopaque) sink_port.Error!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        const stream = self.locked.?;
        self.record(.release, stream);
        self.locked = null;
        if (self.release_fails[@intFromEnum(stream)]) |failure| return failure;
    }
};

fn candidate() log_binding.BindingCandidate {
    return .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-1").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-1").?,
        .run_id = telemetry.Identifier.validate("RUN-1").?,
        .feature_id = feature_identity.FeatureId.parse("F0002").?,
    };
}

fn prepared() log_stream.Runtime {
    return .{ .event = .{ .open = stateAt(3) }, .prompt = .{ .open = stateAt(3) }, .prepared = true };
}

fn exercise(fake: *Fake, runtime: *log_stream.Runtime, scope: routine.Scope, diagnostic: *routine.Diagnostic) !routine.Outcome {
    const owner = try log_binding.createValidated(std.testing.allocator, candidate());
    defer log_binding.deinitOwner(owner);
    return routine.run(fake.ports(), .{ .allocator = std.testing.allocator, .binding = log_binding.binding(owner) }, runtime, scope, diagnostic);
}

fn expectKinds(fake: *const Fake, expected: []const Kind) !void {
    var out: [32]Kind = undefined;
    try std.testing.expectEqualSlices(Kind, expected, fake.kinds(&out));
}

test "finalization closes both streams with the trailer that follows each stream's last row, then retires the run" {
    var fake: Fake = .{};
    var runtime = prepared();
    var diagnostic: routine.Diagnostic = .{};
    const outcome = try exercise(&fake, &runtime, .finalize, &diagnostic);
    try std.testing.expect(outcome == .closed);
    try expectKinds(&fake, &.{ .clock, .acquire, .close, .release, .acquire, .close, .release });
    try std.testing.expect(runtime.retired and !runtime.prepared);
    try std.testing.expect(runtime.event == .unopened and runtime.prompt == .unopened);
    try std.testing.expectEqual(@as(?routine.Step, null), diagnostic.step);
    // Each trailer is the production serializer's, named for the stream's segment and last written sequence.
    const owner = try log_binding.createValidated(std.testing.allocator, candidate());
    defer log_binding.deinitOwner(owner);
    inline for (.{ log_stream.Stream.event, log_stream.Stream.prompt }) |stream| {
        const wanted = try log_rows.serializeControl(std.testing.allocator, stream, .segment_trailer, log_binding.binding(owner), 1, 2, "2026-08-30T10:15:30Z");
        defer std.testing.allocator.free(wanted);
        const index = @intFromEnum(stream);
        try std.testing.expectEqualStrings(wanted, fake.trailers[index][0..fake.trailer_lengths[index]]);
        try std.testing.expectEqual(@as(?log_stream.StreamState, stateAt(3)), fake.closed_state[index]);
    }
}

test "finalization closes the segment the cache names, a rotated one that holds only its header included" {
    var fake: Fake = .{};
    var rotated = stateAt(3);
    rotated.segment_ordinal = 2;
    rotated.segment_count = 2;
    rotated.total_segment_count = 2;
    rotated.segment_bytes = 120;
    var runtime: log_stream.Runtime = .{ .event = .{ .open = rotated }, .prepared = true };
    var diagnostic: routine.Diagnostic = .{};
    const outcome = try exercise(&fake, &runtime, .finalize, &diagnostic);
    try std.testing.expect(outcome == .closed);
    const index = @intFromEnum(log_stream.Stream.event);
    try std.testing.expectEqual(@as(?log_stream.StreamState, rotated), fake.closed_state[index]);
    // The trailer names the new segment, and the last sequence written before it.
    const owner = try log_binding.createValidated(std.testing.allocator, candidate());
    defer log_binding.deinitOwner(owner);
    const wanted = try log_rows.serializeControl(std.testing.allocator, .event, .segment_trailer, log_binding.binding(owner), 2, 2, "2026-08-30T10:15:30Z");
    defer std.testing.allocator.free(wanted);
    try std.testing.expectEqualStrings(wanted, fake.trailers[index][0..fake.trailer_lengths[index]]);
}

test "only a prepared, live run is finalized, and a rejected finalization touches nothing" {
    inline for (.{ log_stream.Runtime{}, log_stream.Runtime{ .retired = true } }) |initial| {
        var fake: Fake = .{};
        var runtime = initial;
        var diagnostic: routine.Diagnostic = .{};
        const outcome = try exercise(&fake, &runtime, .finalize, &diagnostic);
        try std.testing.expect(outcome == .invalid);
        try std.testing.expectEqual(@as(?routine.Step, .validate_status), diagnostic.step);
        try std.testing.expectEqual(@as(usize, 0), fake.count);
        try std.testing.expectEqual(initial, runtime);
    }
}

test "each close step takes its one port or domain rule and answers for itself" {
    const owner = try log_binding.createValidated(std.testing.allocator, candidate());
    defer log_binding.deinitOwner(owner);
    const binding = log_binding.binding(owner);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sink_failure: log_stream.Stop = .{ .blocked = .LOG_SINK_FAILURE };
    // Only a prepared, live run is finalized.
    try std.testing.expect(routine.steps.mayFinalize(.prepared));
    try std.testing.expect(!routine.steps.mayFinalize(.unprepared) and !routine.steps.mayFinalize(.retired));
    // The clock is read through its one port.
    var working: Fake = .{};
    try std.testing.expectEqual(reading.unix_ms, (try routine.steps.readClock(working.ports().clock)).unix_ms);
    var broken: Fake = .{ .clock_fails = true };
    try std.testing.expectError(error.LogClockReadFailure, routine.steps.readClock(broken.ports().clock));
    // A lock: taken, or stopped with the code of its kind.
    try std.testing.expect(routine.steps.acquire(working.ports().acquirer, binding, .event) == null);
    for ([_]struct { failure: sink_port.Error, stop: log_stream.Stop }{
        .{ .failure = error.LockUnavailable, .stop = .{ .blocked = .LOG_LOCK_TIMEOUT } },
        .{ .failure = error.SinkFailure, .stop = sink_failure },
        .{ .failure = error.Cancelled, .stop = .cancelled },
    }) |case| {
        var fake: Fake = .{ .acquire_fails = .{ case.failure, case.failure } };
        try std.testing.expectEqual(case.stop, routine.steps.acquire(fake.ports().acquirer, binding, .event).?);
    }
    // Recovering gives what the stream holds under the lock, or the stop of the sink's failure.
    try std.testing.expect(routine.steps.recover(working.ports().recoverer, a, binding, .event).recovered == .active);
    var unrecoverable: Fake = .{ .recover_fails = .{ error.CorruptStream, null } };
    try std.testing.expectEqual(sink_failure, routine.steps.recover(unrecoverable.ports().recoverer, a, binding, .event).stopped);
    // The trailer is the production serializer's for the state's segment and its last written sequence.
    const trailer = try routine.steps.serializeTrailer(a, .event, binding, stateAt(5), reading);
    const wanted = try log_rows.serializeControl(a, .event, .segment_trailer, binding, 1, 4, "2026-08-30T10:15:30Z");
    try std.testing.expectEqualStrings(wanted, trailer);
    // Closing writes the trailer, or stops with the code of its kind: only a close names a failed flush.
    try std.testing.expect(routine.steps.closeStream(working.ports().closer, binding, .event, stateAt(5), trailer) == null);
    var unflushable: Fake = .{ .close_fails = .{ error.FlushFailure, null } };
    try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_FLUSH_FAILURE }, routine.steps.closeStream(unflushable.ports().closer, binding, .event, stateAt(5), trailer).?);
    var cancelled: Fake = .{ .close_fails = .{ error.Cancelled, null } };
    try std.testing.expectEqual(log_stream.Stop.cancelled, routine.steps.closeStream(cancelled.ports().closer, binding, .event, stateAt(5), trailer).?);
    // A release that worked, and one that failed.
    try std.testing.expect(routine.steps.release(working.ports().releaser));
    var stuck: Fake = .{ .release_fails = .{ error.ReleaseFailure, null } };
    _ = routine.steps.acquire(stuck.ports().acquirer, binding, .event);
    try std.testing.expect(!routine.steps.release(stuck.ports().releaser));
}

test "a clock that cannot be read is a serialization failure that closes nothing" {
    var fake: Fake = .{ .clock_fails = true };
    var runtime = prepared();
    var diagnostic: routine.Diagnostic = .{};
    const outcome = try exercise(&fake, &runtime, .finalize, &diagnostic);
    try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_SERIALIZATION_FAILURE }, outcome.stopped);
    try std.testing.expectEqual(@as(?routine.Step, .read_clock), diagnostic.step);
    try expectKinds(&fake, &.{.clock});
    try std.testing.expect(runtime.prepared and !runtime.retired);
}

test "every stream is closed even when the first stopped, the first stop is the one reported, and the run is not retired" {
    const Case = struct { failure: sink_port.Error, stop: log_stream.Stop };
    for ([_]Case{
        .{ .failure = error.FlushFailure, .stop = .{ .blocked = .LOG_FLUSH_FAILURE } },
        .{ .failure = error.SinkFailure, .stop = .{ .blocked = .LOG_SINK_FAILURE } },
        .{ .failure = error.Cancelled, .stop = .cancelled },
    }) |case| {
        var fake: Fake = .{ .close_fails = .{ case.failure, error.SinkFailure } };
        var runtime = prepared();
        var diagnostic: routine.Diagnostic = .{};
        const outcome = try exercise(&fake, &runtime, .finalize, &diagnostic);
        try std.testing.expectEqual(case.stop, outcome.stopped);
        try std.testing.expectEqual(@as(?routine.Step, .close_stream), diagnostic.step);
        // The prompt stream is closed after the event stream stopped, and its own stop is not the one reported.
        try expectKinds(&fake, &.{ .clock, .acquire, .close, .release, .acquire, .close, .release });
        try std.testing.expect(runtime.prepared and !runtime.retired);
        // A cancelled close may have written its trailer, so the state is dropped; any other failure keeps it.
        try std.testing.expect(if (case.stop == .cancelled) runtime.event == .dropped else runtime.event == .open);
    }
}

test "a lock held elsewhere is a timeout, closes nothing in that stream and does not stop the other" {
    var fake: Fake = .{ .acquire_fails = .{ error.LockUnavailable, null } };
    var runtime = prepared();
    var diagnostic: routine.Diagnostic = .{};
    const outcome = try exercise(&fake, &runtime, .finalize, &diagnostic);
    try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_LOCK_TIMEOUT }, outcome.stopped);
    try std.testing.expectEqual(@as(?routine.Step, .acquire_close), diagnostic.step);
    try expectKinds(&fake, &.{ .clock, .acquire, .acquire, .close, .release });
    try std.testing.expect(runtime.event == .open and runtime.prompt == .unopened);
}

test "a lock that cannot be released is a logging failure of its own that outranks the stop before it" {
    const Case = struct { close: ?sink_port.Error, cancels: bool, stop: log_stream.Stop, step: routine.Step };
    for ([_]Case{
        .{ .close = null, .cancels = false, .stop = .{ .blocked = .LOG_RELEASE_FAILURE }, .step = .release_close },
        .{ .close = error.SinkFailure, .cancels = false, .stop = .{ .blocked = .LOG_RELEASE_FAILURE }, .step = .close_stream },
        .{ .close = error.Cancelled, .cancels = true, .stop = .{ .blocked = .LOG_RELEASE_FAILURE }, .step = .close_stream },
    }) |case| {
        var fake: Fake = .{ .close_fails = .{ case.close, null }, .release_fails = .{ error.ReleaseFailure, null } };
        var runtime = prepared();
        var diagnostic: routine.Diagnostic = .{};
        const outcome = try exercise(&fake, &runtime, .finalize, &diagnostic);
        try std.testing.expectEqual(case.stop, outcome.stopped);
        try std.testing.expectEqual(@as(?routine.Step, case.step), diagnostic.step);
        // The cancelled close dropped the state before the failed release, and the release failure did not undo it.
        try std.testing.expect(if (case.cancels) runtime.event == .dropped else true);
    }
}

test "a stream a cancelled step dropped is recovered under its lock, then closed after the rows that really are on disk" {
    var fake: Fake = .{ .recovery = .{ .{ .active = stateAt(5) }, .{ .active = stateAt(5) } } };
    var runtime = prepared();
    runtime.event = .dropped;
    var diagnostic: routine.Diagnostic = .{};
    const outcome = try exercise(&fake, &runtime, .finalize, &diagnostic);
    try std.testing.expect(outcome == .closed);
    try expectKinds(&fake, &.{ .clock, .acquire, .recover, .release, .acquire, .close, .release, .acquire, .close, .release });
    // The trailer follows the recovered state's last row, not the cached one's.
    try std.testing.expectEqual(@as(?log_stream.StreamState, stateAt(5)), fake.closed_state[@intFromEnum(log_stream.Stream.event)]);
    try std.testing.expectEqual(@as(?log_stream.StreamState, stateAt(3)), fake.closed_state[@intFromEnum(log_stream.Stream.prompt)]);
    // The unrelated member of the class: the other stream dropped is recovered the same way.
    var other: Fake = .{};
    var other_runtime = prepared();
    other_runtime.prompt = .dropped;
    const other_outcome = try exercise(&other, &other_runtime, .finalize, &diagnostic);
    try std.testing.expect(other_outcome == .closed);
    try std.testing.expectEqual(@as(?log_stream.StreamState, stateAt(5)), other.closed_state[@intFromEnum(log_stream.Stream.prompt)]);
}

test "a dropped stream whose recovery finds no segment has nothing to close, and one whose recovery fails keeps its mark and releases the lock" {
    var empty: Fake = .{ .recovery = .{ .{ .empty = .{ .next_segment_ordinal = 1, .next_sequence = 1, .total_segment_count = 0 } }, .{ .active = stateAt(5) } } };
    var runtime = prepared();
    runtime.event = .dropped;
    var diagnostic: routine.Diagnostic = .{};
    const outcome = try exercise(&empty, &runtime, .finalize, &diagnostic);
    try std.testing.expect(outcome == .closed);
    try expectKinds(&empty, &.{ .clock, .acquire, .recover, .release, .acquire, .close, .release });
    try std.testing.expect(runtime.event == .unopened);

    var failing: Fake = .{ .recover_fails = .{ error.SinkFailure, null } };
    var stuck = prepared();
    stuck.event = .dropped;
    const stopped = try exercise(&failing, &stuck, .finalize, &diagnostic);
    try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_SINK_FAILURE }, stopped.stopped);
    try std.testing.expectEqual(@as(?routine.Step, .recover_dropped), diagnostic.step);
    try expectKinds(&failing, &.{ .clock, .acquire, .recover, .release, .acquire, .close, .release });
    try std.testing.expect(stuck.event == .dropped);
    try std.testing.expect(stuck.prepared and !stuck.retired);
}

test "an abandoned activation closes the one stream it opened with its own reading and leaves the run as it was" {
    var fake: Fake = .{};
    var runtime: log_stream.Runtime = .{ .event = .{ .open = stateAt(3) } };
    var diagnostic: routine.Diagnostic = .{};
    const outcome = try exercise(&fake, &runtime, .{ .abandon = .{ .stream = .event, .reading = reading } }, &diagnostic);
    try std.testing.expect(outcome == .closed);
    // No status check and no clock read: the activation never finished.
    try expectKinds(&fake, &.{ .acquire, .close, .release });
    try std.testing.expect(runtime.event == .unopened and !runtime.prepared and !runtime.retired);
}
