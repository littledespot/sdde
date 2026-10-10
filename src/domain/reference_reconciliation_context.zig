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
    phase: r.Phase,
    source: r.diagnostic.Source,
    carried_from: ?r.SummaryId,
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
    return .{ .phase = parsed.phase, .source = parsed.source, .carried_from = parsed.carried_from, .lineage = retained, .partition = input.partition, .purpose = input.purpose, .items = input.items, .summaries = input.summaries, .member_summary_ids = input.member_summary_ids, .proposal = parsed.proposal, .text = if (context) |ctx| try r.text.dependencies(ctx.inputs, ctx.registry, ctx.current) else null };
}
pub fn snapshot(a: std.mem.Allocator, parsed: r.Parsed, context: ?v.TextContext) r.Error!@import("atomic_repair.zig").Snapshot {
    const facts = try capture(a, parsed, context);
    defer a.free(facts.lineage.history);
    return @import("atomic_repair.zig").snapshot(Facts, a, facts);
}

/// Acceptance proof for native reuse. Bind content and original occurrence
/// evidence as well as source bytes, exact-token ownership and text policy.
pub fn summarySnapshot(a: std.mem.Allocator, items: r.Items, projection: r.SummaryProjection, context: v.TextContext) r.Error!@import("atomic_repair.zig").Snapshot {
    const SummaryFacts = struct { items: r.Items, projection: r.SummaryProjection, text: r.text.Dependencies };
    return @import("atomic_repair.zig").snapshot(SummaryFacts, a, .{ .items = items, .projection = projection, .text = try r.text.dependencies(context.inputs, context.registry, context.current) });
}
