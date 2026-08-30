const std = @import("std");
const roots = @import("../domain/bootstrap_root_registry.zig");
const toolchain = @import("../domain/toolchain.zig");

pub const Error = error{InvalidToolchainSource};
pub const Source = struct {
    context: *anyopaque,
    capture_project_fn: *const fn (*anyopaque, *const roots.ConfiguredBaseRootCapability, std.mem.Allocator) Error!toolchain.Capture,
    inventory_presets_fn: *const fn (*anyopaque, *const roots.ConfiguredBaseRootCapability, std.mem.Allocator) Error![]const toolchain.Entry,
    capture_preset_fn: *const fn (*anyopaque, *const roots.ConfiguredBaseRootCapability, toolchain.Entry, std.mem.Allocator) Error!toolchain.Capture,
    pub fn captureProject(self: Source, capability: *const roots.ConfiguredBaseRootCapability, allocator: std.mem.Allocator) Error!toolchain.Capture {
        return self.capture_project_fn(self.context, capability, allocator);
    }
    pub fn inventoryPresets(self: Source, capability: *const roots.ConfiguredBaseRootCapability, allocator: std.mem.Allocator) Error![]const toolchain.Entry {
        return self.inventory_presets_fn(self.context, capability, allocator);
    }
    pub fn capturePreset(self: Source, capability: *const roots.ConfiguredBaseRootCapability, entry: toolchain.Entry, allocator: std.mem.Allocator) Error!toolchain.Capture {
        return self.capture_preset_fn(self.context, capability, entry, allocator);
    }
};
