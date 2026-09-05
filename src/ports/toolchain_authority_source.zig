const std = @import("std");
const roots = @import("../domain/bootstrap_root_registry.zig");
const toolchain = @import("../domain/toolchain.zig");

pub const Error = error{InvalidToolchainSource};
pub const ProjectCapturer = struct {
    context: *anyopaque,
    capability: ?*const roots.ConfiguredBaseRootCapability = null,
    capture_project_fn: *const fn (*anyopaque, *const roots.ConfiguredBaseRootCapability, std.mem.Allocator) Error!toolchain.Capture,
    pub fn captureProject(self: ProjectCapturer, allocator: std.mem.Allocator) Error!toolchain.Capture {
        return self.capture_project_fn(self.context, self.capability orelse return error.InvalidToolchainSource, allocator);
    }
};
pub const PresetEnumerator = struct {
    context: *anyopaque,
    capability: ?*const roots.ConfiguredBaseRootCapability = null,
    inventory_presets_fn: *const fn (*anyopaque, *const roots.ConfiguredBaseRootCapability, std.mem.Allocator) Error![]const toolchain.Entry,
    pub fn inventoryPresets(self: PresetEnumerator, allocator: std.mem.Allocator) Error![]const toolchain.Entry {
        return self.inventory_presets_fn(self.context, self.capability orelse return error.InvalidToolchainSource, allocator);
    }
};
pub const PresetCapturer = struct {
    context: *anyopaque,
    capability: ?*const roots.ConfiguredBaseRootCapability = null,
    capture_preset_fn: *const fn (*anyopaque, *const roots.ConfiguredBaseRootCapability, toolchain.Entry, std.mem.Allocator) Error!toolchain.Capture,
    pub fn capturePreset(self: PresetCapturer, entry: toolchain.Entry, allocator: std.mem.Allocator) Error!toolchain.Capture {
        return self.capture_preset_fn(self.context, self.capability orelse return error.InvalidToolchainSource, entry, allocator);
    }
};
