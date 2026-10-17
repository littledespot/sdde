const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const a = @import("../../domain/required_authority.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-required-authority-clarification-needs", .kind = .action, .requires = &.{ .citable_reference_inputs, .required_authority_inputs, .required_authority_observations, .required_authority_result }, .produces = &.{.clarification_needs}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, sources: @import("../../domain/reference_evidence.zig").Inputs, inputs: a.Inputs, observations: a.Observations, result: a.Result) a.Error!@import("../../domain/clarification_refresh.zig").Needs {
        return @import("../../domain/required_authority_clarifications.zig").build(allocator, sources, inputs, observations, result);
    }
};
