//! Native disposition membership, relationship and graph validation.
//! Redundancy preserves the same claim, variant and validated edge set.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const v = @import("reference_reconciliation_validation.zig");
const d = r.diagnostic;

pub fn validate(allocator: std.mem.Allocator, parsed: r.Parsed) r.Error!d.Result(r.CheckedDispositions) {
    const supplied = try allocator.alloc(r.ClaimDisposition, parsed.proposal.global.claim_dispositions.len);
    for (parsed.proposal.global.claim_dispositions, supplied) |proposal, *value| value.* = try proposal.canonical(allocator);
    return switch (try check(allocator, parsed.input.progress.plan.layout.items, supplied)) {
        .valid => |values| .{ .valid = .{ .source = parsed.source, .input = parsed.input, .proposal = parsed.proposal.global, .dispositions = values } },
        .invalid => |rejection| d.reject(r.CheckedDispositions, parsed.input, parsed.source, rejection.unit, rejection.issue),
    };
}

pub const Result = union(enum) { valid: []const r.ClaimDisposition, invalid: d.RecordIssue };

/// Canonical record validation, independent of live candidate/history wrappers.
pub fn check(allocator: std.mem.Allocator, items: r.Items, supplied: []const r.ClaimDisposition) r.Error!Result {
    if (supplied.len != items.entries.len) return .{ .invalid = .{ .unit = .dispositions, .issue = .{ .rule = .cardinality, .observed = .{ .count = supplied.len }, .expected = .{ .count = items.entries.len } } } };
    const dispositions = try allocator.alloc(r.ClaimDisposition, supplied.len);
    const seen = try allocator.alloc(bool, supplied.len);
    @memset(seen, false);
    for (supplied, 0..) |value, position| {
        _ = r.item(items, value.claim_id) catch return failure(position, .claim_selection, value, .nonempty_unique_allowed_claims);
        const index = value.claim_id.ordinal - 1;
        if (seen[index]) return failure(position, .duplicate_disposition, value, .unique_nonzero);
        seen[index] = true;
        if (record(items, value)) |rejection| return .{ .invalid = .{ .unit = .{ .disposition = position }, .issue = rejection } };
        dispositions[index] = value;
    }
    for (supplied, 0..) |proposal, position| {
        const value = dispositions[proposal.claim_id.ordinal - 1];
        for (value.related_claim_ids) |id| {
            const target = dispositions[id.ordinal - 1];
            switch (value.disposition) {
                .retained => unreachable,
                .duplicate, .superseded => if (target.disposition == .conflicting) return failure(position, .relationship, value, .nonconflicting_target),
                .conflicting => if (target.disposition != .conflicting or !r.contains(r.ClaimId, target.related_claim_ids, value.claim_id)) return failure(position, .relationship, value, .reciprocal_conflict),
            }
        }
    }
    if (try cycle(allocator, dispositions)) |index| {
        for (supplied, 0..) |value, position| if (value.claim_id.ordinal == dispositions[index].claim_id.ordinal) return failure(position, .cycle, dispositions[index], .acyclic);
        return error.InvalidReferenceReconciliation;
    }
    return .{ .valid = dispositions };
}

fn record(items: r.Items, value: r.ClaimDisposition) ?d.Issue {
    const original = r.item(items, value.claim_id) catch return issue(.claim_selection, value, .nonempty_unique_allowed_claims);
    r.unique(r.ClaimId, value.related_claim_ids) catch return issue(.relationship, value, .unique_nonzero);
    for (value.related_claim_ids) |related| {
        const target = r.item(items, related) catch return issue(.claim_selection, value, .nonempty_unique_allowed_claims);
        if (related.ordinal == value.claim_id.ordinal) return issue(.relationship, value, .no_self_relation);
        if (value.disposition == .duplicate or value.disposition == .superseded) {
            if (std.meta.activeTag(original.claim.content) != std.meta.activeTag(target.claim.content)) return issue(.relationship, value, .same_content_kind);
            switch (original.claim.content) {
                .model => |model| if (std.meta.activeTag(model) != std.meta.activeTag(target.claim.content.model)) return issue(.relationship, value, .same_content_kind),
                .preserved_token => |token| if (value.disposition == .duplicate and
                    (token.value.kind != target.claim.content.preserved_token.value.kind or !std.mem.eql(u8, token.value.raw_value.bytes, target.claim.content.preserved_token.value.raw_value.bytes))) return issue(.relationship, value, .same_token_value),
            }
        }
    }
    switch (value.disposition) {
        .retained, .duplicate => {
            const expected: usize = if (value.disposition == .retained) 0 else 1;
            if (value.related_claim_ids.len != expected) return .{ .rule = .cardinality, .observed = .{ .disposition = value }, .expected = .{ .count = expected } };
        },
        .superseded, .conflicting => if (value.related_claim_ids.len == 0) return issue(.cardinality, value, .nonempty),
    }
    return null;
}

/// No survivor meaning is selected: both occurrences must express the same
/// locally valid edges. Deletion leaves graph, signal and conflict obligations
/// unchanged; their complete validation still follows the merge.
pub fn redundancy(allocator: std.mem.Allocator, parsed: r.Parsed) r.Error!d.Relations {
    const values = parsed.proposal.global.claim_dispositions;
    const items = parsed.input.progress.plan.layout.items;
    for (values, 0..) |value, index| for (values[0..index]) |prior| {
        if (prior.claim_id.ordinal != value.claim_id.ordinal) continue;
        const left = try prior.canonical(allocator);
        const right = try value.canonical(allocator);
        if (record(items, left) == null and record(items, right) == null and left.disposition == right.disposition and v.sameMembers(left.related_claim_ids, right.related_claim_ids)) return .{ .redundant = index };
        return .{ .competing = true };
    };
    return .{};
}

fn issue(rule: d.Rule, actual: r.ClaimDisposition, expected: d.Constraint) d.Issue {
    return .{ .rule = rule, .observed = .{ .disposition = actual }, .expected = .{ .constraint = expected } };
}

/// Iterative graph proof: duplicate/supersession chains must terminate at
/// retained claims. Conflict relationships are symmetric, not directed edges.
fn cycle(allocator: std.mem.Allocator, values: []const r.ClaimDisposition) r.Error!?usize {
    const Mark = enum { unseen, active, done };
    const marks = try allocator.alloc(Mark, values.len);
    @memset(marks, .unseen);
    const Frame = struct { index: usize, edge: usize };
    var stack: std.ArrayList(Frame) = .empty;
    for (values, 0..) |value, root| {
        if (marks[root] == .done or value.disposition == .conflicting) continue;
        try stack.append(allocator, .{ .index = root, .edge = 0 });
        marks[root] = .active;
        while (stack.items.len != 0) {
            const frame = &stack.items[stack.items.len - 1];
            const edges = values[frame.index].related_claim_ids;
            if (frame.edge == edges.len) {
                marks[frame.index] = .done;
                _ = stack.pop();
                continue;
            }
            const target = edges[frame.edge].ordinal - 1;
            frame.edge += 1;
            switch (marks[target]) {
                .active => return frame.index,
                .done => {},
                .unseen => {
                    marks[target] = .active;
                    try stack.append(allocator, .{ .index = target, .edge = 0 });
                },
            }
        }
    }
    return null;
}

fn failure(index: usize, rule: d.Rule, actual: r.ClaimDisposition, expected: d.Constraint) Result {
    return .{ .invalid = .{ .unit = .{ .disposition = index }, .issue = issue(rule, actual, expected) } };
}
