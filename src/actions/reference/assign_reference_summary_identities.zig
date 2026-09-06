const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "assign-reference-summary-identities", .kind = .action, .requires = &.{.validated_reference_summary}, .produces = &.{.reference_summary_identities}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, checked: r.CheckedSummary) r.Error!r.SummaryAssignment {
        const id: r.SummaryId = .{ .ordinal = try r.ordinal(checked.input.progress.summary_count) };
        if (id.ordinal != checked.input.partition.id.ordinal) return error.InvalidReferenceReconciliation;
        const ids = try allocator.alloc(r.StatementId, checked.statements.len);
        var next = checked.input.progress.next_statement_ordinal;
        for (ids) |*statement| {
            statement.* = .{ .ordinal = next };
            next = try r.next(next);
        }
        return .{ .checked = checked, .id = id, .statement_ids = ids, .next_statement_ordinal = next };
    }
};
