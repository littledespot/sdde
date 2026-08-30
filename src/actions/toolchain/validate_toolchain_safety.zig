const std = @import("std");
const toolchain = @import("../../domain/toolchain.zig");
const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    registry: toolchain.PolicyRegistry,
    pub const contract: pipeline.NodeContract = .{ .id = "validate-toolchain-safety@1", .kind = .action, .requires = &.{.composed_toolchain}, .produces = &.{.valid_toolchain}, .side_effect = .none };
    pub fn execute(self: Action, allocator: std.mem.Allocator, composed: toolchain.Composed) toolchain.Error!*toolchain.Owner {
        return toolchain.validateSafety(allocator, composed, self.registry);
    }
};
