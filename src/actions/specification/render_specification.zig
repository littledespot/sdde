const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const codec = @import("../../domain/specification_markdown.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "render-specification",
        .kind = .action,
        .requires = &.{.specification_document},
        .produces = &.{.rendered_specification},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, document: @import("../../domain/specification.zig").CapturedDocument) codec.Error![]const u8 {
        return codec.render(allocator, document);
    }
};
