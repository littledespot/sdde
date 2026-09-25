const pipeline = @import("../../domain/pipeline.zig");
const provenance = @import("../../domain/specification_provenance.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "check-specification-source-readiness", .kind = .action, .requires = &.{.accounted_reference_reconciliation}, .produces = &.{}, .side_effect = .none };
    pub fn execute(_: Action, references: @import("../../domain/reference_reconciliation.zig").Accounted) @import("../../domain/workflow.zig").OutcomeTag {
        return if (provenance.generationReady(references)) .ok else .blocked;
    }
};
