const selector = @import("../../domain/reference_selector.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-reference-selector@1",
        .kind = .action,
        .requires = &.{.normalized_reference_selector},
        .produces = &.{.relative_reference_selector},
        .side_effect = .none,
    };
    pub fn execute(_: Action, candidate: selector.NormalizedCandidate) selector.Error!selector.RelativeSelector {
        return selector.validate(candidate);
    }
};
