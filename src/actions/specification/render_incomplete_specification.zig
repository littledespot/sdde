const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const draft = @import("../../domain/incomplete_specification.zig");
const codec = @import("../../domain/incomplete_specification_markdown.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "render-incomplete-specification",
        .kind = .action,
        .requires = &.{ .incomplete_specification_state, .refreshed_clarification_state },
        .produces = &.{.rendered_incomplete_specification},
        .side_effect = .none,
    };
    pub fn execute(_: Action, a: std.mem.Allocator, value: draft.State, clarifications: @import("../../domain/clarification_refresh.zig").Result) codec.Error![]const u8 {
        if (clarifications != .ready) return error.InvalidIncompleteSpecification;
        return codec.render(a, value, clarifications.ready);
    }
};
