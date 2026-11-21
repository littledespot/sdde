const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const g = @import("../../domain/specification_generation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "parse-specification-unit", .kind = .action, .requires = &.{ .raw_specification_unit, .specification_generation_session, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals }, .produces = &.{.parsed_specification_unit}, .side_effect = .none };
    /// The unit's response: while scenarios are written (ADR 0038 Decision 3), the answer's numbered
    /// scenarios bound to their slots' claims, as the acceptance criteria of the group's batch.
    pub fn execute(_: Action, allocator: std.mem.Allocator, bytes: []const u8, current: @import("../../domain/specification_session.zig").Session, context: @import("../../domain/specification_provenance.zig").Context) @import("../../domain/scenario_request.zig").Error!g.Response {
        const session = @import("../../domain/specification_session.zig");
        const bound = try session.currentBinding(allocator, current, context);
        if (!session.scenarioPhase(current)) return g.parse(allocator, bytes, bound);
        return .{ .content = .{ .records = try @import("../../domain/scenario_request.zig").parse(allocator, bytes, try session.scenarioPlan(allocator, current), bound.records) } };
    }
};
