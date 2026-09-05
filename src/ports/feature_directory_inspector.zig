const std = @import("std");
const feature = @import("../domain/feature_directory.zig");
const roots = @import("../domain/bootstrap_root_registry.zig");

pub const Error = std.mem.Allocator.Error || error{FeatureDirectoryUnavailable};
pub const Inspector = struct {
    context: *anyopaque,
    specs: ?*const roots.ConfiguredBaseRootCapability = null,
    archive: ?*const roots.ConfiguredBaseRootCapability = null,
    inspect_fn: *const fn (*anyopaque, *const roots.ConfiguredBaseRootCapability, *const roots.ConfiguredBaseRootCapability, std.mem.Allocator, feature.Selector) Error!feature.Directory,

    pub fn inspect(self: Inspector, allocator: std.mem.Allocator, selector: feature.Selector) Error!feature.Directory {
        return self.inspect_fn(self.context, self.specs orelse return error.FeatureDirectoryUnavailable, self.archive orelse return error.FeatureDirectoryUnavailable, allocator, selector);
    }
};
