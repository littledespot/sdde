const std = @import("std");
const roots = @import("../domain/bootstrap_root_registry.zig");
const feature = @import("../domain/feature_directory.zig");
const binding = @import("../domain/feature_log_binding.zig");
const active = @import("../domain/active_feature_directory.zig");

pub const Error = std.mem.Allocator.Error || error{ InvalidFeatureLogLayout, FeatureLogLayoutUnavailable, InsecurePermissions, Cancelled };
pub const Context = opaque {};
pub const Port = struct {
    context: *Context,
    activate_fn: *const fn (*Context, std.mem.Allocator, *const roots.FeatureOutputWriteCapability, feature.Directory, *const binding.ValidatedFeatureLogBinding) Error!*active.Owner,

    pub fn activate(self: Port, allocator: std.mem.Allocator, authority: *const roots.FeatureOutputWriteCapability, prior: feature.Directory, log: *const binding.ValidatedFeatureLogBinding) Error!*active.Owner {
        return self.activate_fn(self.context, allocator, authority, prior, log);
    }
};
