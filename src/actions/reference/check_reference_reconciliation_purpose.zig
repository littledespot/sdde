const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "check-reference-reconciliation-purpose", .kind = .action, .requires = &.{.reference_reconciliation_input}, .produces = &.{}, .side_effect = .none };
    pub fn execute(_: Action, input: @import("../../domain/reference_reconciliation.zig").Input) @import("../../domain/workflow.zig").OutcomeTag {
        return switch (input.purpose) {
            .summary => .more,
            .global => .ok,
        };
    }
};
