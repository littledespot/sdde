const pipeline = @import("../../domain/pipeline.zig");
const std = @import("std");
const registry = @import("../../domain/principle_registry.zig");
pub const Action = struct {
    source: ?@import("../../ports/principle_source.zig").Reader = null,
    pub const contract: pipeline.NodeContract = .{ .id = "capture-principle-registry", .kind = .action, .requires = &.{}, .optional = &.{.prior_principle_registry}, .produces = &.{.principle_registry}, .side_effect = .filesystem_read };
    pub fn execute(self: Action, a: std.mem.Allocator, prior: ?registry.Registry) @import("../../ports/principle_source.zig").Error!registry.Registry {
        const reader = self.source orelse return error.PrincipleSourceUnavailable;
        const captured = try reader.read(a);
        return registry.build(a, captured, prior);
    }
};
