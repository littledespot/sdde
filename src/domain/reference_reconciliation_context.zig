//! Serializable immutable facts consumed by reconciliation validation/repair.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const v = @import("reference_reconciliation_validation.zig");
pub const TextFacts = struct {
    inputs: r.evidence.Inputs,
    policy_ids: []const []const u8,
    rules: []const @import("naming_policy.zig").BoundRule,
    names: []const @import("path_token_grammar.zig").ReferenceName,
    records: []const @import("passive_literals.zig").Record,
    occurrences: []const @import("passive_literals.zig").Occurrence,
};
pub const Facts = struct {
    source: r.diagnostic.Source,
    plan: r.Plan,
    history: []const r.Summary,
    next_statement: u32,
    partition: r.Partition,
    items: []const r.Item,
    summaries: []const r.Summary,
    member_summary_ids: []const r.SummaryId,
    proposal: @FieldType(r.Parsed, "proposal"),
    text: ?TextFacts,
};
pub fn capture(a: std.mem.Allocator, parsed: r.Parsed, context: ?v.TextContext) r.Error!Facts {
    const input = parsed.input;
    const history = try a.alloc(r.Summary, input.progress.summary_count);
    errdefer a.free(history);
    var node = input.progress.latest;
    for (history) |*entry| {
        const current = node orelse return error.InvalidReferenceReconciliation;
        entry.* = current.value;
        node = current.previous;
    }
    if (node != null) return error.InvalidReferenceReconciliation;
    return .{ .source = parsed.source, .plan = input.progress.plan, .history = history, .next_statement = input.progress.next_statement_ordinal, .partition = input.partition, .items = input.items, .summaries = input.summaries, .member_summary_ids = input.member_summary_ids, .proposal = parsed.proposal, .text = if (context) |ctx| .{ .inputs = ctx.inputs, .policy_ids = ctx.registry.grammar.policy.policy_ids, .rules = ctx.registry.grammar.policy.rules, .names = ctx.registry.grammar.reference_names, .records = ctx.registry.records, .occurrences = ctx.registry.occurrences } else null };
}
pub fn snapshot(a: std.mem.Allocator, parsed: r.Parsed, context: ?v.TextContext) r.Error!@import("atomic_repair.zig").Snapshot {
    const facts = try capture(a, parsed, context);
    defer a.free(facts.history);
    return @import("atomic_repair.zig").snapshot(Facts, a, facts);
}
