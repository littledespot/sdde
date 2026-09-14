//! Serializable immutable facts consumed by reconciliation validation/repair.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const v = @import("reference_reconciliation_validation.zig");
pub const Lineage = struct {
    plan: r.Plan,
    history: []const r.Summary,
    next_statement: u32,
};
/// Flatten the execution-owned chain once for every validator dependency owner.
/// Only history is allocated here; the other fields borrow their input owner.
pub fn lineage(a: std.mem.Allocator, progress: r.Progress) r.Error!Lineage {
    const history = try a.alloc(r.Summary, progress.summary_count);
    errdefer a.free(history);
    var node = progress.latest;
    for (history) |*entry| {
        const current = node orelse return error.InvalidReferenceReconciliation;
        entry.* = current.value;
        node = current.previous;
    }
    if (node != null) return error.InvalidReferenceReconciliation;
    return .{ .plan = progress.plan, .history = history, .next_statement = progress.next_statement_ordinal };
}
pub const Facts = struct {
    source: r.diagnostic.Source,
    lineage: Lineage,
    partition: r.Partition,
    purpose: @FieldType(r.Input, "purpose"),
    items: []const r.Item,
    summaries: []const r.Summary,
    member_summary_ids: []const r.SummaryId,
    proposal: @FieldType(r.Parsed, "proposal"),
    text: ?r.text.Dependencies,
};
pub fn capture(a: std.mem.Allocator, parsed: r.Parsed, context: ?v.TextContext) r.Error!Facts {
    const input = parsed.input;
    const retained = try lineage(a, input.progress);
    errdefer a.free(retained.history);
    return .{ .source = parsed.source, .lineage = retained, .partition = input.partition, .purpose = input.purpose, .items = input.items, .summaries = input.summaries, .member_summary_ids = input.member_summary_ids, .proposal = parsed.proposal, .text = if (context) |ctx| try r.text.dependencies(ctx.inputs, ctx.registry, ctx.current) else null };
}
pub fn snapshot(a: std.mem.Allocator, parsed: r.Parsed, context: ?v.TextContext) r.Error!@import("atomic_repair.zig").Snapshot {
    const facts = try capture(a, parsed, context);
    defer a.free(facts.lineage.history);
    return @import("atomic_repair.zig").snapshot(Facts, a, facts);
}
