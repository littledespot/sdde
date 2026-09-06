const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const g = @import("../../domain/specification_generation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "parse-specification-unit", .kind = .action, .requires = &.{.raw_specification_unit}, .produces = &.{.parsed_specification_unit}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, bytes: []const u8) g.Error!g.Response {
        return g.parse(allocator, bytes);
    }
};
