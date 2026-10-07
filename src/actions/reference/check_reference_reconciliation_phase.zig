const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "check-reference-reconciliation-phase", .kind = .action, .requires = &.{.parsed_reference_reconciliation}, .produces = &.{}, .side_effect = .none };
    pub fn execute(_: Action, current: r.Parsed, expected: r.Phase) @import("../../domain/workflow.zig").OutcomeTag {
        return if (current.phase == expected or (expected == .signals and current.phase == .signals_with_conflicts)) .ok else .more;
    }
};
