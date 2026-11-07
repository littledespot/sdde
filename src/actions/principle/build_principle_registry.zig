const pipeline = @import("../../domain/pipeline.zig");
const std = @import("std");
const registry = @import("../../domain/principle_registry.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-principle-registry", .kind = .action, .requires = &.{.captured_principles}, .optional = &.{.prior_principle_registry}, .produces = &.{.principle_registry}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, captured: registry.Captured, prior: ?registry.Registry) registry.Error!registry.Registry {
        return registry.build(a, captured, prior);
    }
};
