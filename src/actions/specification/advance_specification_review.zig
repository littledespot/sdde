const pipeline = @import("../../domain/pipeline.zig");
const std = @import("std");
const review = @import("../../domain/specification_review.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "advance-specification-review", .kind = .action, .requires = &.{ .specification_support_review, .principle_registry }, .produces = &.{}, .replaces = &.{.specification_support_review}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, current: review.Progress, registry: @import("../../domain/principle_registry.zig").Registry) review.Error!review.Advanced {
        return review.advance(a, current, registry);
    }
};
