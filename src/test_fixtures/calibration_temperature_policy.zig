//! Compare current offline projections with immutable temperature-0 captures.
//! Only the amended control changes; all remaining provider bytes must match.
const std = @import("std");
const controls = @import("../domain/model_controls.zig");

pub const temperature = controls.Temperature.fixed.wireValue();

pub fn request(a: std.mem.Allocator, historical: []const u8) ![]const u8 {
    var value = try std.json.parseFromSliceLeaky(std.json.Value, a, historical, .{});
    const field = value.object.getPtr("temperature") orelse return error.InvalidHistoricalTemperature;
    if (field.* != .integer or field.integer != 0) return error.InvalidHistoricalTemperature;
    field.* = .{ .float = temperature };
    return std.json.Stringify.valueAlloc(a, value, .{});
}

pub fn expectProjection(a: std.mem.Allocator, suffix: []const u8, historical: []const u8, current: []const u8) !void {
    try std.testing.expectEqualStrings(if (std.mem.endsWith(u8, suffix, "request.json")) try request(a, historical) else historical, current);
}

test "historical projection changes only the approved temperature" {
    const a = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const projected = try request(arena.allocator(), "{\"temperature\":0,\"reasoning_effort\":\"low\",\"max_completion_tokens\":16384}");
    try std.testing.expectEqualStrings("{\"temperature\":0.1,\"reasoning_effort\":\"low\",\"max_completion_tokens\":16384}", projected);
    for ([_][]const u8{ "{}", "{\"temperature\":null}", "{\"temperature\":0.25}" }) |invalid|
        try std.testing.expectError(error.InvalidHistoricalTemperature, request(arena.allocator(), invalid));
}
