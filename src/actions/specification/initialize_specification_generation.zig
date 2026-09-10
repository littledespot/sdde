const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "initialize-specification-generation", .kind = .action, .requires = &.{ .relative_feature_directory, .prior_specification_state, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain }, .produces = &.{.specification_generation_session}, .side_effect = .none };
    pub fn execute(_: Action, feature: @import("../../domain/feature_identity.zig").FeatureId, context: @import("../../domain/specification_provenance.zig").Context, prior: @import("../../domain/specification_state.zig").Prior) @import("../../domain/specification_session.zig").Error!@import("../../domain/specification_session.zig").Session {
        var result = try @import("../../domain/specification_session.zig").initialize(feature, context);
        if (prior.state) |state| result.starting_ledger = state.id_ledger;
        return result;
    }
};
