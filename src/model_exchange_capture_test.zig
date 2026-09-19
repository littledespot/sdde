const std = @import("std");
const capture = @import("application/model_exchange_capture.zig");
const prompt = @import("domain/sanitized_prompt_log.zig");
const stream = @import("domain/feature_log_stream.zig");
const telemetry = @import("domain/telemetry.zig");

const Sink = struct {
    allocator: std.mem.Allocator,
    fragments: std.ArrayList(prompt.SanitizedPromptFragment) = .empty,
    enabled: bool = true,
    failure_at: ?usize = null,
    drop: bool = false,
    fn barrier(self: *Sink) @import("ports/telemetry_barrier.zig").Barrier {
        return .{ .context = self, .process_fn = event, .select_prompt_fn = select, .process_prompt_fn = process };
    }
    fn event(_: *anyopaque, _: telemetry.WorkflowTelemetryFact) stream.Outcome {
        return .dropped;
    }
    fn select(context: *anyopaque, fragment: prompt.SanitizedPromptFragment) bool {
        const self: *Sink = @ptrCast(@alignCast(context));
        std.debug.assert(fragment.body_class == .complete_body);
        return self.enabled;
    }
    fn process(context: *anyopaque, fragment: prompt.SanitizedPromptFragment) stream.Outcome {
        const self: *Sink = @ptrCast(@alignCast(context));
        if (self.drop) return .dropped;
        if (self.failure_at == self.fragments.items.len) return .{ .blocked = .LOG_FLUSH_FAILURE };
        prompt.validate(fragment) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        var copy = fragment;
        copy.content = self.allocator.dupe(u8, fragment.content) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        copy.fragment_id.bytes = self.allocator.dupe(u8, fragment.fragment_id.bytes) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        copy.request_id.bytes = self.allocator.dupe(u8, fragment.request_id.bytes) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        self.fragments.append(self.allocator, copy) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        return .{ .persisted = .{ .sequence = self.fragments.items.len, .segment_ordinal = 1, .bytes_written = fragment.content.len, .flushed = true } };
    }
};
const metadata: capture.Metadata = .{
    .workflow = telemetry.WorkflowShortcode.parse("SPEC") catch unreachable,
    .node = .{ .bytes = "invoke-part" },
    .operation = .{ .bytes = "generate-part" },
    .model_slot = .{ .bytes = "generation" },
    .origin = .{ .request = .{ .value = 4 }, .attempt = .{ .value = 70000 } },
};

test "model capture preserves full sanitized bodies and existing request attempt identity" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sink: Sink = .{ .allocator = a };
    var logger: capture.Capture = .{ .allocator = a, .logs = sink.barrier() };
    logger.begin(metadata);
    defer logger.end();
    const prefix = try a.alloc(u8, 4997);
    @memset(prefix, 'a');
    const suffix = try a.alloc(u8, 170000);
    @memset(suffix, 'z');
    const body = try std.mem.concat(a, u8, &.{ prefix, "credential-秘密", suffix, "\ncomplete tail 🐈" });
    try std.testing.expectEqual(.recorded, logger.port().capture(.request, .{ .provider_body = body }, &.{"credential-秘密"}));
    try std.testing.expect(sink.fragments.items.len > 32);
    var restored: std.ArrayList(u8) = .empty;
    for (sink.fragments.items, 0..) |fragment, index| {
        try std.testing.expectEqual(@as(u32, 70000), fragment.attempt);
        try std.testing.expectEqualStrings("request-4", fragment.request_id.bytes);
        try std.testing.expectEqualStrings("generate-part", fragment.route_id.bytes);
        try std.testing.expectEqualStrings("generation", fragment.model_profile_id.bytes);
        try std.testing.expect(fragment.redacted and !fragment.truncated);
        try std.testing.expect(std.mem.startsWith(u8, fragment.fragment_id.bytes, "inference-request-provider_body-utf8-"));
        if (index > 0) try std.testing.expect(std.mem.order(u8, sink.fragments.items[index - 1].fragment_id.bytes, fragment.fragment_id.bytes) == .lt);
        try restored.appendSlice(a, fragment.content);
    }
    const expected = try std.mem.concat(a, u8, &.{ prefix, "[REDACTED_CREDENTIAL]", suffix, "\ncomplete tail 🐈" });
    try std.testing.expectEqualStrings(expected, restored.items);
    const before = sink.fragments.items.len;
    try std.testing.expectEqual(.recorded, logger.port().capture(.response, .{ .provider_body = "broken model JSON {" }, &.{}));
    try std.testing.expectEqualStrings("broken model JSON {", sink.fragments.items[before].content);
    try std.testing.expectEqual(.response, sink.fragments.items[before].direction);
    try std.testing.expectEqual(.recorded, logger.port().capture(.response, .{ .transport_outcome = .{ .outcome = .cancelled } }, &.{}));
    try std.testing.expect(std.mem.startsWith(u8, sink.fragments.items[before + 1].fragment_id.bytes, "inference-response-transport_outcome-utf8-"));
    try std.testing.expect(!std.mem.eql(u8, sink.fragments.items[before].fragment_id.bytes, sink.fragments.items[before + 1].fragment_id.bytes));
    try std.testing.expect(logger.failure == null);
}

test "capture keeps binary provider responses reversible and counting distinct" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sink: Sink = .{ .allocator = a };
    var logger: capture.Capture = .{ .allocator = a, .logs = sink.barrier() };
    var count_metadata = metadata;
    count_metadata.origin.kind = .input_token_count;
    logger.begin(count_metadata);
    defer logger.end();
    try std.testing.expectEqual(.recorded, logger.port().capture(.response, .{ .provider_body = "\xff\x00" }, &.{}));
    try std.testing.expectEqualStrings("/wA=", sink.fragments.items[0].content);
    try std.testing.expect(std.mem.startsWith(u8, sink.fragments.items[0].fragment_id.bytes, "input_token_count-response-provider_body-base64-"));
    try std.testing.expectEqual(.recorded, logger.port().capture(.request, .{ .provider_body = "" }, &.{}));
    try std.testing.expectEqualStrings("", sink.fragments.items[1].content);
}

test "capture serialization failure records logging failure without a false body" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var sink: Sink = .{ .allocator = arena.allocator() };
    var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .fail_index = 0 });
    var logger: capture.Capture = .{ .allocator = failing.allocator(), .logs = sink.barrier() };
    logger.begin(metadata);
    defer logger.end();
    try std.testing.expectEqual(.blocked, logger.port().capture(.response, .{ .transport_outcome = .{ .outcome = .transport_failed } }, &.{}));
    try std.testing.expectEqual(.LOG_SERIALIZATION_FAILURE, logger.failure.?);
    try std.testing.expectEqual(@as(usize, 0), sink.fragments.items.len);
}

test "capture honors disabled selection and makes persistence failures sticky" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sink: Sink = .{ .allocator = a, .enabled = false };
    var logger: capture.Capture = .{ .allocator = a, .logs = sink.barrier() };
    logger.begin(metadata);
    defer logger.end();
    try std.testing.expectEqual(.disabled, logger.port().capture(.request, .{ .provider_body = "private" }, &.{}));
    try std.testing.expectEqual(@as(usize, 0), sink.fragments.items.len);
    sink.enabled = true;
    sink.failure_at = 1;
    const body = try a.alloc(u8, 10001);
    @memset(body, 'x');
    try std.testing.expectEqual(.blocked, logger.port().capture(.request, .{ .provider_body = body }, &.{}));
    try std.testing.expectEqual(.LOG_FLUSH_FAILURE, logger.failure.?);
    try std.testing.expectEqual(@as(usize, 1), sink.fragments.items.len);
    sink.failure_at = null;
    try std.testing.expectEqual(.blocked, logger.port().capture(.response, .{ .provider_body = "must not continue" }, &.{}));
    try std.testing.expectEqual(@as(usize, 1), sink.fragments.items.len);
    var drop_logger: capture.Capture = .{ .allocator = a, .logs = sink.barrier() };
    sink.drop = true;
    drop_logger.begin(metadata);
    defer drop_logger.end();
    try std.testing.expectEqual(.blocked, drop_logger.port().capture(.response, .{ .provider_body = "unexpectedly dropped" }, &.{}));
    try std.testing.expectEqual(.LOG_SERIALIZATION_FAILURE, drop_logger.failure.?);
}
