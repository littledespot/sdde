const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const view = @import("../../domain/reference_context.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "render-reference-context", .kind = .action, .requires = &.{.reference_snapshot}, .produces = &.{.rendered_reference_context}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, snapshot: @import("../../domain/reference_snapshot.zig").Snapshot) view.Error![]const u8 {
        return view.render(allocator, snapshot);
    }
};
