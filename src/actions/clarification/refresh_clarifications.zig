const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const c = @import("../../domain/clarification_inputs.zig");
const refresh = @import("../../domain/clarification_refresh.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "refresh-clarifications",
        .kind = .action,
        .requires = &.{ .clarification_inputs, .clarification_needs },
        .produces = &.{.refreshed_clarification_state},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: c.Inputs, needs: refresh.Needs) refresh.Error!c.ValidatedState {
        return refresh.refresh(allocator, inputs, needs);
    }
};
