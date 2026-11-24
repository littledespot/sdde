const std = @import("std");
const routine = @import("application/feature_log_prepare_routine.zig");
const feature_identity = @import("domain/feature_identity.zig");
const log_binding = @import("domain/feature_log_binding.zig");
const log_policy = @import("domain/log_policy.zig");
const log_rows = @import("domain/feature_log_rows.zig");
const log_stream = @import("domain/feature_log_stream.zig");
const telemetry = @import("domain/telemetry.zig");
const clock_port = @import("ports/trusted_log_clock.zig");
const sink_port = @import("ports/feature_log_sink.zig");

const Kind = enum { clock, acquire, recover, create, release };

const reading: log_stream.ClockReading = .{ .occurred_at_utc = "2026-08-30T10:15:30Z".*, .unix_ms = 1_788_087_330_000, .monotonic_ms = 1 };

const seed: log_stream.StreamSeed = .{ .next_segment_ordinal = 1, .next_sequence = 1, .total_segment_count = 0 };

fn stateAt(next_sequence: u64) log_stream.StreamState {
    return .{ .segment_ordinal = 1, .next_sequence = next_sequence, .segment_bytes = 500, .segment_count = 1, .total_segment_count = 1, .records_since_flush = 0, .last_flush_monotonic_ms = 0 };
}

/// Fake ports that record the order of their calls and fail where told, per stream.
const Fake = struct {
    kinds: [32]Kind = undefined,
    streams: [32]?log_stream.Stream = undefined,
    count: usize = 0,
    locked: ?log_stream.Stream = null,
    clock_fails: bool = false,
    acquire_fails: [2]?sink_port.Error = .{ null, null },
    recovery: [2]log_stream.Recovery = .{ .{ .empty = seed }, .{ .empty = seed } },
    recover_fails: [2]?sink_port.Error = .{ null, null },
    create_fails: [2]?sink_port.Error = .{ null, null },
    release_fails: [2]?sink_port.Error = .{ null, null },
    header: [2][512]u8 = undefined,
    header_lengths: [2]usize = .{ 0, 0 },

    fn ports(self: *Fake) routine.Ports {
        return .{
            .clock = .{ .context = self, .now_fn = now },
            .acquirer = .{ .context = self, .acquire_fn = acquire },
            .recoverer = .{ .context = self, .recover_fn = recover },
            .creator = .{ .context = self, .create_fn = create },
            .releaser = .{ .context = self, .release_fn = release },
        };
    }

    fn record(self: *Fake, kind: Kind, stream: ?log_stream.Stream) void {
        self.kinds[self.count] = kind;
        self.streams[self.count] = stream;
        self.count += 1;
    }

    fn order(self: *const Fake) []const Kind {
        return self.kinds[0..self.count];
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
    fn create(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, ordinal: u16, from: log_stream.StreamSeed, _: []const u8, header: []const u8) sink_port.Error!log_stream.StreamState {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.create, stream);
        const index = @intFromEnum(stream);
        @memcpy(self.header[index][0..header.len], header);
        self.header_lengths[index] = header.len;
        if (self.create_fails[index]) |failure| return failure;
        return .{ .segment_ordinal = ordinal, .next_sequence = from.next_sequence, .segment_bytes = 100, .segment_count = 1, .total_segment_count = 1, .records_since_flush = 0, .last_flush_monotonic_ms = 0 };
    }
    fn release(context: *anyopaque) sink_port.Error!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        const stream = self.locked.?;
        self.record(.release, stream);
        self.locked = null;
        if (self.release_fails[@intFromEnum(stream)]) |failure| return failure;
    }
};

const debug_policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
const info_policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .info, .alias_evidence = .none }, .console = false };

fn candidate() log_binding.BindingCandidate {
    return .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-1").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-1").?,
        .run_id = telemetry.Identifier.validate("RUN-1").?,
        .feature_id = feature_identity.FeatureId.parse("F0002").?,
    };
}

fn exercise(fake: *Fake, active: *const log_policy.CompiledLoggingPolicy, runtime: *log_stream.Runtime, diagnostic: *routine.Diagnostic) !routine.Outcome {
    const owner = try log_binding.createValidated(std.testing.allocator, candidate());
    defer log_binding.deinitOwner(owner);
    return routine.run(fake.ports(), .{ .allocator = std.testing.allocator, .policy = active, .binding = log_binding.binding(owner) }, runtime, diagnostic);
}

test "preparation creates each enabled stream's first segment under its own lock and marks the run prepared" {
    var fake: Fake = .{};
    var runtime: log_stream.Runtime = .{};
    var diagnostic: routine.Diagnostic = .{};
    try std.testing.expect((try exercise(&fake, &debug_policy, &runtime, &diagnostic)) == .prepared);
    try std.testing.expectEqualSlices(Kind, &.{ .clock, .acquire, .recover, .create, .release, .acquire, .recover, .create, .release }, fake.order());
    try std.testing.expect(runtime.prepared and !runtime.retired);
    try std.testing.expect(runtime.event == .open and runtime.prompt == .open);
    try std.testing.expectEqual(@as(?routine.Step, null), diagnostic.step);
    // Each header is the production serializer's, for the first segment of its stream.
    const owner = try log_binding.createValidated(std.testing.allocator, candidate());
    defer log_binding.deinitOwner(owner);
    inline for (.{ log_stream.Stream.event, log_stream.Stream.prompt }) |stream| {
        const wanted = try log_rows.serializeControl(std.testing.allocator, stream, .segment_header, log_binding.binding(owner), 1, null, "2026-08-30T10:15:30Z");
        defer std.testing.allocator.free(wanted);
        const index = @intFromEnum(stream);
        try std.testing.expectEqualStrings(wanted, fake.header[index][0..fake.header_lengths[index]]);
    }
}

test "a stream that already has segments is recovered, not created, and a stream that is already open is left alone" {
    var fake: Fake = .{ .recovery = .{ .{ .active = stateAt(7) }, .{ .empty = seed } } };
    var runtime: log_stream.Runtime = .{ .prompt = .{ .open = stateAt(3) } };
    var diagnostic: routine.Diagnostic = .{};
    try std.testing.expect((try exercise(&fake, &debug_policy, &runtime, &diagnostic)) == .prepared);
    try std.testing.expectEqualSlices(Kind, &.{ .clock, .acquire, .recover, .release }, fake.order());
    try std.testing.expectEqual(log_stream.Slot{ .open = stateAt(7) }, runtime.event);
    try std.testing.expectEqual(log_stream.Slot{ .open = stateAt(3) }, runtime.prompt);
}

test "a stream a cancelled step dropped is opened again from its bytes" {
    var fake: Fake = .{ .recovery = .{ .{ .active = stateAt(9) }, .{ .empty = seed } } };
    var runtime: log_stream.Runtime = .{ .event = .dropped, .prompt = .{ .open = stateAt(3) } };
    var diagnostic: routine.Diagnostic = .{};
    try std.testing.expect((try exercise(&fake, &debug_policy, &runtime, &diagnostic)) == .prepared);
    try std.testing.expectEqual(log_stream.Slot{ .open = stateAt(9) }, runtime.event);
}

test "a policy that captures no prompts opens only the event stream" {
    try std.testing.expect(!log_policy.promptCaptureEnabled(info_policy));
    var fake: Fake = .{};
    var runtime: log_stream.Runtime = .{};
    var diagnostic: routine.Diagnostic = .{};
    try std.testing.expect((try exercise(&fake, &info_policy, &runtime, &diagnostic)) == .prepared);
    try std.testing.expectEqualSlices(Kind, &.{ .clock, .acquire, .recover, .create, .release }, fake.order());
    try std.testing.expect(runtime.event == .open and runtime.prompt == .unopened and runtime.prepared);
}

test "a prepared run is prepared again without a call, and a retired run is a sink failure" {
    var fake: Fake = .{};
    var diagnostic: routine.Diagnostic = .{};
    var prepared: log_stream.Runtime = .{ .prepared = true };
    try std.testing.expect((try exercise(&fake, &debug_policy, &prepared, &diagnostic)) == .prepared);
    try std.testing.expectEqual(@as(usize, 0), fake.count);
    var retired: log_stream.Runtime = .{ .retired = true };
    const outcome = try exercise(&fake, &debug_policy, &retired, &diagnostic);
    try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_SINK_FAILURE }, outcome.stopped.stop);
    try std.testing.expectEqual(@as(?routine.Step, .check_status), diagnostic.step);
    try std.testing.expectEqual(@as(usize, 0), fake.count);
}

test "each prepare step takes its one port or domain rule and answers for itself" {
    const owner = try log_binding.createValidated(std.testing.allocator, candidate());
    defer log_binding.deinitOwner(owner);
    const binding = log_binding.binding(owner);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sink_failure: log_stream.Stop = .{ .blocked = .LOG_SINK_FAILURE };
    // The clock is read through its one port; the policy decides whether the prompt stream is opened at all.
    var working: Fake = .{};
    try std.testing.expectEqual(reading.unix_ms, (try routine.steps.readClock(working.ports().clock)).unix_ms);
    var broken: Fake = .{ .clock_fails = true };
    try std.testing.expectError(error.LogClockReadFailure, routine.steps.readClock(broken.ports().clock));
    try std.testing.expect(routine.steps.capturesPrompts(&debug_policy));
    try std.testing.expect(!routine.steps.capturesPrompts(&info_policy));
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
    // Recovering gives what the stream holds, or the stop of the sink's failure.
    try std.testing.expect(routine.steps.recover(working.ports().recoverer, a, binding, .event).recovered == .empty);
    var unrecoverable: Fake = .{ .recover_fails = .{ error.CorruptStream, null } };
    try std.testing.expectEqual(sink_failure, routine.steps.recover(unrecoverable.ports().recoverer, a, binding, .event).stopped);
    // The first header is the production serializer's for the seed's ordinal, and creating gives the segment's state.
    const header = try routine.steps.serializeHeader(a, .event, binding, seed, reading);
    const wanted = try log_rows.serializeControl(a, .event, .segment_header, binding, 1, null, "2026-08-30T10:15:30Z");
    try std.testing.expectEqualStrings(wanted, header);
    try std.testing.expectEqual(@as(u16, 1), routine.steps.create(working.ports().creator, binding, .event, seed, header).created.segment_ordinal);
    var uncreatable: Fake = .{ .create_fails = .{ error.SinkFailure, null } };
    try std.testing.expectEqual(sink_failure, routine.steps.create(uncreatable.ports().creator, binding, .event, seed, header).stopped);
    // A release that worked, and one that failed.
    try std.testing.expect(routine.steps.release(working.ports().releaser));
    var stuck: Fake = .{ .release_fails = .{ error.ReleaseFailure, null } };
    _ = routine.steps.acquire(stuck.ports().acquirer, binding, .event);
    try std.testing.expect(!routine.steps.release(stuck.ports().releaser));
}

test "a clock that cannot be read is a serialization failure before any lock" {
    var fake: Fake = .{ .clock_fails = true };
    var runtime: log_stream.Runtime = .{};
    var diagnostic: routine.Diagnostic = .{};
    const outcome = try exercise(&fake, &debug_policy, &runtime, &diagnostic);
    try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_SERIALIZATION_FAILURE }, outcome.stopped.stop);
    try std.testing.expectEqual(@as(?routine.Step, .read_clock), diagnostic.step);
    try std.testing.expectEqualSlices(Kind, &.{.clock}, fake.order());
}

test "a stop in the prompt stream leaves the event stream open for its caller to close with the activation's reading, and a stop in the event stream leaves nothing" {
    // The event stream stops first: nothing was opened.
    {
        var fake: Fake = .{ .acquire_fails = .{ error.LockUnavailable, null } };
        var runtime: log_stream.Runtime = .{};
        var diagnostic: routine.Diagnostic = .{};
        const outcome = try exercise(&fake, &debug_policy, &runtime, &diagnostic);
        try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_LOCK_TIMEOUT }, outcome.stopped.stop);
        try std.testing.expectEqual(@as(?routine.Abandon, null), outcome.stopped.abandon);
        try std.testing.expectEqual(@as(?routine.Step, .acquire), diagnostic.step);
        try std.testing.expect(!runtime.prepared);
    }
    // The prompt stream stops after the event stream opened.
    {
        var fake: Fake = .{ .acquire_fails = .{ null, error.LockUnavailable } };
        var runtime: log_stream.Runtime = .{};
        var diagnostic: routine.Diagnostic = .{};
        const outcome = try exercise(&fake, &debug_policy, &runtime, &diagnostic);
        try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_LOCK_TIMEOUT }, outcome.stopped.stop);
        try std.testing.expectEqual(log_stream.Stream.event, outcome.stopped.abandon.?.stream);
        try std.testing.expectEqual(reading, outcome.stopped.abandon.?.reading);
        try std.testing.expect(runtime.event == .open and runtime.prompt == .unopened and !runtime.prepared);
    }
}

test "a recover or a create that fails stops with its own code and releases the lock, a cancellation is no failure, and the release failure outranks them" {
    const Case = struct { recover: ?sink_port.Error, create: ?sink_port.Error, release: ?sink_port.Error, stop: log_stream.Stop, step: routine.Step };
    for ([_]Case{
        .{ .recover = error.SinkFailure, .create = null, .release = null, .stop = .{ .blocked = .LOG_SINK_FAILURE }, .step = .recover },
        .{ .recover = error.Cancelled, .create = null, .release = null, .stop = .cancelled, .step = .recover },
        .{ .recover = null, .create = error.SinkFailure, .release = null, .stop = .{ .blocked = .LOG_SINK_FAILURE }, .step = .create },
        .{ .recover = null, .create = error.Cancelled, .release = null, .stop = .cancelled, .step = .create },
        .{ .recover = null, .create = error.SinkFailure, .release = error.ReleaseFailure, .stop = .{ .blocked = .LOG_RELEASE_FAILURE }, .step = .create },
        .{ .recover = null, .create = null, .release = error.ReleaseFailure, .stop = .{ .blocked = .LOG_RELEASE_FAILURE }, .step = .release },
    }) |case| {
        var fake: Fake = .{ .recover_fails = .{ case.recover, null }, .create_fails = .{ case.create, null }, .release_fails = .{ case.release, null } };
        var runtime: log_stream.Runtime = .{};
        var diagnostic: routine.Diagnostic = .{};
        const outcome = try exercise(&fake, &debug_policy, &runtime, &diagnostic);
        try std.testing.expectEqual(case.stop, outcome.stopped.stop);
        try std.testing.expectEqual(@as(?routine.Step, case.step), diagnostic.step);
        // The lock a stopped open took is released, and the run stays unprepared with the stream unopened.
        try std.testing.expectEqual(Kind.release, fake.order()[fake.count - 1]);
        try std.testing.expect(runtime.event == .unopened and !runtime.prepared);
    }
}
