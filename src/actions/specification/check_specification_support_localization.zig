const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "check-specification-support-localization", .kind = .action, .requires = &.{.specification_support_review}, .produces = &.{}, .side_effect = .none };
    pub const Outcome = enum { complete, next, localize };

    pub fn execute(_: Action, current: @import("../../domain/specification_review.zig").Progress) Outcome {
        const collection = switch (current) {
            .initial, .pending => return .next,
            .source => |value| value,
            .principles => |value| return switch (value.result) {
                .accepted => .complete,
                .pending => .next,
                .rejected => .next,
            },
        };
        return switch (collection) {
            .accepted => |value| if (value.candidate.pending_localization != null) .localize else .complete,
            .pending => |value| if (value.pending_localization != null) .localize else .next,
            .rejected => .next,
        };
    }
};
