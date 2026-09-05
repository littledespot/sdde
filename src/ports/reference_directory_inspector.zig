const std = @import("std");
const roots = @import("../domain/bootstrap_root_registry.zig");
const reference = @import("../domain/reference_selector.zig");

pub const Error = std.mem.Allocator.Error || error{ReferenceDirectoryUnavailable};
pub const Inspector = struct {
    context: *anyopaque,
    capability: ?*const roots.ConfiguredBaseRootCapability = null,
    inspect_fn: *const fn (*anyopaque, *const roots.ConfiguredBaseRootCapability, std.mem.Allocator, reference.RelativeSelector) Error!reference.Directory,

    pub fn inspect(self: Inspector, allocator: std.mem.Allocator, selector: reference.RelativeSelector) Error!reference.Directory {
        return self.inspect_fn(self.context, self.capability orelse return error.ReferenceDirectoryUnavailable, allocator, selector);
    }
};
