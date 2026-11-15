const pipeline = @import("../../domain/pipeline.zig");
const session = @import("../../domain/specification_session.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "check-specification-generation-progress", .kind = .action, .requires = &.{.specification_generation_session}, .produces = &.{}, .side_effect = .none };
    /// `more` while a source group still awaits its records. Once every group's records are admitted,
    /// `invalid` when a mandatory family this step authors is missing: a model can omit one, and that
    /// is no complete specification. The scenarios follow in a step of their own, which checks the
    /// family it writes (ADR 0038 Decision 3).
    pub fn execute(_: Action, current: session.Session) @import("../../domain/workflow.zig").OutcomeTag {
        if (current.record_cursor < current.record_group_count) return .more;
        return if (session.missingRecordsFamily(current)) .invalid else .ok;
    }
};
