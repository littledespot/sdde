const std = @import("std");
const feature = @import("../../domain/feature_directory.zig");

pub const Action = struct {
    roots: ?feature.Roots = null,
    pub const contract: @import("../../domain/pipeline.zig").NodeContract = .{
        .id = "validate-feature-directory@1",
        .kind = .action,
        .requires = &.{.normalized_feature_directory},
        .produces = &.{.relative_feature_directory},
        .side_effect = .none,
    };

    pub fn execute(self: Action, allocator: std.mem.Allocator, candidate: feature.NormalizedCandidate) feature.Error!feature.Selector {
        return feature.validate(allocator, candidate, self.roots orelse return error.InvalidFeatureDirectory);
    }
};
