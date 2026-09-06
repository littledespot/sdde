const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const a = @import("../../domain/required_authority.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-required-authority-reconciliation", .kind = .action, .requires = &.{ .required_authority_inputs, .required_authority_observations, .required_authority_result }, .produces = &.{.required_authority_gate}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: a.Inputs, observations: a.Observations, result: a.Result) a.Error!bool {
        return a.validate(allocator, inputs, observations, result);
    }
};
