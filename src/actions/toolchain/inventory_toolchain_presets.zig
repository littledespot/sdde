const std = @import("std");
const toolchain = @import("../../domain/toolchain.zig");
const source_port = @import("../../ports/toolchain_authority_source.zig");
const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    source: source_port.PresetEnumerator,
    pub const contract: pipeline.NodeContract = .{ .id = "inventory-toolchain-presets@1", .kind = .action, .requires = &.{}, .produces = &.{.toolchain_preset_inventory}, .side_effect = .filesystem_read };
    pub fn execute(self: Action, allocator: std.mem.Allocator) toolchain.Error![]const toolchain.Entry {
        return self.source.inventoryPresets(allocator) catch error.InvalidToolchain;
    }
};
