const pipeline = @import("../../domain/pipeline.zig");
const session = @import("../../domain/specification_session.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "advance-scenario-generation", .kind = .action, .requires = &.{ .accounted_reference_reconciliation, .specification_generation_session, .scenario_generation_progress, .validated_specification_unit }, .produces = &.{}, .replaces = &.{ .specification_generation_session, .scenario_generation_progress }, .invalidates = &.{ .raw_specification_unit, .parsed_specification_unit, .validated_specification_unit }, .side_effect = .none };

    /// The session with the validated criteria joined to their group's batch, and the group counted as
    /// written. It completes nothing: the records unit completes in `complete-scenario-generation`.
    pub fn execute(_: Action, allocator: @import("std").mem.Allocator, current: session.Session, checked: @import("../../domain/specification_generation.zig").Checked) session.Error!session.Session {
        return session.appendScenarios(allocator, current, checked);
    }
};
