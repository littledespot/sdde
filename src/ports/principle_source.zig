const std = @import("std");
const registry = @import("../domain/principle_registry.zig");
const roots = @import("../domain/bootstrap_root_registry.zig");
pub const Error = registry.Error || error{PrincipleSourceUnavailable};
pub const Reader = struct {
    context: *anyopaque,
    capability: ?*const roots.ConfiguredBaseRootCapability = null,
    read_fn: *const fn (*anyopaque, *const roots.ConfiguredBaseRootCapability, std.mem.Allocator) Error!registry.Captured,
    pub fn read(self: Reader, a: std.mem.Allocator) Error!registry.Captured {
        return self.read_fn(self.context, self.capability orelse return error.PrincipleSourceUnavailable, a);
    }
};
pub const Enumerator = struct {
    context: *anyopaque,
    capability: ?*const roots.ConfiguredBaseRootCapability = null,
    enumerate_fn: *const fn (*anyopaque, *const roots.ConfiguredBaseRootCapability, std.mem.Allocator) Error!registry.Raw,
    pub fn enumerate(self: Enumerator, a: std.mem.Allocator) Error!registry.Raw {
        return self.enumerate_fn(self.context, self.capability orelse return error.PrincipleSourceUnavailable, a);
    }
};
pub const Capturer = struct {
    context: *anyopaque,
    capability: ?*const roots.ConfiguredBaseRootCapability = null,
    capture_fn: *const fn (*anyopaque, *const roots.ConfiguredBaseRootCapability, std.mem.Allocator, registry.Inventory) Error!registry.Captured,
    pub fn capture(self: Capturer, a: std.mem.Allocator, inventory: registry.Inventory) Error!registry.Captured {
        return self.capture_fn(self.context, self.capability orelse return error.PrincipleSourceUnavailable, a, inventory);
    }
};
