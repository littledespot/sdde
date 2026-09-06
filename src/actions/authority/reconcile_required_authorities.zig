const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const a = @import("../../domain/required_authority.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "reconcile-required-authorities", .kind = .action, .requires = &.{ .required_authority_ledger, .required_authority_observations }, .produces = &.{.required_authority_result}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, ledger: a.Ledger, observations: a.Observations) a.Error!a.Result {
        return a.reconcile(allocator, ledger, observations);
    }
};
