const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const feature = @import("../../domain/feature_directory.zig");
const artifacts = @import("../../domain/workflow_artifact_registry.zig");
const clarification = @import("../../domain/clarification_inputs.zig");
const source = @import("../../ports/feature_input_source.zig");

pub const Action = struct {
    source: source.Capturer,
    pub const contract: pipeline.NodeContract = .{
        .id = "capture-clarification-inputs@1",
        .kind = .action,
        .requires = &.{ .feature_directory, .feature_artifact_paths },
        .produces = &.{.raw_clarification_inputs},
        .side_effect = .none,
    };
    pub fn execute(self: Action, allocator: std.mem.Allocator, observed: feature.Directory, paths: artifacts.FeaturePaths) source.Error!clarification.Captures {
        return self.source.capture(allocator, observed, paths);
    }
};
