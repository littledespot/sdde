const pipeline = @import("../../domain/pipeline.zig");
const session = @import("../../domain/specification_session.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "check-scenario-generation-progress", .kind = .action, .requires = &.{ .specification_generation_session, .scenario_generation_progress }, .produces = &.{}, .side_effect = .none };

    /// `more` while a group with a slot still awaits its scenarios. Once every group has its criteria,
    /// the batches must hold the family this step writes (ADR 0038 Decision 3), or the assembled
    /// specification would lack a mandatory family. The check changes nothing. While a functional
    /// requirement is mandatory the records step leaves a group a slot, so `invalid` cannot fire; it is
    /// kept as the backstop for a change to the mandatory families.
    pub fn execute(_: Action, current: session.Session) @import("../../domain/workflow.zig").OutcomeTag {
        if (current.scenario_cursor < session.scenarioPopulation(current)) return .more;
        return if (session.missingScenarioFamily(current)) .invalid else .ok;
    }
};
