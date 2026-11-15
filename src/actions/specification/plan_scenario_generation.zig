const pipeline = @import("../../domain/pipeline.zig");
const session = @import("../../domain/specification_session.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "plan-scenario-generation", .kind = .action, .requires = &.{ .specification_generation_session, .accounted_reference_reconciliation }, .produces = &.{.scenario_generation_progress}, .side_effect = .none };

    /// The population of the scenarios step: the groups with a slot (`session.scenarioPopulation`), once
    /// every group's records are admitted and none of their scenarios are. It plans only; the session
    /// is unchanged (ADR 0038 Decision 3).
    pub fn execute(_: Action, current: session.Session) session.Error!usize {
        if (!session.scenarioPhase(current) or current.scenario_cursor != 0) return error.InvalidSpecificationUnit;
        return session.scenarioPopulation(current);
    }
};
