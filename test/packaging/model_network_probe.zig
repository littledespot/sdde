//! Exercised as an ordinary executable behind the offline packaging root.
const std = @import("std");
const native = @import("native_model_http");
pub const live_model_connections = true;

pub fn main() !void {
    if (@import("builtin").is_test) return error.ExpectedOrdinaryExecutable;
    // Even a regression in the guard cannot reach the network in this probe.
    var client: std.http.Client = .{ .allocator = std.heap.page_allocator, .io = .failing };
    defer client.deinit();
    try std.testing.expectError(error.LiveModelCallsDisabled, native.request(&client, .POST, try std.Uri.parse("https://api.openai.com/v1/responses"), .{
        .headers = .{ .authorization = .{ .override = "Bearer test-credential" } },
    }));
}
