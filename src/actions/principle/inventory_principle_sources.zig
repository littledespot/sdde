const pipeline = @import("../../domain/pipeline.zig");
const std = @import("std");
const port = @import("../../ports/principle_source.zig");
pub const Action = struct {
    source: ?port.Enumerator = null,
    pub const contract: pipeline.NodeContract = .{ .id = "inventory-principle-sources", .kind = .action, .requires = &.{}, .produces = &.{.raw_principle_inventory}, .side_effect = .filesystem_read };
    pub fn execute(self: Action, a: std.mem.Allocator) port.Error!@import("../../domain/principle_registry.zig").Raw {
        return (self.source orelse return error.PrincipleSourceUnavailable).enumerate(a);
    }
};
