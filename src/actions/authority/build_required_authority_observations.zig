const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const a = @import("../../domain/required_authority.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-required-authority-observations", .kind = .action, .requires = &.{.required_authority_ledger}, .produces = &.{.required_authority_observations}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, ledger: a.Ledger) a.Error!a.Observations {
        return a.buildObservations(allocator, ledger);
    }
};
