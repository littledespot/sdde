const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/specification_repair.zig");
const session = @import("../../domain/specification_session.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "authorize-specification-repair", .kind = .action, .requires = &.{ .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .specification_generation_session, .parsed_specification_unit, .validated_specification_unit }, .produces = &.{.specification_repair_authorization}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, current: session.Session, context: @import("../../domain/specification_provenance.zig").Context, candidate: repair.Candidate, rejection: @import("../../domain/specification_candidate.zig").Rejection) repair.Error!repair.Authorization {
        return repair.authorize(allocator, current, context, candidate, rejection);
    }
};
