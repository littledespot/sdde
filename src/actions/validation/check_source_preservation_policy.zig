const pipeline = @import("../../domain/pipeline.zig");
const config = @import("../../domain/config.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "check-source-preservation-policy", .kind = .action, .requires = &.{}, .produces = &.{}, .side_effect = .none };

    pub fn execute(_: Action, policy: *const config.ValidationConfig) @import("../../domain/workflow.zig").OutcomeTag {
        return if (policy.sourcePreservationCheck) .ok else .more;
    }
};

test "policy enables only the optional branch" {
    const std = @import("std");
    try std.testing.expectEqual(.more, (Action{}).execute(&.{}));
    try std.testing.expectEqual(.more, (Action{}).execute(&.{ .sourcePreservationCheck = false }));
    try std.testing.expectEqual(.ok, (Action{}).execute(&.{ .sourcePreservationCheck = true }));
}
