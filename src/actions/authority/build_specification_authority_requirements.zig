const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const a = @import("../../domain/required_authority.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-specification-authority-requirements", .kind = .action, .requires = &.{ .relative_feature_directory, .accounted_reference_reconciliation }, .optional = &.{ .identified_specification_content, .specification_generation_session }, .produces = &.{.required_authority_inputs}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, feature: @import("../../domain/feature_identity.zig").FeatureId, references: @import("../../domain/reference_reconciliation.zig").Accounted, content: ?@import("../../domain/specification.zig").IdentifiedContent, brief: ?@import("../../domain/specification.zig").Brief) a.Error!a.Inputs {
        return @import("../../domain/specification_authority.zig").project(allocator, feature, references, content, brief);
    }
};
