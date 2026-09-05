const std = @import("std");
const roots = @import("../domain/bootstrap_root_registry.zig");
const artifacts = @import("../domain/workflow_artifact_registry.zig");
const directory = @import("../domain/feature_directory.zig");
const clarification = @import("../domain/clarification_inputs.zig");

pub const Error = std.mem.Allocator.Error || error{FeatureInputUnavailable};
pub const Capturer = struct {
    context: *anyopaque,
    capability: ?*const roots.FeatureInputReadCapability = null,
    capture_fn: *const fn (*anyopaque, *const roots.FeatureInputReadCapability, std.mem.Allocator, directory.Directory, artifacts.FeaturePaths) Error!clarification.Captures,

    pub fn capture(self: Capturer, allocator: std.mem.Allocator, observed: directory.Directory, paths: artifacts.FeaturePaths) Error!clarification.Captures {
        return self.capture_fn(self.context, self.capability orelse return error.FeatureInputUnavailable, allocator, observed, paths);
    }
};
