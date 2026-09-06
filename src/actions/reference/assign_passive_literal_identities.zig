const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const literals = @import("../../domain/passive_literals.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "assign-passive-literal-identities", .kind = .action, .requires = &.{.passive_literal_candidates}, .produces = &.{.passive_literal_identities}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, candidates: literals.Candidates) literals.Error!literals.Assigned {
        return literals.assign(allocator, candidates);
    }
};
