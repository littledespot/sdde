const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const view = @import("../../domain/reference_context.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "render-reference-context", .kind = .action, .requires = &.{.specification_publication_state}, .produces = &.{.rendered_reference_context}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, state: @import("../../domain/specification_state.zig").State) view.Error![]const u8 {
        return view.render(allocator, state.reference, state.principle_assessment);
    }
};
