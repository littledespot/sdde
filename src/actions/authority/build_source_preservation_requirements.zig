const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const a = @import("../../domain/required_authority.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-source-preservation-requirements", .kind = .action, .requires = &.{ .relative_feature_directory, .accounted_reference_reconciliation, .citable_reference_inputs }, .produces = &.{.required_authority_inputs}, .side_effect = .none };

    pub fn execute(_: Action, allocator: std.mem.Allocator, feature: @import("../../domain/feature_identity.zig").FeatureId, references: @import("../../domain/reference_reconciliation.zig").Accounted, sources: @import("../../domain/reference_evidence.zig").Inputs) a.Error!a.Inputs {
        return @import("../../domain/source_preservation.zig").project(allocator, feature, @import("../../domain/reference_support.zig").records(references), sources);
    }
};
