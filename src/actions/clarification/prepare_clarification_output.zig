const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const c = @import("../../domain/clarification_inputs.zig");
const views = @import("../../domain/clarification_views.zig");
const output = @import("../../domain/workflow_output.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "prepare-clarification-output",
        .kind = .action,
        .requires = &.{ .feature_directory, .feature_artifact_paths, .raw_clarification_inputs, .clarification_inputs, .refreshed_clarification_state, .clarification_views },
        .produces = &.{.prepared_workflow_output},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, feature: @import("../../domain/feature_directory.zig").Directory, paths: @import("../../domain/workflow_artifact_registry.zig").FeaturePaths, prior: c.Captures, inputs: c.Inputs, state: @import("../../domain/clarification_refresh.zig").Result, rendered: []const views.View) (output.Error || c.Error || @import("../../domain/canonical_json.zig").Error)!output.Prepared {
        return @import("../../domain/clarification_output.zig").prepare(allocator, feature, paths, prior, inputs, state, rendered);
    }
};
