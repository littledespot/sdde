const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/specification_repair.zig");
const session = @import("../../domain/specification_session.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "merge-specification-repair", .kind = .action, .requires = &.{ .specification_generation_session, .parsed_specification_unit, .specification_repair_authorization, .specification_repair_result }, .produces = &.{}, .replaces = &.{.parsed_specification_unit}, .invalidates = &.{ .validated_specification_unit, .specification_repair_authorization, .specification_repair_result }, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, current: session.Session, candidate: repair.Candidate, authorization: repair.Authorization, replacement: repair.Replacement) repair.Error!repair.Candidate {
        return repair.merge(allocator, current, candidate, authorization, replacement);
    }
};
