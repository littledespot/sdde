const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const c = @import("../../domain/clarification_inputs.zig");
const views = @import("../../domain/clarification_views.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "render-clarification-forms",
        .kind = .action,
        .requires = &.{ .clarification_inputs, .refreshed_clarification_state },
        .produces = &.{.clarification_views},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, state: c.ValidatedState, inputs: c.Inputs) c.Error![]const views.View {
        return views.render(allocator, state, inputs.protected_forms);
    }
};
