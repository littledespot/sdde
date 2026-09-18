const pipeline = @import("../../domain/pipeline.zig");
const a = @import("../../domain/required_authority.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "initialize-specification-review", .kind = .action, .requires = &.{.required_authority_inputs}, .produces = &.{.specification_support_review}, .side_effect = .none };
    pub fn execute(_: Action, inputs: a.Inputs) a.Error!@import("../../domain/specification_review.zig").Progress {
        if (inputs.projection != .specification or inputs.evidence.len != 0 or inputs.candidates.len != 0) return error.InvalidRequiredAuthority;
        return .initial;
    }
};
