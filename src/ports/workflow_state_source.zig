const std = @import("std");
const roots = @import("../domain/bootstrap_root_registry.zig");
const feature = @import("../domain/feature_directory.zig");
const artifacts = @import("../domain/workflow_artifact_registry.zig");
pub const Error = std.mem.Allocator.Error || error{FeatureInputUnavailable};
pub const Capturer = struct {
    context: *anyopaque,
    capability: ?*const roots.FeatureInputReadCapability = null,
    capture_fn: *const fn (*anyopaque, *const roots.FeatureInputReadCapability, std.mem.Allocator, feature.Directory, artifacts.FeaturePaths) Error!?[]const u8,
    pub fn capture(self: Capturer, allocator: std.mem.Allocator, observed: feature.Directory, paths: artifacts.FeaturePaths) Error!?[]const u8 {
        return self.capture_fn(self.context, self.capability orelse return error.FeatureInputUnavailable, allocator, observed, paths);
    }
};
