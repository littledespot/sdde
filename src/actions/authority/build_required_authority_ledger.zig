const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const a = @import("../../domain/required_authority.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-required-authority-ledger", .kind = .action, .requires = &.{.required_authority_inputs}, .produces = &.{.required_authority_ledger}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: a.Inputs) a.Error!a.Ledger {
        return a.build(allocator, inputs);
    }
};
