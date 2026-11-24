const std = @import("std");
const routine = @import("application/feature_log_persist_routine.zig");
const feature_identity = @import("domain/feature_identity.zig");
const log_binding = @import("domain/feature_log_binding.zig");
const log_limits = @import("domain/feature_log_limits.zig");
const log_policy = @import("domain/log_policy.zig");
const log_rows = @import("domain/feature_log_rows.zig");
const log_stream = @import("domain/feature_log_stream.zig");
const prompt_log = @import("domain/sanitized_prompt_log.zig");
const telemetry = @import("domain/telemetry.zig");
const clock_port = @import("ports/trusted_log_clock.zig");
const console_port = @import("ports/console_log_sink.zig");
const sink_port = @import("ports/feature_log_sink.zig");

const Kind = enum { clock, acquire, recover, create, rotate, append, console, release };

const reading: log_stream.ClockReading = .{ .occurred_at_utc = "2026-08-30T10:15:30Z".*, .unix_ms = 1_788_087_330_000, .monotonic_ms = 1001 };
const seed: log_stream.StreamSeed = .{ .next_segment_ordinal = 1, .next_sequence = 1, .total_segment_count = 0 };

fn stateAt(next_sequence: u64) log_stream.StreamState {
    return .{ .segment_ordinal = 1, .next_sequence = next_sequence, .segment_bytes = 500, .segment_count = 1, .total_segment_count = 1, .records_since_flush = 0, .last_flush_monotonic_ms = 0 };
}

const full_segment: log_stream.StreamState = .{
    .segment_ordinal = 1,
    .next_sequence = 3,
    .segment_bytes = log_limits.max_segment_bytes - 1,
    .segment_count = 1,
    .total_segment_count = 1,
    .records_since_flush = 0,
    .last_flush_monotonic_ms = 0,
};

/// Fake ports that record the order of their calls and fail where told, per stream.
const Fake = struct {
    kinds: [32]Kind = undefined,
    count: usize = 0,
    locked: ?log_stream.Stream = null,
    clock_fails: bool = false,
    acquire_fails: [2]?sink_port.Error = .{ null, null },
    recovery: [2]log_stream.Recovery = .{ .{ .empty = seed }, .{ .empty = seed } },
    recover_fails: [2]?sink_port.Error = .{ null, null },
    create_fails: [2]?sink_port.Error = .{ null, null },
    rotate_fails: [2]?sink_port.Error = .{ null, null },
    append_fails: [2]?sink_port.Error = .{ null, null },
    console_fails: ?console_port.Error = null,
    release_fails: [2]?sink_port.Error = .{ null, null },
    header: [512]u8 = undefined,
    header_length: usize = 0,
    trailer: [512]u8 = undefined,
    trailer_length: usize = 0,
    row: [4096]u8 = undefined,
    row_length: usize = 0,
    appended_state: ?log_stream.StreamState = null,
    appended_flush: ?bool = null,
    console_bytes: [4096]u8 = undefined,
    console_length: usize = 0,

    fn ports(self: *Fake) routine.Ports {
        return .{
            .clock = .{ .context = self, .now_fn = now },
            .acquirer = .{ .context = self, .acquire_fn = acquire },
            .recoverer = .{ .context = self, .recover_fn = recover },
            .creator = .{ .context = self, .create_fn = create },
            .rotator = .{ .context = self, .rotate_fn = rotate },
            .appender = .{ .context = self, .append_fn = append },
            .console = .{ .context = self, .write_fn = write },
            .releaser = .{ .context = self, .release_fn = release },
        };
    }

    fn record(self: *Fake, kind: Kind) void {
        self.kinds[self.count] = kind;
        self.count += 1;
    }

    fn order(self: *const Fake) []const Kind {
        return self.kinds[0..self.count];
    }

    fn rowBytes(self: *const Fake) []const u8 {
        return self.row[0..self.row_length];
    }

    fn now(context: *anyopaque) clock_port.Error!log_stream.ClockReading {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.clock);
        if (self.clock_fails) return error.ClockFailure;
        return reading;
    }
    fn acquire(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, _: u16) sink_port.Error!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.acquire);
        if (self.acquire_fails[@intFromEnum(stream)]) |failure| return failure;
        self.locked = stream;
    }
    fn recover(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, _: []const u8, _: std.mem.Allocator) sink_port.Error!log_stream.Recovery {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.recover);
        if (self.recover_fails[@intFromEnum(stream)]) |failure| return failure;
        return self.recovery[@intFromEnum(stream)];
    }
    fn create(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, ordinal: u16, from: log_stream.StreamSeed, _: []const u8, header: []const u8) sink_port.Error!log_stream.StreamState {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.create);
        @memcpy(self.header[0..header.len], header);
        self.header_length = header.len;
        if (self.create_fails[@intFromEnum(stream)]) |failure| return failure;
        return .{ .segment_ordinal = ordinal, .next_sequence = from.next_sequence, .segment_bytes = header.len, .segment_count = 1, .total_segment_count = 1, .records_since_flush = 0, .last_flush_monotonic_ms = 0 };
    }
    fn rotate(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, state: log_stream.StreamState, trailer: []const u8, _: []const u8, header: []const u8) sink_port.Error!log_stream.StreamState {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.rotate);
        @memcpy(self.trailer[0..trailer.len], trailer);
        self.trailer_length = trailer.len;
        @memcpy(self.header[0..header.len], header);
        self.header_length = header.len;
        if (self.rotate_fails[@intFromEnum(stream)]) |failure| return failure;
        var next = state;
        next.segment_ordinal += 1;
        next.segment_count += 1;
        next.total_segment_count += 1;
        next.segment_bytes = header.len;
        return next;
    }
    fn append(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, state: log_stream.StreamState, bytes: []const u8, flush: bool) sink_port.Error!log_stream.PersistedEvidence {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.append);
        @memcpy(self.row[0..bytes.len], bytes);
        self.row_length = bytes.len;
        self.appended_state = state;
        self.appended_flush = flush;
        if (self.append_fails[@intFromEnum(stream)]) |failure| return failure;
        return .{ .segment_ordinal = state.segment_ordinal, .sequence = state.next_sequence, .bytes_written = bytes.len, .flushed = flush };
    }
    fn write(context: *anyopaque, bytes: []const u8) console_port.Error!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.console);
        @memcpy(self.console_bytes[0..bytes.len], bytes);
        self.console_length = bytes.len;
        if (self.console_fails) |failure| return failure;
    }
    fn release(context: *anyopaque) sink_port.Error!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        const stream = self.locked.?;
        self.record(.release);
        self.locked = null;
        if (self.release_fails[@intFromEnum(stream)]) |failure| return failure;
    }
};

const debug_policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
const mirrored_policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = true };
const dropping_policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .fatal, .alias_evidence = .none }, .console = false };
const info_policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .info, .alias_evidence = .none }, .console = false };

fn candidate() log_binding.BindingCandidate {
    return .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-1").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-1").?,
        .run_id = telemetry.Identifier.validate("RUN-1").?,
        .feature_id = feature_identity.FeatureId.parse("F0002").?,
    };
}

fn eventInput() !routine.Input {
    return .{ .event = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"), .fact = .{ .run_completed = .{ .outcome = .completed } } } };
}

fn fragment() !prompt_log.SanitizedPromptFragment {
    return .{
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"),
        .attempt = 1,
        .request_id = telemetry.Identifier.validate("REQ-1").?,
        .route_id = telemetry.Identifier.validate("ROUTE-1").?,
        .model_profile_id = telemetry.Identifier.validate("PROFILE-1").?,
        .fragment_id = telemetry.Identifier.validate("FRAG-1").?,
        .direction = .response,
        .body_class = .code_body,
        .content = "sanitized",
        .retained_bytes = 9,
        .truncated = false,
        .redacted = true,
    };
}

fn promptInput() !routine.Input {
    return .{ .prompt = try fragment() };
}

fn inputFor(stream: log_stream.Stream) !routine.Input {
    return switch (stream) {
        .event => try eventInput(),
        .prompt => try promptInput(),
    };
}

fn exercise(fake: *Fake, active: *const log_policy.CompiledLoggingPolicy, runtime: *log_stream.Runtime, input: routine.Input, diagnostic: *routine.Diagnostic) !log_stream.Result {
    const owner = try log_binding.createValidated(std.testing.allocator, candidate());
    defer log_binding.deinitOwner(owner);
    return routine.run(fake.ports(), .{ .allocator = std.testing.allocator, .policy = active, .binding = log_binding.binding(owner) }, runtime, input, diagnostic);
}

fn expectKinds(fake: *const Fake, expected: []const Kind) !void {
    try std.testing.expectEqualSlices(Kind, expected, fake.order());
}

/// The bytes the production serializers give the row of `input` against `state`.
fn expectedRow(input: routine.Input, state: log_stream.StreamState) ![]u8 {
    const owner = try log_binding.createValidated(std.testing.allocator, candidate());
    defer log_binding.deinitOwner(owner);
    const row: log_rows.Row = switch (input) {
        .event => |attributed| .{ .event = .{ .attributed = attributed, .definition = try log_rows.validateEvent(attributed.fact) } },
        .prompt => |value| .{ .prompt = value },
    };
    return log_rows.render(std.testing.allocator, log_binding.binding(owner), state, &reading, row);
}

test "a fact persists as the row the production serializers give it, in either stream, from a stream with a cached state" {
    inline for (.{ log_stream.Stream.event, log_stream.Stream.prompt }) |stream| {
        var fake: Fake = .{};
        var runtime: log_stream.Runtime = .{};
        runtime.slot(stream).* = .{ .open = stateAt(3) };
        var diagnostic: routine.Diagnostic = .{};
        const input = try inputFor(stream);
        const result = try exercise(&fake, &debug_policy, &runtime, input, &diagnostic);
        try std.testing.expectEqual(@as(u64, 3), result.persisted.sequence);
        try expectKinds(&fake, &.{ .clock, .acquire, .append, .release });
        const wanted = try expectedRow(input, stateAt(3));
        defer std.testing.allocator.free(wanted);
        try std.testing.expectEqualStrings(wanted, fake.rowBytes());
        // The cached state advances by the row: its bytes, one sequence, and the flush the policy decided.
        const state = runtime.slot(stream).open;
        try std.testing.expectEqual(@as(u64, 4), state.next_sequence);
        try std.testing.expectEqual(@as(u64, 500 + wanted.len), state.segment_bytes);
        try std.testing.expectEqual(@as(?routine.Step, null), diagnostic.step);
    }
}

test "the append asks for a flush exactly when a flush trigger fires, and the cached state then agrees, in either stream" {
    const Case = struct { state: log_stream.StreamState, flush: bool };
    var idle = stateAt(3);
    idle.last_flush_monotonic_ms = reading.monotonic_ms;
    var counted = idle;
    counted.records_since_flush = log_limits.lower_level_flush_records - 1;
    var waited = idle;
    waited.last_flush_monotonic_ms = 0;
    inline for (.{ log_stream.Stream.event, log_stream.Stream.prompt }) |stream| {
        for ([_]Case{
            // No trigger: a row below the flush level, a spent budget of one, an interval just reset.
            .{ .state = idle, .flush = false },
            // The record budget alone, then the interval alone.
            .{ .state = counted, .flush = true },
            .{ .state = waited, .flush = true },
        }) |case| {
            var fake: Fake = .{};
            var runtime: log_stream.Runtime = .{};
            runtime.slot(stream).* = .{ .open = case.state };
            var diagnostic: routine.Diagnostic = .{};
            const result = try exercise(&fake, &debug_policy, &runtime, try inputFor(stream), &diagnostic);
            try std.testing.expectEqual(case.flush, result.persisted.flushed);
            try std.testing.expectEqual(@as(?bool, case.flush), fake.appended_flush);
            try std.testing.expectEqual(case.flush, runtime.slot(stream).open.records_since_flush == 0);
        }
    }
}

test "a stream with no cached state is recovered, or given its first segment, before its row" {
    var fresh: Fake = .{};
    var runtime: log_stream.Runtime = .{};
    var diagnostic: routine.Diagnostic = .{};
    const created = try exercise(&fresh, &debug_policy, &runtime, try eventInput(), &diagnostic);
    try std.testing.expectEqual(@as(u64, 1), created.persisted.sequence);
    try expectKinds(&fresh, &.{ .clock, .acquire, .recover, .create, .append, .release });
    // A stream a cancelled step dropped is recovered from its bytes the same way.
    var recovered: Fake = .{ .recovery = .{ .{ .active = stateAt(9) }, .{ .empty = seed } } };
    var dropped: log_stream.Runtime = .{ .event = .dropped };
    const resumed = try exercise(&recovered, &debug_policy, &dropped, try eventInput(), &diagnostic);
    try std.testing.expectEqual(@as(u64, 9), resumed.persisted.sequence);
    try expectKinds(&recovered, &.{ .clock, .acquire, .recover, .append, .release });
    try std.testing.expect(dropped.event == .open);
}

test "a fact the policy drops, or a fragment it does not capture, costs no clock and no lock" {
    var fake: Fake = .{};
    var runtime: log_stream.Runtime = .{};
    var diagnostic: routine.Diagnostic = .{};
    const started: routine.Input = .{ .event = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"), .fact = .{ .run_started = .{} } } };
    try std.testing.expect((try exercise(&fake, &dropping_policy, &runtime, started, &diagnostic)) == .dropped);
    try std.testing.expect(!log_policy.promptCaptureEnabled(info_policy));
    try std.testing.expect((try exercise(&fake, &info_policy, &runtime, try promptInput(), &diagnostic)) == .dropped);
    try std.testing.expectEqual(@as(usize, 0), fake.count);
}

test "an input that does not validate is a serialization failure, and a retired run a sink failure, before any clock or lock" {
    var fake: Fake = .{};
    var diagnostic: routine.Diagnostic = .{};
    var runtime: log_stream.Runtime = .{};
    var invalid = try fragment();
    invalid.retained_bytes = 3;
    const rejected = try exercise(&fake, &debug_policy, &runtime, .{ .prompt = invalid }, &diagnostic);
    try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_SERIALIZATION_FAILURE }, rejected.stopped);
    try std.testing.expectEqual(@as(?routine.Step, .validate), diagnostic.step);
    var retired: log_stream.Runtime = .{ .retired = true };
    const blocked = try exercise(&fake, &debug_policy, &retired, try eventInput(), &diagnostic);
    try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_SINK_FAILURE }, blocked.stopped);
    try std.testing.expectEqual(@as(?routine.Step, .check_status), diagnostic.step);
    try std.testing.expectEqual(@as(usize, 0), fake.count);
}

test "a clock that cannot be read is a serialization failure before any lock" {
    var fake: Fake = .{ .clock_fails = true };
    var runtime: log_stream.Runtime = .{ .event = .{ .open = stateAt(3) } };
    var diagnostic: routine.Diagnostic = .{};
    const result = try exercise(&fake, &debug_policy, &runtime, try eventInput(), &diagnostic);
    try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_SERIALIZATION_FAILURE }, result.stopped);
    try std.testing.expectEqual(@as(?routine.Step, .read_clock), diagnostic.step);
    try expectKinds(&fake, &.{.clock});
}

test "a lock that cannot be taken stops with its own code, releases nothing and leaves the stream's state alone" {
    const Case = struct { failure: sink_port.Error, stop: log_stream.Stop };
    for ([_]Case{
        .{ .failure = error.LockUnavailable, .stop = .{ .blocked = .LOG_LOCK_TIMEOUT } },
        .{ .failure = error.SinkFailure, .stop = .{ .blocked = .LOG_SINK_FAILURE } },
        .{ .failure = error.Cancelled, .stop = .cancelled },
    }) |case| {
        var fake: Fake = .{ .acquire_fails = .{ case.failure, case.failure } };
        var runtime: log_stream.Runtime = .{ .event = .{ .open = stateAt(3) } };
        var diagnostic: routine.Diagnostic = .{};
        const result = try exercise(&fake, &debug_policy, &runtime, try eventInput(), &diagnostic);
        try std.testing.expectEqual(case.stop, result.stopped);
        try std.testing.expectEqual(@as(?routine.Step, .acquire), diagnostic.step);
        try expectKinds(&fake, &.{ .clock, .acquire });
        try std.testing.expectEqual(log_stream.Slot{ .open = stateAt(3) }, runtime.event);
    }
}

test "a full segment rotates before its row, which then names the segment it opens, in either stream" {
    inline for (.{ log_stream.Stream.event, log_stream.Stream.prompt }) |stream| {
        var fake: Fake = .{};
        var runtime: log_stream.Runtime = .{};
        runtime.slot(stream).* = .{ .open = full_segment };
        var diagnostic: routine.Diagnostic = .{};
        const input = try inputFor(stream);
        const result = try exercise(&fake, &debug_policy, &runtime, input, &diagnostic);
        try std.testing.expectEqual(@as(u16, 2), result.persisted.segment_ordinal);
        try expectKinds(&fake, &.{ .clock, .acquire, .rotate, .append, .release });
        // The trailer and the next header are the production serializer's for the segment closed and the one opened.
        const owner = try log_binding.createValidated(std.testing.allocator, candidate());
        defer log_binding.deinitOwner(owner);
        const trailer = try log_rows.serializeControl(std.testing.allocator, stream, .segment_trailer, log_binding.binding(owner), 1, 2, "2026-08-30T10:15:30Z");
        defer std.testing.allocator.free(trailer);
        try std.testing.expectEqualStrings(trailer, fake.trailer[0..fake.trailer_length]);
        const next = runtime.slot(stream).open;
        try std.testing.expectEqual(@as(u16, 2), next.segment_ordinal);
        try std.testing.expectEqual(@as(u8, 2), next.segment_count);
        try std.testing.expectEqual(@as(u64, 4), next.next_sequence);
        const wanted = try expectedRow(input, fake.appended_state.?);
        defer std.testing.allocator.free(wanted);
        try std.testing.expectEqualStrings(wanted, fake.rowBytes());
        try std.testing.expectEqual(@as(u16, 2), fake.appended_state.?.segment_ordinal);
    }
}

test "a spent segment budget writes nothing, a failed rotation keeps the old state, and both release the lock" {
    var spent = full_segment;
    spent.total_segment_count = log_limits.max_segments;
    var exhausted: Fake = .{};
    var runtime: log_stream.Runtime = .{ .event = .{ .open = spent } };
    var diagnostic: routine.Diagnostic = .{};
    const limit = try exercise(&exhausted, &debug_policy, &runtime, try eventInput(), &diagnostic);
    try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_SEGMENT_LIMIT_EXHAUSTED }, limit.stopped);
    try std.testing.expectEqual(@as(?routine.Step, .rotate), diagnostic.step);
    try expectKinds(&exhausted, &.{ .clock, .acquire, .release });
    try std.testing.expectEqual(log_stream.Slot{ .open = spent }, runtime.event);

    var failing: Fake = .{ .rotate_fails = .{ error.SinkFailure, null } };
    var kept: log_stream.Runtime = .{ .event = .{ .open = full_segment } };
    const failed = try exercise(&failing, &debug_policy, &kept, try eventInput(), &diagnostic);
    try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_SINK_FAILURE }, failed.stopped);
    try expectKinds(&failing, &.{ .clock, .acquire, .rotate, .release });
    try std.testing.expectEqual(log_stream.Slot{ .open = full_segment }, kept.event);
}

test "a rotation that landed is kept in the cached state when the append after it stops, so the stream closes the segment it is really in" {
    const Case = struct { append: sink_port.Error, dropped: bool };
    for ([_]Case{
        .{ .append = error.SinkFailure, .dropped = false },
        .{ .append = error.FlushFailure, .dropped = false },
        .{ .append = error.Cancelled, .dropped = true },
    }) |case| {
        var fake: Fake = .{ .append_fails = .{ case.append, null } };
        var runtime: log_stream.Runtime = .{ .event = .{ .open = full_segment } };
        var diagnostic: routine.Diagnostic = .{};
        const result = try exercise(&fake, &debug_policy, &runtime, try eventInput(), &diagnostic);
        try std.testing.expect(result == .stopped);
        try std.testing.expectEqual(@as(?routine.Step, .append), diagnostic.step);
        try expectKinds(&fake, &.{ .clock, .acquire, .rotate, .append, .release });
        if (case.dropped) {
            // A cancelled step may have left the file ahead of any cache: the state is dropped and recovered from the bytes.
            try std.testing.expect(runtime.event == .dropped);
        } else {
            // The file holds the closed segment and the new one's header alone; the cache says so, with no row counted.
            const kept = runtime.event.open;
            try std.testing.expectEqual(@as(u16, 2), kept.segment_ordinal);
            try std.testing.expectEqual(@as(u8, 2), kept.segment_count);
            try std.testing.expectEqual(full_segment.next_sequence, kept.next_sequence);
            try std.testing.expectEqual(@as(u64, fake.header_length), kept.segment_bytes);
        }
    }
}

test "a failure at each step under the lock stops with its own code and releases the lock; a cancellation drops the stream's state" {
    const Case = struct {
        name: []const u8,
        fake: Fake,
        runtime: log_stream.Runtime,
        stop: log_stream.Stop,
        step: routine.Step,
        order: []const Kind,
        dropped: bool,
    };
    const open: log_stream.Runtime = .{ .event = .{ .open = stateAt(3) } };
    for ([_]Case{
        .{ .name = "recover fails", .fake = .{ .recover_fails = .{ error.SinkFailure, null } }, .runtime = .{}, .stop = .{ .blocked = .LOG_SINK_FAILURE }, .step = .recover, .order = &.{ .clock, .acquire, .recover, .release }, .dropped = false },
        .{ .name = "recover cancelled", .fake = .{ .recover_fails = .{ error.Cancelled, null } }, .runtime = .{}, .stop = .cancelled, .step = .recover, .order = &.{ .clock, .acquire, .recover, .release }, .dropped = true },
        .{ .name = "create fails", .fake = .{ .create_fails = .{ error.SinkFailure, null } }, .runtime = .{}, .stop = .{ .blocked = .LOG_SINK_FAILURE }, .step = .create, .order = &.{ .clock, .acquire, .recover, .create, .release }, .dropped = false },
        .{ .name = "rotation cancelled", .fake = .{ .rotate_fails = .{ error.Cancelled, null } }, .runtime = .{ .event = .{ .open = full_segment } }, .stop = .cancelled, .step = .rotate, .order = &.{ .clock, .acquire, .rotate, .release }, .dropped = true },
        .{ .name = "append fails", .fake = .{ .append_fails = .{ error.SinkFailure, null } }, .runtime = open, .stop = .{ .blocked = .LOG_SINK_FAILURE }, .step = .append, .order = &.{ .clock, .acquire, .append, .release }, .dropped = false },
        .{ .name = "flush fails", .fake = .{ .append_fails = .{ error.FlushFailure, null } }, .runtime = open, .stop = .{ .blocked = .LOG_FLUSH_FAILURE }, .step = .append, .order = &.{ .clock, .acquire, .append, .release }, .dropped = false },
        .{ .name = "append cancelled", .fake = .{ .append_fails = .{ error.Cancelled, null } }, .runtime = open, .stop = .cancelled, .step = .append, .order = &.{ .clock, .acquire, .append, .release }, .dropped = true },
    }) |case| {
        var fake = case.fake;
        var runtime = case.runtime;
        var diagnostic: routine.Diagnostic = .{};
        const result = try exercise(&fake, &debug_policy, &runtime, try eventInput(), &diagnostic);
        try std.testing.expectEqual(case.stop, result.stopped);
        try std.testing.expectEqual(@as(?routine.Step, case.step), diagnostic.step);
        try expectKinds(&fake, case.order);
        try std.testing.expectEqual(case.dropped, runtime.event == .dropped);
    }
}

test "the console mirror follows the append: a failed mirror leaves the state level with the file, and a cancelled one drops it" {
    var mirrored: Fake = .{};
    var runtime: log_stream.Runtime = .{ .event = .{ .open = stateAt(3) } };
    var diagnostic: routine.Diagnostic = .{};
    const result = try exercise(&mirrored, &mirrored_policy, &runtime, try eventInput(), &diagnostic);
    try std.testing.expectEqual(@as(u64, 3), result.persisted.sequence);
    try expectKinds(&mirrored, &.{ .clock, .acquire, .append, .console, .release });
    try std.testing.expectEqualStrings(mirrored.rowBytes(), mirrored.console_bytes[0..mirrored.console_length]);

    var failing: Fake = .{ .console_fails = error.ConsoleWriteFailure };
    var advanced: log_stream.Runtime = .{ .event = .{ .open = stateAt(3) } };
    const failed = try exercise(&failing, &mirrored_policy, &advanced, try eventInput(), &diagnostic);
    try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_SINK_FAILURE }, failed.stopped);
    try std.testing.expectEqual(@as(?routine.Step, .mirror), diagnostic.step);
    try std.testing.expectEqual(@as(u64, 4), advanced.event.open.next_sequence);

    var cancelling: Fake = .{ .console_fails = error.Cancelled };
    var dropped: log_stream.Runtime = .{ .event = .{ .open = stateAt(3) } };
    const cancelled = try exercise(&cancelling, &mirrored_policy, &dropped, try eventInput(), &diagnostic);
    try std.testing.expectEqual(log_stream.Stop.cancelled, cancelled.stopped);
    try std.testing.expect(dropped.event == .dropped);
    try expectKinds(&cancelling, &.{ .clock, .acquire, .append, .console, .release });
}

test "the persist steps that decide, serialize and measure each answer for themselves" {
    const decisions = @import("domain/feature_log_decisions.zig");
    const owner = try log_binding.createValidated(std.testing.allocator, candidate());
    defer log_binding.deinitOwner(owner);
    const binding = log_binding.binding(owner);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A fact validates to its definition and the policy emits it; a fact only the prompt stream carries is refused.
    const definition = try routine.steps.validateEvent(.{ .run_completed = .{ .outcome = .completed } });
    try std.testing.expect(routine.steps.emits(&debug_policy, definition));
    try std.testing.expectError(error.InvalidLogEventFact, routine.steps.validateEvent(.{ .model_prompt_fragment = .{} }));
    // A fragment validates when its retained bytes are its content; the policy captures fragments only at debug.
    try routine.steps.validatePrompt(try fragment());
    var invalid = try fragment();
    invalid.retained_bytes = 3;
    try std.testing.expectError(error.InvalidPromptLogFragment, routine.steps.validatePrompt(invalid));
    try std.testing.expect(routine.steps.captures(&debug_policy));
    try std.testing.expect(!routine.steps.captures(&info_policy));
    // The clock is read through its one port, and a port that fails is a failure to read.
    var working: Fake = .{};
    try std.testing.expectEqual(reading.unix_ms, (try routine.steps.readClock(working.ports().clock)).unix_ms);
    var broken: Fake = .{ .clock_fails = true };
    try std.testing.expectError(error.LogClockReadFailure, routine.steps.readClock(broken.ports().clock));
    // The header, the trailer and their measures are the production serializer's, and each measure is its bytes' length.
    inline for (.{ log_stream.Stream.event, log_stream.Stream.prompt }) |stream| {
        const header = try routine.steps.serializeHeader(a, stream, binding, 2, reading);
        try std.testing.expectEqual(header.len, try routine.steps.measureHeader(stream, binding, 2, reading));
        const trailer = try routine.steps.serializeTrailer(a, stream, binding, stateAt(5), reading);
        try std.testing.expectEqual(trailer.len, try routine.steps.measureTrailer(stream, binding, stateAt(5), reading));
        const wanted = try log_rows.serializeControl(a, stream, .segment_trailer, binding, 1, 4, "2026-08-30T10:15:30Z");
        try std.testing.expectEqualStrings(wanted, trailer);
    }
    // A row renders against the state it is given, and a state with no sequence has no event id to render under.
    const input = try eventInput();
    const row: log_rows.Row = .{ .event = .{ .attributed = input.event, .definition = definition } };
    const bytes = try routine.steps.render(a, binding, stateAt(5), reading, row);
    try std.testing.expect(bytes.len != 0);
    try std.testing.expectError(error.LogSerializationFailure, routine.steps.render(a, binding, stateAt(0), reading, row));
    // The rotation decision: a row that fits appends, a full segment rotates to the next ordinal, a spent budget is exhausted.
    try std.testing.expectEqual(@as(decisions.Rotation, .append), routine.steps.rotation(stateAt(5), 100, 50, 80));
    try std.testing.expectEqual(@as(decisions.Rotation, .{ .rotate = 2 }), routine.steps.rotation(full_segment, 100, 50, 80));
    var spent = full_segment;
    spent.total_segment_count = log_limits.max_segments;
    try std.testing.expectEqual(@as(decisions.Rotation, .exhausted), routine.steps.rotation(spent, 100, 50, 80));
    // Advancing counts the row and resets the flush budget only when the row flushed.
    try std.testing.expectEqual(@as(u8, 1), routine.steps.advance(stateAt(5), 40, false, 900).records_since_flush);
    try std.testing.expectEqual(@as(u8, 0), routine.steps.advance(stateAt(5), 40, true, 900).records_since_flush);
    // The row forces a flush only when a trigger fires: a debug row with the budget and the interval unspent does not.
    var quiet = stateAt(3);
    quiet.last_flush_monotonic_ms = reading.monotonic_ms;
    try std.testing.expect(!routine.steps.forcesFlush(&debug_policy, row, quiet, reading));
    var waited = quiet;
    waited.last_flush_monotonic_ms = 0;
    try std.testing.expect(routine.steps.forcesFlush(&debug_policy, row, waited, reading));
}

test "the persist steps that reach a port map what it reports to the stop of their kind, and take no other port" {
    const owner = try log_binding.createValidated(std.testing.allocator, candidate());
    defer log_binding.deinitOwner(owner);
    const binding = log_binding.binding(owner);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sink_failure: log_stream.Stop = .{ .blocked = .LOG_SINK_FAILURE };
    // A lock: taken, held elsewhere (a timeout), refused by the sink, or cancelled.
    var free: Fake = .{};
    try std.testing.expect(routine.steps.acquire(free.ports().acquirer, binding, .event) == null);
    for ([_]struct { failure: sink_port.Error, stop: log_stream.Stop }{
        .{ .failure = error.LockUnavailable, .stop = .{ .blocked = .LOG_LOCK_TIMEOUT } },
        .{ .failure = error.SinkFailure, .stop = sink_failure },
        .{ .failure = error.Cancelled, .stop = .cancelled },
    }) |case| {
        var fake: Fake = .{ .acquire_fails = .{ case.failure, case.failure } };
        try std.testing.expectEqual(case.stop, routine.steps.acquire(fake.ports().acquirer, binding, .event).?);
    }
    // Recovering gives the stream's state or seed, or the stop of the sink's failure.
    try std.testing.expect(routine.steps.recover(free.ports().recoverer, a, binding, .event) == .recovered);
    var unrecoverable: Fake = .{ .recover_fails = .{ error.CorruptStream, null } };
    try std.testing.expectEqual(sink_failure, routine.steps.recover(unrecoverable.ports().recoverer, a, binding, .event).stopped);
    // Creating the first segment gives its state, or a stop.
    try std.testing.expectEqual(@as(u16, 1), routine.steps.create(free.ports().creator, binding, .event, seed, "header\n").created.segment_ordinal);
    var uncreatable: Fake = .{ .create_fails = .{ error.Cancelled, null } };
    try std.testing.expectEqual(log_stream.Stop.cancelled, routine.steps.create(uncreatable.ports().creator, binding, .event, seed, "header\n").stopped);
    // Rotating gives the next segment's state, or a stop.
    try std.testing.expectEqual(@as(u16, 2), routine.steps.rotate(free.ports().rotator, binding, .event, full_segment, "trailer\n", "heading\n", "header\n").rotated.segment_ordinal);
    var unrotatable: Fake = .{ .rotate_fails = .{ error.SinkFailure, null } };
    try std.testing.expectEqual(sink_failure, routine.steps.rotate(unrotatable.ports().rotator, binding, .event, full_segment, "trailer\n", "heading\n", "header\n").stopped);
    // Appending gives the row's evidence; only an append names a failed flush.
    const appended = routine.steps.append(free.ports().appender, binding, .event, stateAt(3), "row\n", true).appended;
    try std.testing.expect(appended.flushed and appended.sequence == 3);
    var unflushable: Fake = .{ .append_fails = .{ error.FlushFailure, null } };
    try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_FLUSH_FAILURE }, routine.steps.append(unflushable.ports().appender, binding, .event, stateAt(3), "row\n", true).stopped);
    // The console is only a mirror: a failed write is a sink failure and a cancellation is none.
    try std.testing.expect(routine.steps.mirror(free.ports().console, "row\n") == null);
    var closed_console: Fake = .{ .console_fails = error.ConsoleWriteFailure };
    try std.testing.expectEqual(sink_failure, routine.steps.mirror(closed_console.ports().console, "row\n").?);
    var cancelled_console: Fake = .{ .console_fails = error.Cancelled };
    try std.testing.expectEqual(log_stream.Stop.cancelled, routine.steps.mirror(cancelled_console.ports().console, "row\n").?);
    // A release that worked, and one that failed.
    _ = routine.steps.acquire(free.ports().acquirer, binding, .event);
    try std.testing.expect(routine.steps.release(free.ports().releaser));
    var stuck: Fake = .{ .release_fails = .{ error.ReleaseFailure, null } };
    _ = routine.steps.acquire(stuck.ports().acquirer, binding, .event);
    try std.testing.expect(!routine.steps.release(stuck.ports().releaser));
}

test "a lock that cannot be released is a logging failure of its own that outranks the stop before it, and a cancellation still drops the state" {
    const Case = struct { append: ?sink_port.Error, step: routine.Step, dropped: bool };
    for ([_]Case{
        .{ .append = null, .step = .release, .dropped = false },
        .{ .append = error.SinkFailure, .step = .append, .dropped = false },
        .{ .append = error.Cancelled, .step = .append, .dropped = true },
    }) |case| {
        var fake: Fake = .{ .append_fails = .{ case.append, null }, .release_fails = .{ error.ReleaseFailure, null } };
        var runtime: log_stream.Runtime = .{ .event = .{ .open = stateAt(3) } };
        var diagnostic: routine.Diagnostic = .{};
        const result = try exercise(&fake, &debug_policy, &runtime, try eventInput(), &diagnostic);
        try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_RELEASE_FAILURE }, result.stopped);
        try std.testing.expectEqual(@as(?routine.Step, case.step), diagnostic.step);
        try std.testing.expectEqual(case.dropped, runtime.event == .dropped);
    }
}
