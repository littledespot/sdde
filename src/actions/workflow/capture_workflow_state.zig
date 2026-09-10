const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const source = @import("../../ports/workflow_state_source.zig");
pub const Action = struct {
    source: ?source.Capturer = null,
    pub const contract: pipeline.NodeContract = .{ .id = "capture-workflow-state", .kind = .action, .requires = &.{ .feature_directory, .feature_artifact_paths }, .produces = &.{.raw_workflow_state}, .side_effect = .filesystem_read };
    pub fn execute(self: Action, allocator: std.mem.Allocator, feature: @import("../../domain/feature_directory.zig").Directory, paths: @import("../../domain/workflow_artifact_registry.zig").FeaturePaths) source.Error!?[]const u8 {
        return (self.source orelse return error.FeatureInputUnavailable).capture(allocator, feature, paths);
    }
};
