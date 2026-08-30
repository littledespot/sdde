const std = @import("std");
const toolchain = @import("../../domain/toolchain.zig");
const composition = @import("../../domain/toolchain_composition.zig");
const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "compose-toolchain@1", .kind = .action, .requires = &.{ .schema_valid_project_toolchain, .resolved_toolchain_inheritance }, .produces = &.{.composed_toolchain}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, project: toolchain.Project, resolved: toolchain.Resolved) toolchain.Error!toolchain.Composed {
        return composition.compose(allocator, project, resolved);
    }
};
