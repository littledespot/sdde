const std = @import("std");
const registry = @import("../domain/principle_registry.zig");
const roots = @import("../domain/bootstrap_root_registry.zig");
pub const Error = @import("../domain/operation_error.zig").PrincipleSource;
pub const Reader = struct {
    context: *anyopaque,
    capability: ?*const roots.ConfiguredBaseRootCapability = null,
    read_fn: *const fn (*anyopaque, *const roots.ConfiguredBaseRootCapability, std.mem.Allocator) Error!registry.Captured,
    pub fn read(self: Reader, a: std.mem.Allocator) Error!registry.Captured {
        return self.read_fn(self.context, self.capability orelse return error.PrincipleSourceUnavailable, a);
    }
};
