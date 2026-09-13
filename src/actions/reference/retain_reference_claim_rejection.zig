//! Return the original model-selection rejection to its repair boundary.
const pipeline = @import("../../domain/pipeline.zig");
const rejection = @import("../../domain/reference_selection_validation.zig").Rejection;
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "retain-reference-claim-rejection",
        .kind = .action,
        .requires = &.{.validated_reference_claims},
        .produces = &.{},
        .replaces = &.{.validated_reference_selections},
        .invalidates = &.{ .validated_reference_claims, .prepared_reference_claims, .preserved_token_identities },
        .side_effect = .none,
    };
    pub fn execute(_: Action, value: rejection) rejection {
        return value;
    }
};
