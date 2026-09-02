const std = @import("std");
const roots = @import("../../domain/bootstrap_root_registry.zig");
const toolchain = @import("../../domain/toolchain.zig");
const source_port = @import("../../ports/toolchain_authority_source.zig");
const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    source: source_port.PresetEnumerator,
    pub const contract: pipeline.NodeContract = .{ .id = "inventory-toolchain-presets@1", .kind = .action, .requires = &.{.bootstrap_root_registry}, .produces = &.{.toolchain_preset_inventory}, .side_effect = .filesystem_read };
    pub fn execute(self: Action, allocator: std.mem.Allocator, registry: *const roots.BootstrapRootRegistry) toolchain.Error![]const toolchain.Entry {
        return self.source.inventoryPresets(registry.toolchainPresetRegistry(), allocator) catch error.InvalidToolchain;
    }
};
