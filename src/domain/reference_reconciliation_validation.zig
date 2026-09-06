//! Shared joins and scoped text checks for summaries, signals and conflicts.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
pub const TextContext = struct { registry: @import("passive_literals.zig").Registry, current: *const @import("toolchain_safety.zig").ValidToolchain, inputs: r.evidence.Inputs };

pub fn bind(allocator: std.mem.Allocator, items: r.Items, context: TextContext, validator: r.text.Validator) r.Error!void {
    if (!items.state_id.eql(context.inputs.corpus.state_id)) return error.InvalidReferenceReconciliation;
    try @import("path_token_grammar.zig").validateBinding(allocator, context.registry.grammar, context.current, context.inputs, validator.normalizer, validator.folder);
}

pub fn claims(items: r.Items, ids: []const r.ClaimId, allowed: []const r.ClaimId) r.Error!void {
    if (ids.len == 0) return error.InvalidReferenceReconciliation;
    try r.unique(r.ClaimId, ids);
    for (ids) |id| {
        _ = try r.item(items, id);
        if (!r.contains(r.ClaimId, allowed, id)) return error.InvalidReferenceReconciliation;
    }
}
pub fn scopes(allocator: std.mem.Allocator, items: r.Items, ids: []const r.ClaimId, context: TextContext) r.Error!r.text.ScopeSetContext {
    const result = try allocator.alloc(r.evidence.Scope, ids.len);
    if (!items.state_id.eql(context.inputs.corpus.state_id)) return error.InvalidReferenceReconciliation;
    for (ids, result) |id, *scope| scope.* = .{ .state_id = items.state_id, .chunk_id = (try r.item(items, id)).claim.chunk_id };
    return .{ .registry = context.registry, .current = context.current, .inputs = context.inputs, .scopes = result };
}
pub fn content(allocator: std.mem.Allocator, validator: r.text.Validator, context: TextContext, items: r.Items, ids: []const r.ClaimId, candidate: r.ContentProposal) r.Error!r.Content {
    if (ids.len == 0) return error.InvalidReferenceReconciliation;
    switch (candidate) {
        .model => |model| {
            for (ids) |id| {
                const original = (try r.item(items, id)).claim.content;
                if (original != .model or std.meta.activeTag(original.model) != std.meta.activeTag(model)) return error.InvalidReferenceReconciliation;
            }
            const context_set = try scopes(allocator, items, ids, context);
            return .{ .model = switch (model) {
                inline .business, .scope_guard => |value, tag| @unionInit(r.extraction.Content, @tagName(tag), try validator.businessIn(allocator, context_set, value)),
                inline else => |value, tag| @unionInit(r.extraction.Content, @tagName(tag), try validator.referenceIn(allocator, context_set, value)),
            } };
        },
        .preserved_token => |token| {
            // A summary or signal names exactly the supplied token, not a new
            // scalar or a different token with coincidentally equal bytes.
            if (ids.len != 1) return error.InvalidReferenceReconciliation;
            const original = (try r.item(items, ids[0])).claim.content;
            if (original != .preserved_token or original.preserved_token.value.id.ordinal != token.token_id.ordinal) return error.InvalidReferenceReconciliation;
            return .{ .preserved_token = token };
        },
    }
}
pub fn citations(allocator: std.mem.Allocator, items: r.Items, ids: []const r.ClaimId, proposed: []const r.CitationId) r.Error!void {
    var expected: std.ArrayList(r.CitationId) = .empty;
    for (ids) |id| for ((try r.item(items, id)).claim.citation_ids) |citation| {
        if (!r.contains(r.CitationId, expected.items, citation)) try expected.append(allocator, citation);
    };
    try r.sameSet(r.CitationId, expected.items, proposed);
}
pub fn disposition(values: []const r.ClaimDisposition, id: r.ClaimId) r.Error!r.ClaimDisposition {
    for (values) |value| if (value.claim_id.ordinal == id.ordinal) return value;
    return error.InvalidReferenceReconciliation;
}

/// Replay-independent final lineage gate. Every statement represents original
/// claims exactly once; no model-supplied membership can shrink the next input.
pub fn history(allocator: std.mem.Allocator, progress: r.Progress) r.Error!void {
    try @import("reference_reconciliation_partition.zig").validate(allocator, progress.plan);
    if (progress.summary_count + 1 != progress.plan.partitions.len) return error.InvalidReferenceReconciliation;
    var next_statement = progress.next_statement_ordinal;
    var remaining = progress.summary_count;
    var history_node = progress.latest;
    while (remaining != 0) {
        const node = history_node orelse return error.InvalidReferenceReconciliation;
        const summary = node.value;
        const partition = progress.plan.partitions[remaining - 1];
        if (summary.id.ordinal != remaining or summary.partition_id.ordinal != partition.id.ordinal or summary.statements.len >= next_statement) return error.InvalidReferenceReconciliation;
        next_statement -= @intCast(summary.statements.len);
        try r.sameSet(r.ClaimId, partition.group.claim_ids, summary.member_claim_ids);
        if (partition.group.children.len != summary.member_summary_ids.len) return error.InvalidReferenceReconciliation;
        for (partition.group.children, summary.member_summary_ids) |child, id| {
            // These earlier records are checked by this same complete walk;
            // no canonical summary IDs are allocated by partition planning.
            if (id.ordinal != child.value + 1) return error.InvalidReferenceReconciliation;
        }
        var represented: std.ArrayList(r.ClaimId) = .empty;
        for (summary.statements, 0..) |statement, index| {
            if (statement.id.ordinal != next_statement + index or statement.claim_ids.len == 0) return error.InvalidReferenceReconciliation;
            try represented.appendSlice(allocator, statement.claim_ids);
        }
        try r.sameSet(r.ClaimId, represented.items, summary.member_claim_ids);
        remaining -= 1;
        history_node = node.previous;
    }
    if (next_statement != 1 or history_node != null) return error.InvalidReferenceReconciliation;
}
