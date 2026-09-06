const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-reference-reconciliation-summary", .kind = .action, .requires = &.{.reference_summary_identities}, .produces = &.{}, .replaces = &.{.reference_reconciliation_progress}, .invalidates = &.{ .reference_reconciliation_input, .raw_reference_reconciliation, .parsed_reference_reconciliation, .validated_reference_summary, .reference_summary_identities }, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, assignment: r.SummaryAssignment) r.Error!r.Progress {
        const checked = assignment.checked;
        if (assignment.statement_ids.len != checked.statements.len) return error.InvalidReferenceReconciliation;
        const statements = try allocator.alloc(r.Statement, checked.statements.len);
        for (checked.statements, assignment.statement_ids, statements) |value, id, *statement| statement.* = .{ .id = id, .claim_ids = value.claim_ids, .content = value.content };
        const latest = try allocator.create(r.SummaryHistory);
        latest.* = .{ .previous = checked.input.progress.latest, .value = .{ .id = assignment.id, .partition_id = checked.input.partition.id, .member_claim_ids = checked.input.partition.group.claim_ids, .member_summary_ids = checked.input.member_summary_ids, .statements = statements } };
        return .{ .plan = checked.input.progress.plan, .latest = latest, .summary_count = checked.input.progress.summary_count + 1, .next_statement_ordinal = assignment.next_statement_ordinal };
    }
};
