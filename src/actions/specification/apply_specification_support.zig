const pipeline = @import("../../domain/pipeline.zig");
const support = @import("../../domain/specification_support.zig").Source;
const authority = @import("../../domain/required_authority.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "apply-specification-support", .kind = .action, .requires = &.{ .required_authority_inputs, .specification_support_review }, .produces = &.{}, .replaces = &.{.required_authority_inputs}, .side_effect = .none };
    pub fn execute(_: Action, reviewed: support.Collection) authority.Error!authority.Inputs {
        return switch (reviewed) {
            .accepted => |accepted| accepted.inputs,
            .rejected => error.InvalidRequiredAuthority,
        };
    }
};
