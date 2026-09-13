//! Shared joins and scoped text checks for summaries, signals and conflicts.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const d = r.diagnostic;
pub const TextContext = struct { registry: @import("passive_literals.zig").Registry, current: *const @import("toolchain_safety.zig").ValidToolchain, inputs: r.evidence.Inputs };

pub fn bind(allocator: std.mem.Allocator, items: r.Items, context: TextContext, validator: r.text.Validator) r.Error!void {
    if (!items.state_id.eql(context.inputs.corpus.state_id)) return error.InvalidReferenceReconciliation;
    for (items.entries) |entry| _ = try r.evidence.resolve(context.inputs, .{ .state_id = items.state_id, .chunk_id = entry.claim.chunk_id });
    try @import("path_token_grammar.zig").validateBinding(allocator, context.registry.grammar, context.current, context.inputs, validator.normalizer, validator.folder);
}

pub fn claims(items: r.Items, ids: []const r.ClaimId, allowed: []const r.ClaimId) ?d.Issue {
    const failure: d.Issue = .{ .rule = .claim_selection, .observed = .{ .claims = ids }, .expected = .{ .claims = allowed } };
    if (ids.len == 0) return failure;
    r.unique(r.ClaimId, ids) catch return failure;
    for (ids) |id| {
        _ = r.item(items, id) catch return failure;
        if (!r.contains(r.ClaimId, allowed, id)) return failure;
    }
    return null;
}
pub fn scopes(allocator: std.mem.Allocator, items: r.Items, ids: []const r.ClaimId, context: TextContext) r.Error!r.text.ScopeSetContext {
    const result = try allocator.alloc(r.evidence.Scope, ids.len);
    if (!items.state_id.eql(context.inputs.corpus.state_id)) return error.InvalidReferenceReconciliation;
    for (ids, result) |id, *scope| scope.* = .{ .state_id = items.state_id, .chunk_id = (try r.item(items, id)).claim.chunk_id };
    return .{ .registry = context.registry, .current = context.current, .inputs = context.inputs, .scopes = result };
}
pub fn content(allocator: std.mem.Allocator, validator: r.text.Validator, context: TextContext, items: r.Items, ids: []const r.ClaimId, candidate: r.ContentProposal) r.Error!d.Check(r.Content) {
    const mismatch: d.Check(r.Content) = .{ .invalid = .{ .rule = .content, .observed = .{ .content = candidate }, .expected = .{ .constraint = .matching_claim_content } } };
    if (ids.len == 0) return mismatch;
    switch (candidate) {
        .model => |model| {
            for (ids) |id| {
                const original = (try r.item(items, id)).claim.content;
                if (original != .model or std.meta.activeTag(original.model) != std.meta.activeTag(model)) return mismatch;
            }
            const context_set = try scopes(allocator, items, ids, context);
            return .{ .valid = .{ .model = switch (model) {
                inline .business, .scope_guard => |value, tag| @unionInit(r.extraction.Content, @tagName(tag), switch (try validator.checkBusinessIn(allocator, context_set, value)) {
                    .valid => |checked| checked,
                    .invalid => |issue| return .{ .invalid = d.textFailure(issue, .{ .content = candidate }) },
                }),
                inline else => |value, tag| @unionInit(r.extraction.Content, @tagName(tag), switch (try validator.checkReferenceIn(allocator, context_set, value)) {
                    .valid => |checked| checked,
                    .invalid => |issue| return .{ .invalid = d.textFailure(issue, .{ .content = candidate }) },
                }),
            } } };
        },
        .preserved_token => |token| {
            // A summary or signal names exactly the supplied token, not a new
            // scalar or a different token with coincidentally equal bytes.
            if (ids.len != 1) return mismatch;
            const original = (try r.item(items, ids[0])).claim.content;
            if (original != .preserved_token or original.preserved_token.value.id.ordinal != token.token_id.ordinal) return .{ .invalid = .{ .rule = .content, .observed = .{ .content = candidate }, .expected = .{ .constraint = .exact_selected_token } } };
            return .{ .valid = .{ .preserved_token = token } };
        },
    }
}
pub fn disposition(values: []const r.ClaimDisposition, id: r.ClaimId) r.Error!r.ClaimDisposition {
    for (values) |value| if (value.claim_id.ordinal == id.ordinal) return value;
    return error.InvalidReferenceReconciliation;
}

/// Replay-independent final lineage gate. Every statement represents original
/// claims exactly once; no model-supplied membership can shrink the next input.
pub fn history(allocator: std.mem.Allocator, progress: r.Progress) r.Error!void {
    if (progress.summary_count + 1 != progress.plan.partitions.len) return error.InvalidReferenceReconciliation;
    try historyPrefix(allocator, progress);
}

fn historyPrefix(allocator: std.mem.Allocator, progress: r.Progress) r.Error!void {
    try @import("reference_reconciliation_partition.zig").validate(allocator, progress.plan);
    if (progress.summary_count >= progress.plan.partitions.len) return error.InvalidReferenceReconciliation;
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

/// Revalidate engine-owned partition/history before attributing a candidate defect.
pub fn input(allocator: std.mem.Allocator, current: r.Input) r.Error!void {
    try historyPrefix(allocator, current.progress);
    const expected = current.progress.plan.partitions[current.progress.summary_count];
    if (current.partition.id.ordinal != expected.id.ordinal or current.partition.group.level != expected.group.level or current.partition.group.round != expected.group.round or current.purpose != (if (current.progress.summary_count + 1 == current.progress.plan.partitions.len) @FieldType(r.Input, "purpose").global else .summary)) return error.InvalidReferenceReconciliation;
    try r.sameSet(r.ClaimId, current.partition.group.claim_ids, expected.group.claim_ids);
    if (current.partition.group.children.len != expected.group.children.len) return error.InvalidReferenceReconciliation;
    for (current.partition.group.children, expected.group.children) |actual, child| if (actual.value != child.value) return error.InvalidReferenceReconciliation;
    if (current.member_summary_ids.len != expected.group.children.len or current.summaries.len != expected.group.children.len or current.items.len != expected.group.claim_ids.len) return error.InvalidReferenceReconciliation;
    for (expected.group.children, current.member_summary_ids, current.summaries) |child, id, summary| {
        if (id.ordinal != child.value + 1 or summary.id.ordinal != id.ordinal) return error.InvalidReferenceReconciliation;
    }
    for (current.items, expected.group.claim_ids) |item, id| if (item.claim.id.ordinal != id.ordinal) return error.InvalidReferenceReconciliation;
}
