const std = @import("std");
const routine = @import("application/feature_log_prior_finalization_routine.zig");
const feature_identity = @import("domain/feature_identity.zig");
const log_binding = @import("domain/feature_log_binding.zig");
const log_format = @import("domain/feature_log_format.zig");
const log_stream = @import("domain/feature_log_stream.zig");
const telemetry = @import("domain/telemetry.zig");
const clock_port = @import("ports/trusted_log_clock.zig");
const sink_port = @import("ports/feature_log_sink.zig");

const utc = "2026-08-30T10:15:30Z";

const Call = enum { clock, acquire, check_open, recover, close, verify_closed, release };

const open_tail: log_stream.StreamState = .{
    .segment_ordinal = 2,
    .next_sequence = 5,
    .segment_bytes = 640,
    .segment_count = 2,
    .total_segment_count = 2,
    .records_since_flush = 0,
    .last_flush_monotonic_ms = 0,
};

/// Fake ports that record the order of their calls and fail where told. A tail is open until a close writes its
/// trailer, so a second finalization finds it closed, as the disk would.
const Fake = struct {
    calls: [12]Call = undefined,
    count: usize = 0,
    clock_fails: bool = false,
    acquire_fails: ?sink_port.Error = null,
    inspect_fails: ?sink_port.Error = null,
    recovery: ?log_stream.Recovery = .{ .active = open_tail },
    recover_fails: ?sink_port.Error = null,
    close_fails: ?sink_port.Error = null,
    /// A close that reports success but leaves the group open, as a trailer that did not land would.
    close_lands: bool = true,
    release_fails: ?sink_port.Error = null,
    state: log_stream.TailState = .active,
    inspections: usize = 0,
    trailer: [512]u8 = undefined,
    trailer_len: usize = 0,
    closed_stream: ?log_stream.Stream = null,
    closed_state: ?log_stream.StreamState = null,

    fn ports(self: *Fake) routine.Ports {
        return .{
            .clock = .{ .context = self, .now_fn = now },
            .acquirer = .{ .context = self, .acquire_fn = acquire },
            .inspector = .{ .context = self, .inspect_fn = inspect },
            .recoverer = .{ .context = self, .recover_fn = recover },
            .closer = .{ .context = self, .close_fn = close },
            .releaser = .{ .context = self, .release_fn = release },
        };
    }

    fn record(self: *Fake, call: Call) void {
        self.calls[self.count] = call;
        self.count += 1;
    }

    fn order(self: *const Fake) []const Call {
        return self.calls[0..self.count];
    }

    fn now(context: *anyopaque) clock_port.Error!log_stream.ClockReading {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.clock);
        if (self.clock_fails) return error.ClockFailure;
        return .{ .occurred_at_utc = utc.*, .unix_ms = 1_788_087_330_000, .monotonic_ms = 1 };
    }
    fn acquire(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, _: u16) sink_port.Error!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.acquire);
        if (self.acquire_fails) |failure| return failure;
    }
    fn inspect(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream) sink_port.Error!log_stream.TailState {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(if (self.inspections == 0) .check_open else .verify_closed);
        self.inspections += 1;
        if (self.inspect_fails) |failure| return failure;
        return self.state;
    }
    fn recover(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, _: []const u8, _: std.mem.Allocator) sink_port.Error!log_stream.Recovery {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.recover);
        if (self.recover_fails) |failure| return failure;
        return self.recovery.?;
    }
    fn close(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, state: log_stream.StreamState, trailer: []const u8) sink_port.Error!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.close);
        if (self.close_fails) |failure| return failure;
        self.closed_stream = stream;
        self.closed_state = state;
        @memcpy(self.trailer[0..trailer.len], trailer);
        self.trailer_len = trailer.len;
        if (self.close_lands) self.state = .closed;
    }
    fn release(context: *anyopaque) sink_port.Error!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.release);
        if (self.release_fails) |failure| return failure;
    }
};

fn candidate(run: []const u8) log_binding.BindingCandidate {
    return .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-1").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-1").?,
        .run_id = telemetry.Identifier.validate(run).?,
        .feature_id = feature_identity.FeatureId.parse("F0002").?,
    };
}

/// One finalization of the prior run's `stream` tail.
fn exercise(fake: *Fake, stream: log_stream.Stream, diagnostic: *routine.Diagnostic) !routine.Outcome {
    const owner = try log_binding.createValidated(std.testing.allocator, candidate("RUN-CRASHED"));
    defer log_binding.deinitOwner(owner);
    return routine.run(fake.ports(), .{ .allocator = std.testing.allocator, .historical = log_binding.binding(owner), .stream = stream }, diagnostic);
}

test "a crashed tail is proven open, recovered, closed with one trailer stamped now, proven closed and released, in either stream" {
    inline for (.{ log_stream.Stream.event, log_stream.Stream.prompt }) |stream| {
        var fake: Fake = .{};
        var diagnostic: routine.Diagnostic = .{};
        const outcome = try exercise(&fake, stream, &diagnostic);
        try std.testing.expect(outcome == .closed);
        try std.testing.expectEqualSlices(Call, &.{ .clock, .acquire, .check_open, .recover, .close, .verify_closed, .release }, fake.order());
        try std.testing.expectEqual(@as(?routine.Step, null), diagnostic.step);
        try std.testing.expectEqual(@as(?log_stream.Stream, stream), fake.closed_stream);
        // The trailer follows the recovered tail's last row, in the tail's own segment, and carries the clock's reading.
        try std.testing.expectEqual(@as(?log_stream.StreamState, open_tail), fake.closed_state);
        const trailer = std.mem.trimEnd(u8, fake.trailer[0..fake.trailer_len], "\n");
        try std.testing.expectEqualStrings("segment_trailer", log_format.cellAt(trailer, log_format.sharedColumn("record_kind")).?);
        try std.testing.expectEqualStrings("4", log_format.cellAt(trailer, log_format.sharedColumn("sequence")).?);
        try std.testing.expect(std.mem.indexOf(u8, trailer, utc) != null);
        try std.testing.expect(std.mem.indexOf(u8, trailer, "RUN-CRASHED") != null);
    }
}

test "each finalization step takes its one port or domain rule and answers for itself" {
    const owner = try log_binding.createValidated(std.testing.allocator, candidate("RUN-CRASHED"));
    defer log_binding.deinitOwner(owner);
    const binding = log_binding.binding(owner);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sink_failure: log_stream.Stop = .{ .blocked = .LOG_SINK_FAILURE };
    // The clock is read through its one port.
    var working: Fake = .{};
    try std.testing.expectEqual(@as(u64, 1_788_087_330_000), (try routine.steps.readClock(working.ports().clock)).unix_ms);
    var broken: Fake = .{ .clock_fails = true };
    try std.testing.expectError(error.LogClockReadFailure, routine.steps.readClock(broken.ports().clock));
    // A lock: taken, or stopped with the code of its kind.
    try std.testing.expect(routine.steps.acquire(working.ports().acquirer, binding, .event) == null);
    for ([_]struct { failure: sink_port.Error, stop: log_stream.Stop }{
        .{ .failure = error.LockUnavailable, .stop = .{ .blocked = .LOG_LOCK_TIMEOUT } },
        .{ .failure = error.SinkFailure, .stop = sink_failure },
        .{ .failure = error.Cancelled, .stop = .cancelled },
    }) |case| {
        var fake: Fake = .{ .acquire_fails = case.failure };
        try std.testing.expectEqual(case.stop, routine.steps.acquire(fake.ports().acquirer, binding, .event).?);
    }
    // Under the lock the group must still be an open tail: a group another process closed, or that holds no segment, is
    // not this routine's to touch, and a group that cannot be read is its own stop.
    var open: Fake = .{};
    try std.testing.expect(routine.steps.checkOpen(open.ports().inspector, binding, .event) == null);
    for ([_]log_stream.TailState{ .closed, .empty }) |state| {
        var fake: Fake = .{ .state = state };
        try std.testing.expectEqual(sink_failure, routine.steps.checkOpen(fake.ports().inspector, binding, .event).?);
    }
    var unreadable: Fake = .{ .inspect_fails = error.CorruptStream };
    try std.testing.expectEqual(sink_failure, routine.steps.checkOpen(unreadable.ports().inspector, binding, .event).?);
    var cancelled_read: Fake = .{ .inspect_fails = error.Cancelled };
    try std.testing.expectEqual(log_stream.Stop.cancelled, routine.steps.checkOpen(cancelled_read.ports().inspector, binding, .event).?);
    // After the close the group must read closed: a trailer that did not land is a stop, not a success.
    var closed: Fake = .{ .state = .closed };
    try std.testing.expect(routine.steps.verifyClosed(closed.ports().inspector, binding, .event) == null);
    var still_open: Fake = .{};
    try std.testing.expectEqual(sink_failure, routine.steps.verifyClosed(still_open.ports().inspector, binding, .event).?);
    // Recovering the tail gives its active state; a group with no tail to recover, or a recovery that fails, stops.
    try std.testing.expectEqual(open_tail, routine.steps.recoverTail(working.ports().recoverer, a, binding, .event).recovered);
    var empty_recovery: Fake = .{ .recovery = .{ .empty = .{ .next_segment_ordinal = 3, .next_sequence = 5, .total_segment_count = 2 } } };
    try std.testing.expectEqual(sink_failure, routine.steps.recoverTail(empty_recovery.ports().recoverer, a, binding, .event).stopped);
    var unrecoverable: Fake = .{ .recover_fails = error.CorruptStream };
    try std.testing.expectEqual(sink_failure, routine.steps.recoverTail(unrecoverable.ports().recoverer, a, binding, .event).stopped);
    // The trailer follows the tail's last row, in the tail's own segment, stamped with the reading.
    const reading = try routine.steps.readClock(working.ports().clock);
    const trailer = try routine.steps.serializeTrailer(a, .event, binding, open_tail, reading);
    const wanted = try @import("domain/feature_log_rows.zig").serializeControl(a, .event, .segment_trailer, binding, 2, 4, utc);
    try std.testing.expectEqualStrings(wanted, trailer);
    // Closing writes the trailer, or stops with the code of its kind: only a close names a failed flush.
    try std.testing.expect(routine.steps.closeStream(working.ports().closer, binding, .event, open_tail, trailer) == null);
    var unflushable: Fake = .{ .close_fails = error.FlushFailure };
    try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_FLUSH_FAILURE }, routine.steps.closeStream(unflushable.ports().closer, binding, .event, open_tail, trailer).?);
    // A release that worked, and one that failed.
    try std.testing.expect(routine.steps.release(working.ports().releaser));
    var stuck: Fake = .{ .release_fails = error.ReleaseFailure };
    try std.testing.expect(!routine.steps.release(stuck.ports().releaser));
}

test "a second finalization finds the group closed under the lock and writes nothing" {
    var fake: Fake = .{};
    var diagnostic: routine.Diagnostic = .{};
    try std.testing.expect((try exercise(&fake, .event, &diagnostic)) == .closed);
    // The same fake is now what the disk is after the close; a second run is the unrelated member of the class: a tail
    // another process closed since discovery.
    fake.count = 0;
    fake.inspections = 0;
    fake.closed_stream = null;
    var second: routine.Diagnostic = .{};
    const outcome = try exercise(&fake, .event, &second);
    try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_SINK_FAILURE }, outcome.stopped);
    try std.testing.expectEqual(@as(?routine.Step, .check_open), second.step);
    try std.testing.expectEqualSlices(Call, &.{ .clock, .acquire, .check_open, .release }, fake.order());
    try std.testing.expectEqual(@as(?log_stream.Stream, null), fake.closed_stream);
}

test "a clock that cannot be read and a lock that cannot be taken stop before anything is written, and release nothing" {
    {
        var fake: Fake = .{ .clock_fails = true };
        var diagnostic: routine.Diagnostic = .{};
        const outcome = try exercise(&fake, .event, &diagnostic);
        try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_SERIALIZATION_FAILURE }, outcome.stopped);
        try std.testing.expectEqual(@as(?routine.Step, .read_clock), diagnostic.step);
        try std.testing.expectEqualSlices(Call, &.{.clock}, fake.order());
    }
    const Case = struct { failure: sink_port.Error, stop: log_stream.Stop };
    for ([_]Case{
        // A lock held elsewhere is a timeout, and blocks.
        .{ .failure = error.LockUnavailable, .stop = .{ .blocked = .LOG_LOCK_TIMEOUT } },
        .{ .failure = error.SinkFailure, .stop = .{ .blocked = .LOG_SINK_FAILURE } },
        .{ .failure = error.InvalidBinding, .stop = .{ .blocked = .LOG_SINK_FAILURE } },
        .{ .failure = error.Cancelled, .stop = .cancelled },
    }) |case| {
        var fake: Fake = .{ .acquire_fails = case.failure };
        var diagnostic: routine.Diagnostic = .{};
        const outcome = try exercise(&fake, .event, &diagnostic);
        try std.testing.expectEqual(case.stop, outcome.stopped);
        try std.testing.expectEqual(@as(?routine.Step, .acquire), diagnostic.step);
        try std.testing.expectEqualSlices(Call, &.{ .clock, .acquire }, fake.order());
    }
}

test "a group that is not an active tail under the lock, or cannot be read, is left alone and the lock is released" {
    const Case = struct { state: log_stream.TailState, failure: ?sink_port.Error, stop: log_stream.Stop };
    for ([_]Case{
        // Closed or emptied since discovery: another process changed it, and finalization never writes it.
        .{ .state = .closed, .failure = null, .stop = .{ .blocked = .LOG_SINK_FAILURE } },
        .{ .state = .empty, .failure = null, .stop = .{ .blocked = .LOG_SINK_FAILURE } },
        .{ .state = .active, .failure = error.CorruptStream, .stop = .{ .blocked = .LOG_SINK_FAILURE } },
        .{ .state = .active, .failure = error.Cancelled, .stop = .cancelled },
    }) |case| {
        var fake: Fake = .{ .state = case.state, .inspect_fails = case.failure };
        var diagnostic: routine.Diagnostic = .{};
        const outcome = try exercise(&fake, .event, &diagnostic);
        try std.testing.expectEqual(case.stop, outcome.stopped);
        try std.testing.expectEqual(@as(?routine.Step, .check_open), diagnostic.step);
        try std.testing.expectEqualSlices(Call, &.{ .clock, .acquire, .check_open, .release }, fake.order());
    }
}

test "a tail that cannot be recovered stops before a trailer is written, and the lock is released" {
    const Case = struct { recovery: ?log_stream.Recovery, failure: ?sink_port.Error, stop: log_stream.Stop };
    for ([_]Case{
        .{ .recovery = null, .failure = error.CorruptStream, .stop = .{ .blocked = .LOG_SINK_FAILURE } },
        .{ .recovery = null, .failure = error.SinkFailure, .stop = .{ .blocked = .LOG_SINK_FAILURE } },
        .{ .recovery = null, .failure = error.Cancelled, .stop = .cancelled },
        // Recovery that finds no open tail has nothing to close.
        .{ .recovery = .{ .empty = .{ .next_segment_ordinal = 3, .next_sequence = 5, .total_segment_count = 2 } }, .failure = null, .stop = .{ .blocked = .LOG_SINK_FAILURE } },
    }) |case| {
        var fake: Fake = .{ .recovery = case.recovery, .recover_fails = case.failure };
        var diagnostic: routine.Diagnostic = .{};
        const outcome = try exercise(&fake, .event, &diagnostic);
        try std.testing.expectEqual(case.stop, outcome.stopped);
        try std.testing.expectEqual(@as(?routine.Step, .recover_tail), diagnostic.step);
        try std.testing.expectEqualSlices(Call, &.{ .clock, .acquire, .check_open, .recover, .release }, fake.order());
    }
}

test "a close that fails or does not land is a stop of its own, and a cancelled close still releases the lock" {
    const Case = struct { close: ?sink_port.Error, lands: bool, stop: log_stream.Stop, step: routine.Step, verified: bool };
    for ([_]Case{
        .{ .close = error.FlushFailure, .lands = true, .stop = .{ .blocked = .LOG_FLUSH_FAILURE }, .step = .close_stream, .verified = false },
        .{ .close = error.SinkFailure, .lands = true, .stop = .{ .blocked = .LOG_SINK_FAILURE }, .step = .close_stream, .verified = false },
        .{ .close = error.Cancelled, .lands = true, .stop = .cancelled, .step = .close_stream, .verified = false },
        // A close that reports success while the group stays open is no success.
        .{ .close = null, .lands = false, .stop = .{ .blocked = .LOG_SINK_FAILURE }, .step = .verify_closed, .verified = true },
    }) |case| {
        var fake: Fake = .{ .close_fails = case.close, .close_lands = case.lands };
        var diagnostic: routine.Diagnostic = .{};
        const outcome = try exercise(&fake, .event, &diagnostic);
        try std.testing.expectEqual(case.stop, outcome.stopped);
        try std.testing.expectEqual(@as(?routine.Step, case.step), diagnostic.step);
        const expected: []const Call = if (case.verified) &.{ .clock, .acquire, .check_open, .recover, .close, .verify_closed, .release } else &.{ .clock, .acquire, .check_open, .recover, .close, .release };
        try std.testing.expectEqualSlices(Call, expected, fake.order());
    }
}

test "a lock that cannot be released is a logging failure of its own and outranks the stop before it" {
    const Case = struct { close: ?sink_port.Error, release: sink_port.Error, stop: log_stream.Stop, step: routine.Step };
    for ([_]Case{
        // After a good close.
        .{ .close = null, .release = error.ReleaseFailure, .stop = .{ .blocked = .LOG_RELEASE_FAILURE }, .step = .release },
        // A release that reports a cancellation has failed to release.
        .{ .close = null, .release = error.Cancelled, .stop = .{ .blocked = .LOG_RELEASE_FAILURE }, .step = .release },
        // After a failed or cancelled close: the release failure is reported, as for the run's own close.
        .{ .close = error.SinkFailure, .release = error.ReleaseFailure, .stop = .{ .blocked = .LOG_RELEASE_FAILURE }, .step = .close_stream },
        .{ .close = error.Cancelled, .release = error.ReleaseFailure, .stop = .{ .blocked = .LOG_RELEASE_FAILURE }, .step = .close_stream },
    }) |case| {
        var fake: Fake = .{ .close_fails = case.close, .release_fails = case.release };
        var diagnostic: routine.Diagnostic = .{};
        const outcome = try exercise(&fake, .event, &diagnostic);
        try std.testing.expectEqual(case.stop, outcome.stopped);
        try std.testing.expectEqual(@as(?routine.Step, case.step), diagnostic.step);
        try std.testing.expectEqual(Call.release, fake.order()[fake.count - 1]);
    }
}
