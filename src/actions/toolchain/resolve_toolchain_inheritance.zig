const std = @import("std");
const toolchain = @import("../../domain/toolchain.zig");
const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "resolve-toolchain-inheritance@1", .kind = .action, .requires = &.{ .schema_valid_project_toolchain, .schema_valid_toolchain_registry }, .produces = &.{.resolved_toolchain_inheritance}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, project: toolchain.Project, registry: toolchain.Registry) toolchain.Error!toolchain.Resolved {
        return toolchain.resolve(allocator, project, registry);
    }
};
