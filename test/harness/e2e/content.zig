//! Compare independently authored expected business content with published
//! content. This is fixture conformance, never a semantic rubric judgment.
const std = @import("std");
const spec = @import("../../../src/domain/specification.zig");
const codec = @import("../../../src/domain/specification_markdown.zig");

pub fn matches(allocator: std.mem.Allocator, expected: []const u8, observed: []const u8) !bool {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const wanted = try codec.parse(a, expected);
    const actual = codec.parse(a, observed) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidSpecification => false,
    };
    // Reruns retain monotonic engine IDs. Compare meaning-bearing fields while
    // requiring valid IDs and canonical bytes on the published side.
    spec.validateDocument(actual, true) catch return false;
    if (!std.mem.eql(u8, observed, try codec.render(a, actual))) return false;
    return std.mem.eql(u8, try contentBytes(a, wanted), try contentBytes(a, actual));
}

fn contentBytes(a: std.mem.Allocator, document: spec.CapturedDocument) ![]const u8 {
    const records = try a.alloc(spec.Content(spec.Scalar), document.records.len);
    for (document.records, records) |record, *content| content.* = record.content;
    return std.json.Stringify.valueAlloc(a, .{ .display_name = document.display_name, .primary_user_story = document.primary_user_story, .records = records, .entity_section = document.entity_section }, .{});
}
