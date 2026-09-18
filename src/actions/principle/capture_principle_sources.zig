const pipeline = @import("../../domain/pipeline.zig");
const std = @import("std");
const registry = @import("../../domain/principle_registry.zig");
const port = @import("../../ports/principle_source.zig");
pub const Action = struct {
    source: ?port.Capturer = null,
    pub const contract: pipeline.NodeContract = .{ .id = "capture-principle-sources", .kind = .action, .requires = &.{.principle_inventory}, .produces = &.{.captured_principles}, .side_effect = .filesystem_read };
    pub fn execute(self: Action, a: std.mem.Allocator, inventory: registry.Inventory) port.Error!registry.Captured {
        return (self.source orelse return error.PrincipleSourceUnavailable).capture(a, inventory);
    }
};
