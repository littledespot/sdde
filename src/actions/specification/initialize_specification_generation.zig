const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "initialize-specification-generation", .kind = .action, .requires = &.{ .relative_feature_directory, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain }, .produces = &.{.specification_generation_session}, .side_effect = .none };
    pub fn execute(_: Action, feature: @import("../../domain/feature_identity.zig").FeatureId, context: @import("../../domain/specification_provenance.zig").Context) @import("../../domain/specification_session.zig").Error!@import("../../domain/specification_session.zig").Session {
        return @import("../../domain/specification_session.zig").initialize(feature, context);
    }
};
