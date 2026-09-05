const pipeline = @import("../../domain/pipeline.zig");
const clarification = @import("../../domain/clarification_inputs.zig");
const feature = @import("../../domain/feature_identity.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-clarification-state@1",
        .kind = .action,
        .requires = &.{ .parsed_clarification_state, .feature_artifact_paths },
        .produces = &.{.validated_clarification_state},
        .side_effect = .none,
    };
    pub fn execute(_: Action, parsed: clarification.ParsedState, selected: feature.FeatureId) clarification.Error!clarification.ValidatedState {
        return clarification.validate(parsed, selected);
    }
};
