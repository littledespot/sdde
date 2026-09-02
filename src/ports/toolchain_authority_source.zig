const std = @import("std");
const roots = @import("../domain/bootstrap_root_registry.zig");
const toolchain = @import("../domain/toolchain.zig");

pub const Error = error{InvalidToolchainSource};
pub const ProjectCapturer = struct {
    context: *anyopaque,
    capture_project_fn: *const fn (*anyopaque, *const roots.ConfiguredBaseRootCapability, std.mem.Allocator) Error!toolchain.Capture,
    pub fn captureProject(self: ProjectCapturer, capability: *const roots.ConfiguredBaseRootCapability, allocator: std.mem.Allocator) Error!toolchain.Capture {
        return self.capture_project_fn(self.context, capability, allocator);
    }
};
pub const PresetEnumerator = struct {
    context: *anyopaque,
    inventory_presets_fn: *const fn (*anyopaque, *const roots.ConfiguredBaseRootCapability, std.mem.Allocator) Error![]const toolchain.Entry,
    pub fn inventoryPresets(self: PresetEnumerator, capability: *const roots.ConfiguredBaseRootCapability, allocator: std.mem.Allocator) Error![]const toolchain.Entry {
        return self.inventory_presets_fn(self.context, capability, allocator);
    }
};
pub const PresetCapturer = struct {
    context: *anyopaque,
    capture_preset_fn: *const fn (*anyopaque, *const roots.ConfiguredBaseRootCapability, toolchain.Entry, std.mem.Allocator) Error!toolchain.Capture,
    pub fn capturePreset(self: PresetCapturer, capability: *const roots.ConfiguredBaseRootCapability, entry: toolchain.Entry, allocator: std.mem.Allocator) Error!toolchain.Capture {
        return self.capture_preset_fn(self.context, capability, entry, allocator);
    }
};
