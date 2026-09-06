const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const spec = @import("../../domain/specification.zig");
const codec = @import("../../domain/specification_markdown.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-specification-rendering",
        .kind = .action,
        .requires = &.{ .specification_document, .rendered_specification },
        .produces = &.{.validated_specification_rendering},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, document: spec.CapturedDocument, bytes: []const u8) codec.Error!void {
        const parsed = try codec.parse(allocator, bytes);
        const normalized = try codec.render(allocator, parsed);
        defer allocator.free(normalized);
        const expected = try codec.render(allocator, document);
        defer allocator.free(expected);
        if (!std.mem.eql(u8, expected, bytes) or !std.mem.eql(u8, normalized, bytes)) return error.InvalidSpecification;
    }
};
