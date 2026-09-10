const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const state = @import("../../domain/specification_state.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "parse-specification-state", .kind = .action, .requires = &.{ .feature_directory, .raw_workflow_state }, .produces = &.{.prior_specification_state}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, feature: @import("../../domain/feature_identity.zig").FeatureId, bytes: ?[]const u8) state.Error!state.Prior {
        return state.parse(allocator, bytes, feature);
    }
};
