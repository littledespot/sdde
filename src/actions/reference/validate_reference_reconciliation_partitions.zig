const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-reconciliation-partitions", .kind = .action, .requires = &.{.reference_reconciliation_plan}, .produces = &.{.reference_reconciliation_progress}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, plan: r.Plan) r.Error!r.Progress {
        try @import("../../domain/reference_reconciliation_partition.zig").validate(allocator, plan);
        return .{ .plan = plan, .latest = null, .summary_count = 0, .next_statement_ordinal = 1 };
    }
};
