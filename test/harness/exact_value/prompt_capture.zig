//! Offline inventory adapter. Only the current canonical archive decoder runs;
//! unsupported historical descriptions are inventoried, never reinterpreted.
const std = @import("std");
const archive = @import("../../../src/domain/request_debugger_archive.zig");
const debug = @import("../../../src/domain/request_debugger.zig");
pub const Status = enum { current, unsupported_description, invalid_archive };
pub const Result = struct {
    status: Status,
    calls: []const debug.Call = &.{},
    reason: ?[]const u8 = null,
    owner: ?std.heap.ArenaAllocator = null,

    /// Calls and every decoded witness remain owned until this release.
    pub fn deinit(self: Result) void {
        if (self.owner) |retained| {
            var owner = retained;
            owner.deinit();
        }
    }
};

/// Expected unsupported/invalid observations are closed dispositions. Exposed
/// canonical allocation failures propagate; this adapter adds no fallback reader.
/// Some existing canonical decode sites classify their own OOM as invalid input;
/// that inherited behavior is not changed by this isolated prototype.
pub fn capture(a: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error!Result {
    var owner: std.heap.ArenaAllocator = .init(a);
    var transferred = false;
    defer if (!transferred) owner.deinit();
    var current: archive.Archive = .{ .allocator = owner.allocator() };
    current.ingest(bytes) catch |err| return classify(err);
    const calls = current.calls() catch |err| return classify(err);
    transferred = true;
    return .{ .status = .current, .calls = calls, .owner = owner };
}
fn classify(err: archive.Error) std.mem.Allocator.Error!Result {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.UnsupportedDebugDescriptionVersion => .{ .status = .unsupported_description, .reason = @errorName(err) },
        error.InvalidDebugArchive => .{ .status = .invalid_archive, .reason = @errorName(err) },
    };
}

test "offline prompt inventory delegates accepted unsupported and invalid archives without legacy interpretation" {
    const a = std.testing.allocator;
    const current_bytes = try fixtureLog(a, "provider_body", "{}");
    defer a.free(current_bytes);
    const current = try capture(a, current_bytes);
    defer current.deinit();
    try std.testing.expectEqual(.current, current.status);
    try std.testing.expectEqual(@as(usize, 1), current.calls.len);
    try std.testing.expect(current.calls[0].description == null);
    try std.testing.expect(current.calls[0].request_complete);
    try std.testing.expectEqualStrings("{}", current.calls[0].request.?);
    const unsupported_bytes = try fixtureLog(a, "request_description", "{\"version\":\"model-request-debug/v3\"}");
    defer a.free(unsupported_bytes);
    const unsupported = try capture(a, unsupported_bytes);
    defer unsupported.deinit();
    try std.testing.expectEqual(.unsupported_description, unsupported.status);
    try std.testing.expectEqual(@as(usize, 0), unsupported.calls.len);
    try std.testing.expectEqualStrings("UnsupportedDebugDescriptionVersion", unsupported.reason.?);
    const malformed_bytes = try fixtureLog(a, "request_description", "{\"version\":\"model-request-debug/v5\"}");
    defer a.free(malformed_bytes);
    const malformed = try capture(a, malformed_bytes);
    defer malformed.deinit();
    try std.testing.expectEqual(.invalid_archive, malformed.status);
    try std.testing.expectEqual(@as(usize, 0), malformed.calls.len);
    const bad_heading = try capture(a, "different log format\n");
    defer bad_heading.deinit();
    try std.testing.expectEqual(.invalid_archive, bad_heading.status);
}

test "offline prompt inventory owns parsed data independently of input log bytes" {
    const a = std.testing.allocator;
    const bytes = try fixtureLog(a, "provider_body", "{} ");
    const current = try capture(a, bytes);
    a.free(bytes);
    defer current.deinit();
    try std.testing.expectEqualStrings("request-1-inference-1", current.calls[0].id);
    try std.testing.expectEqualStrings("{} ", current.calls[0].request.?);
}

fn fixtureLog(a: std.mem.Allocator, provenance: []const u8, body: []const u8) ![]const u8 {
    const format = @import("../../../src/domain/feature_log_format.zig");
    const origin: @import("../../../src/domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const fragment = try std.fmt.allocPrint(a, "inference-request-{s}-utf8-0", .{provenance});
    defer a.free(fragment);
    const row = try format.serializePrompt(a, .{
        .log_policy_id = .{ .bytes = "offline-policy" },
        .binding_id = .{ .bytes = "offline-binding" },
        .segment_ordinal = 1,
        .event_id = .{ .bytes = "event-1" },
        .sequence = 1,
        .occurred_at_utc = "2026-10-16T00:00:00Z",
        .monotonic_offset = 0,
        .run_id = .{ .bytes = "offline-run" },
        .feature_id = .{ .bytes = "offline-feature" },
        .fragment = .{
            .workflow_shortcode = try @import("../../../src/domain/telemetry.zig").WorkflowShortcode.parse("SPEC"),
            .node_id = .{ .bytes = "offline-invoke" },
            .attempt = 1,
            .request_id = .{ .bytes = "request-1" },
            .route_id = .{ .bytes = "offline-prepare" },
            .model_profile_id = .{ .bytes = "offline-model" },
            .fragment_id = .{ .bytes = fragment },
            .direction = .request,
            .body_class = .complete_body,
            .content = body,
            .retained_bytes = @intCast(body.len),
            .truncated = false,
            .redacted = false,
            .attribution = .{
                .workflow_id = .{ .bytes = "offline-workflow" },
                .action_id = .{ .bytes = "invoke-model" },
                .call = origin,
                .links = .{ .kind = .initial, .original = origin, .parent = null, .source = .none },
            },
            .body_bytes = body.len,
        },
    });
    defer a.free(row);
    return std.mem.concat(a, u8, &.{ format.prompt_heading, row });
}
