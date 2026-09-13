const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/specification_repair.zig");
const session = @import("../../domain/specification_session.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "authorize-specification-repair", .kind = .action, .requires = &.{ .specification_generation_session, .parsed_specification_unit, .validated_specification_unit }, .produces = &.{.specification_repair_authorization}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, current: session.Session, candidate: repair.Candidate, rejection: @import("../../domain/specification_candidate.zig").Rejection) repair.Error!repair.Authorization {
        return repair.authorize(allocator, current, candidate, rejection);
    }
};
