const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "initialize-specification-review-history", .kind = .action, .requires = &.{}, .produces = &.{.specification_review_history}, .side_effect = .none };
    pub fn execute(_: Action) @import("../../domain/specification_review_retention.zig").History {
        return .{};
    }
};
