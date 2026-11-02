const pipeline = @import("../../domain/pipeline.zig");
const session = @import("../../domain/specification_session.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "check-specification-generation-progress", .kind = .action, .requires = &.{.specification_generation_session}, .produces = &.{}, .side_effect = .none };
    pub fn execute(_: Action, current: session.Session) @import("../../domain/workflow.zig").OutcomeTag {
        if (current.completed != session.unit_count) return .more;
        return if (session.missingRequiredFamily(current)) .invalid else .ok;
    }
};
