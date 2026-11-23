const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const c = @import("../../domain/clarification_inputs.zig");
const authentication = @import("../../domain/clarification_authentication.zig");

/// Plans the authentication loop: its iteration is the closed forms that await an account, one pass for each.
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "plan-clarification-authentication",
        .kind = .action,
        .requires = &.{.clarification_inputs},
        .produces = &.{.authentication_progress},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: c.Inputs) std.mem.Allocator.Error!authentication.Progress {
        return authentication.plan(allocator, inputs);
    }
};
