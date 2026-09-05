const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const artifacts = @import("../../domain/workflow_artifact_registry.zig");
const feature = @import("../../domain/feature_directory.zig");

pub const Action = struct {
    roots: ?artifacts.FeatureRoots = null,
    pub const contract: pipeline.NodeContract = .{
        .id = "resolve-feature-artifact-paths@1",
        .kind = .action,
        .requires = &.{.feature_directory},
        .produces = &.{.feature_artifact_paths},
        .side_effect = .none,
    };
    pub fn execute(self: Action, allocator: std.mem.Allocator, selected: feature.Directory) !artifacts.FeaturePaths {
        return artifacts.resolveFeaturePaths(allocator, self.roots orelse return error.InvalidFeatureArtifactPath, selected.selector);
    }
};
