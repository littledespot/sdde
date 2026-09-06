const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const a = @import("../../domain/required_authority.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "parse-required-authority-observations", .kind = .action, .requires = &.{.raw_required_authority_observations}, .produces = &.{.required_authority_observations}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, bytes: []const u8) a.Error!a.Observations {
        return a.parse(allocator, bytes);
    }
};
