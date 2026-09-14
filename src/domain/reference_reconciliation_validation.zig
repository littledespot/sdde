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
pub fn contentKind(value: r.ContentProposal) d.ContentKind {
    return switch (value) {
        .model => |model| .{ .model = model },
        .preserved_token => |token| .{ .preserved_token = token },
    };
}
fn claimKind(value: r.Item) d.ContentKind {
    return switch (value.claim.content) {
        .model => |model| .{ .model = model },
        .preserved_token => |token| .{ .preserved_token = .{ .token_id = token.value.id } },
    };
}
fn matchingKind(left: d.ContentKind, right: d.ContentKind) bool {
    return std.meta.eql(left, right);
}
/// All selected claims must admit one content value. Exact tokens are indivisible.
fn selectedKind(items: r.Items, ids: []const r.ClaimId) r.Error!?d.ContentKind {
    if (ids.len == 0) return null;
    const first = claimKind(try r.item(items, ids[0]));
    if (first == .preserved_token and ids.len != 1) return null;
    for (ids[1..]) |id| if (!matchingKind(first, claimKind(try r.item(items, id)))) return null;
    return first;
}

pub fn content(allocator: std.mem.Allocator, validator: r.text.Validator, context: TextContext, items: r.Items, ids: []const r.ClaimId, candidate: r.ContentProposal) r.Error!d.Check(r.Content) {
    const mismatch: d.Check(r.Content) = .{ .invalid = .{ .rule = .content, .observed = .{ .content = candidate }, .expected = .{ .constraint = .matching_claim_content } } };
    const required = (try selectedKind(items, ids)) orelse return mismatch;
    if (!matchingKind(required, contentKind(candidate))) return if (required == .preserved_token and candidate == .preserved_token)
        .{ .invalid = .{ .rule = .content, .observed = .{ .content = candidate }, .expected = .{ .constraint = .exact_selected_token } } }
    else
        mismatch;
    switch (candidate) {
        .model => |model| {
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
            return .{ .valid = .{ .preserved_token = token } };
        },
    }
}
pub fn disposition(values: []const r.ClaimDisposition, id: r.ClaimId) r.Error!r.ClaimDisposition {
    for (values) |value| if (value.claim_id.ordinal == id.ordinal) return value;
    return error.InvalidReferenceReconciliation;
}

pub fn signalEligible(values: []const r.ClaimDisposition, id: r.ClaimId) r.Error!bool {
    return (try disposition(values, id)).disposition != .conflicting;
}
pub fn conflictRelated(values: []const r.ClaimDisposition, left: r.ClaimId, right: r.ClaimId) r.Error!bool {
    const value = try disposition(values, left);
    return value.disposition == .conflicting and left.ordinal != right.ordinal and r.contains(r.ClaimId, value.related_claim_ids, right);
}
pub fn sameMembers(left: []const r.ClaimId, right: []const r.ClaimId) bool {
    r.sameSet(r.ClaimId, left, right) catch return false;
    return true;
}

/// Retain compatibility and canonical redundancy while native validation owns
/// the candidate. Authorizers need no second interpretation of these relations.
pub fn relations(a: std.mem.Allocator, validator: r.text.Validator, ctx: TextContext, parsed: r.Parsed, dispositions: []const r.ClaimDisposition, rejection: d.Rejection) r.Error!d.Relations {
    const items = parsed.input.progress.plan.layout.items;
    var result: d.Relations = .{};
    var selections: std.ArrayList(r.ClaimId) = .empty;
    const selected: ?r.SignalProposal = switch (rejection.unit) {
        .statement => |index| .{ .claim_ids = parsed.proposal.summary.statements[index].claim_ids, .content = parsed.proposal.summary.statements[index].content },
        .signal => |index| parsed.proposal.global.signals[index],
        else => null,
    };
    if (selected) |value| {
        var eligible_current = claims(items, value.claim_ids, parsed.input.partition.group.claim_ids) == null;
        if (eligible_current and rejection.unit == .signal) for (value.claim_ids) |id| {
            if (!try signalEligible(dispositions, id)) eligible_current = false;
        };
        if (eligible_current) result.content = try selectedKind(items, value.claim_ids);
        for (parsed.input.partition.group.claim_ids) |id| {
            if (rejection.unit == .signal and !try signalEligible(dispositions, id)) continue;
            if (matchingKind(contentKind(value.content), claimKind(try r.item(items, id)))) try selections.append(a, id);
        }
        result.selection = try selections.toOwnedSlice(a);
    }
    switch (rejection.unit) {
        .summary, .statement => {
            const values = parsed.proposal.summary.statements;
            for (values, 0..) |value, index| {
                if (rejection.unit == .statement and rejection.unit.statement != index) continue;
                for (values[0..index]) |prior| {
                    if (try equivalentContent(a, validator, ctx, items, prior.claim_ids, prior.content, value.claim_ids, value.content)) {
                        result.redundant = index;
                        return result;
                    }
                    if (rejection.unit == .summary) for (value.claim_ids) |id| {
                        if (r.contains(r.ClaimId, prior.claim_ids, id)) result.competing = true;
                    };
                }
            }
        },
        .signal => |index| if (rejection.issue.rule == .duplicate_signal) {
            const value = parsed.proposal.global.signals[index];
            for (parsed.proposal.global.signals[0..index]) |prior| {
                if (try equivalentContent(a, validator, ctx, items, prior.claim_ids, prior.content, value.claim_ids, value.content)) {
                    result.redundant = index;
                    break;
                }
            }
        },
        .conflict => |index| {
            var pairs: std.ArrayList(std.meta.Child(@FieldType(d.Relations, "conflicting_pairs"))) = .empty;
            // Traverse declared edges, never subsets, cliques or repair sequences.
            for (dispositions) |left| for (left.related_claim_ids) |right| {
                if (left.claim_id.ordinal < right.ordinal and try conflictRelated(dispositions, left.claim_id, right) and try conflictRelated(dispositions, right, left.claim_id)) try pairs.append(a, .{ .left = left.claim_id, .right = right });
            };
            result.conflicting_pairs = try pairs.toOwnedSlice(a);
            if (rejection.issue.rule == .duplicate_conflict) {
                const value = parsed.proposal.global.conflicts[index];
                for (parsed.proposal.global.conflicts[0..index]) |prior| {
                    if (prior.kind != value.kind or !sameMembers(prior.claim_ids, value.claim_ids)) continue;
                    const scope = try scopes(a, items, value.claim_ids, ctx);
                    const left = switch (try validator.checkReferenceIn(a, scope, prior.summary)) {
                        .valid => |checked| checked,
                        .invalid => continue,
                    };
                    const right = switch (try validator.checkReferenceIn(a, scope, value.summary)) {
                        .valid => |checked| checked,
                        .invalid => continue,
                    };
                    if (r.text.equivalentReference(left, right)) {
                        result.redundant = index;
                        break;
                    }
                }
            }
        },
        else => {},
    }
    return result;
}
fn equivalentContent(a: std.mem.Allocator, validator: r.text.Validator, ctx: TextContext, items: r.Items, left_ids: []const r.ClaimId, left: r.ContentProposal, right_ids: []const r.ClaimId, right: r.ContentProposal) r.Error!bool {
    if (!sameMembers(left_ids, right_ids) or claims(items, left_ids, left_ids) != null) return false;
    const first = switch (try content(a, validator, ctx, items, left_ids, left)) {
        .valid => |value| value,
        .invalid => return false,
    };
    const second = switch (try content(a, validator, ctx, items, right_ids, right)) {
        .valid => |value| value,
        .invalid => return false,
    };
    // Exact comparison occurs only after canonical text validation. The same
    // claim set proves identical evidence and token/coverage obligations.
    return r.equivalentContent(first, second);
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
