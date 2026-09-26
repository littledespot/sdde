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
pub fn selectedKind(items: r.Items, ids: []const r.ClaimId) r.Error!?d.ContentKind {
    if (ids.len == 0) return null;
    const first = claimKind(try r.item(items, ids[0]));
    if (first == .preserved_token and ids.len != 1) return null;
    for (ids[1..]) |id| if (!matchingKind(first, claimKind(try r.item(items, id)))) return null;
    return first;
}

pub fn contentIssue(items: r.Items, ids: []const r.ClaimId, candidate: r.ContentProposal) r.Error!?d.Issue {
    const mismatch: d.Issue = .{ .rule = .content, .observed = .{ .content = candidate }, .expected = .{ .constraint = .matching_claim_content } };
    const required = (try selectedKind(items, ids)) orelse return mismatch;
    if (!matchingKind(required, contentKind(candidate))) return if (required == .preserved_token and candidate == .preserved_token)
        .{ .rule = .content, .observed = .{ .content = candidate }, .expected = .{ .constraint = .exact_selected_token } }
    else
        mismatch;
    return null;
}

pub fn content(allocator: std.mem.Allocator, validator: r.text.Validator, context: TextContext, items: r.Items, ids: []const r.ClaimId, candidate: r.ContentProposal) r.Error!d.Check(r.Content) {
    if (try contentIssue(items, ids, candidate)) |issue| return .{ .invalid = issue };
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

pub fn checkStatement(a: std.mem.Allocator, validator: r.text.Validator, context: TextContext, current: r.Input, values: []const r.StatementProposal, index: usize) r.Error!d.Check(r.ValidatedStatement) {
    if (index >= values.len) return error.InvalidReferenceReconciliation;
    const proposed = values[index];
    if (statementKey(values, index)) |issue| return .{ .invalid = issue };
    const items = current.progress.plan.layout.items;
    if (claims(items, proposed.claim_ids, current.partition.group.claim_ids)) |issue| return .{ .invalid = issue };
    return switch (try content(a, validator, context, items, proposed.claim_ids, proposed.content)) {
        .valid => |accepted| .{ .valid = .{ .local_key = proposed.local_key, .claim_ids = proposed.claim_ids, .content = accepted } },
        .invalid => |issue| .{ .invalid = issue },
    };
}

pub fn statementKey(values: []const r.StatementProposal, index: usize) ?d.Issue {
    const proposed = values[index];
    const issue: d.Issue = .{ .rule = .local_key, .observed = .{ .count = proposed.local_key }, .expected = .{ .constraint = .unique_nonzero } };
    if (proposed.local_key == 0) return issue;
    for (values[0..index]) |prior| if (prior.local_key == proposed.local_key) return issue;
    return null;
}

pub fn checkSignal(a: std.mem.Allocator, validator: r.text.Validator, context: TextContext, prior: r.CheckedDispositions, index: usize) r.Error!d.Check(r.ValidatedSignal) {
    if (index >= prior.proposal.signals.len) return error.InvalidReferenceReconciliation;
    const proposed = prior.proposal.signals[index];
    const items = prior.input.progress.plan.layout.items;
    if (try signalClaims(items, prior.dispositions, proposed.claim_ids, prior.input.partition.group.claim_ids)) |issue| return .{ .invalid = issue };
    const accepted = switch (try content(a, validator, context, items, proposed.claim_ids, proposed.content)) {
        .valid => |value| value,
        .invalid => |issue| return .{ .invalid = issue },
    };
    if (!signalSelectionAvailable(prior.proposal.signals[0..index], index, proposed.claim_ids)) return .{ .invalid = .{ .rule = .duplicate_signal, .observed = .{ .claims = proposed.claim_ids }, .expected = .{ .constraint = .unique_members } } };
    return .{ .valid = .{ .claim_ids = proposed.claim_ids, .citation_ids = try r.citationUnion(a, items, proposed.claim_ids), .content = accepted } };
}

pub fn checkConflict(a: std.mem.Allocator, validator: r.text.Validator, context: TextContext, prior: r.CheckedDispositions, index: usize) r.Error!d.Check(r.ValidatedConflict) {
    if (index >= prior.proposal.conflicts.len) return error.InvalidReferenceReconciliation;
    const proposed = prior.proposal.conflicts[index];
    const items = prior.input.progress.plan.layout.items;
    if (try conflictClaims(items, prior.dispositions, proposed.claim_ids, prior.input.partition.group.claim_ids)) |issue| return .{ .invalid = issue };
    if (!conflictSelectionAvailable(prior.proposal.conflicts[0..index], index, proposed.kind, proposed.claim_ids)) return .{ .invalid = .{ .rule = .duplicate_conflict, .observed = .{ .claims = proposed.claim_ids }, .expected = .{ .constraint = .unique_members } } };
    const summary = switch (try conflictSummary(a, validator, context, items, proposed.claim_ids, proposed.summary)) {
        .valid => |checked| checked,
        .invalid => |issue| return .{ .invalid = issue },
    };
    return .{ .valid = .{ .claim_ids = proposed.claim_ids, .citation_ids = try r.citationUnion(a, items, proposed.claim_ids), .kind = proposed.kind, .summary = summary, .resolution = .unresolved } };
}

pub fn conflictSummary(a: std.mem.Allocator, validator: r.text.Validator, context: TextContext, items: r.Items, claims_selected: []const r.ClaimId, summary: r.text.ReferenceSemanticText) r.Error!d.Check(r.text.ValidatedReferenceSemanticText) {
    return switch (try validator.checkReferenceIn(a, try scopes(a, items, claims_selected, context), summary)) {
        .valid => |checked| .{ .valid = checked },
        .invalid => |issue| .{ .invalid = d.textFailure(issue, .{ .text = summary }) },
    };
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

pub fn signalClaims(items: r.Items, dispositions: []const r.ClaimDisposition, ids: []const r.ClaimId, allowed: []const r.ClaimId) r.Error!?d.Issue {
    if (claims(items, ids, allowed)) |issue| return issue;
    for (ids) |id| if (!try signalEligible(dispositions, id)) return .{ .rule = .relationship, .observed = .{ .claims = ids }, .expected = .{ .constraint = .nonconflicting_claims } };
    return null;
}

pub fn conflictClaims(items: r.Items, dispositions: []const r.ClaimDisposition, ids: []const r.ClaimId, allowed: []const r.ClaimId) r.Error!?d.Issue {
    if (ids.len < 2) return .{ .rule = .cardinality, .observed = .{ .count = ids.len }, .expected = .{ .constraint = .at_least_two } };
    if (claims(items, ids, allowed)) |issue| return issue;
    for (ids) |id| {
        if ((try disposition(dispositions, id)).disposition != .conflicting) return .{ .rule = .relationship, .observed = .{ .claims = ids }, .expected = .{ .constraint = .conflicting_related_claims } };
        for (ids) |other| if (other.ordinal != id.ordinal and !try conflictRelated(dispositions, id, other)) return .{ .rule = .relationship, .observed = .{ .claims = ids }, .expected = .{ .constraint = .conflicting_related_claims } };
    }
    return null;
}

pub fn signalCoverage(a: std.mem.Allocator, items: r.Items, dispositions: []const r.ClaimDisposition, signals: []const r.SignalProposal) r.Error!?d.Issue {
    const covered = try a.alloc(bool, items.entries.len);
    defer a.free(covered);
    @memset(covered, false);
    const token_covered = try a.alloc(bool, items.entries.len);
    defer a.free(token_covered);
    @memset(token_covered, false);
    for (signals) |signal| for (signal.claim_ids) |id| {
        _ = try r.item(items, id);
        covered[id.ordinal - 1] = true;
        if (signal.content == .preserved_token) token_covered[id.ordinal - 1] = true;
    };
    for (dispositions, items.entries, covered, token_covered) |value, item, present, token_present| {
        if (signalCoverageIssue(value, item, present, token_present)) |issue| return issue;
    }
    return null;
}

fn signalCoverageIssue(value: r.ClaimDisposition, item: r.Item, present: bool, token_present: bool) ?d.Issue {
    if (value.disposition == .retained and !present) return .{ .rule = .signal_coverage, .observed = .{ .disposition = value }, .expected = .{ .constraint = .retained_claim_covered } };
    if (item.claim.content == .preserved_token and value.disposition != .conflicting and !token_present) return .{ .rule = .signal_coverage, .observed = .{ .disposition = value }, .expected = .{ .constraint = .token_projected } };
    return null;
}

pub fn selectedSignalCoverage(items: r.Items, dispositions: []const r.ClaimDisposition, signal: r.SignalProposal, claim: r.ClaimId) r.Error!?d.Issue {
    const present = r.contains(r.ClaimId, signal.claim_ids, claim);
    return signalCoverageIssue(try disposition(dispositions, claim), try r.item(items, claim), present, present and signal.content == .preserved_token);
}

pub fn conflictCoverage(a: std.mem.Allocator, items: r.Items, dispositions: []const r.ClaimDisposition, conflicts: []const r.ConflictProposal) r.Error!?d.Issue {
    const covered = try a.alloc(bool, items.entries.len);
    defer a.free(covered);
    @memset(covered, false);
    for (conflicts) |conflict| for (conflict.claim_ids) |id| {
        _ = try r.item(items, id);
        covered[id.ordinal - 1] = true;
    };
    for (dispositions, covered) |value, present| {
        if ((value.disposition == .conflicting) != present) return .{ .rule = .conflict_coverage, .observed = .{ .disposition = value }, .expected = .{ .constraint = .conflict_claim_covered } };
        if (!present) continue;
        for (value.related_claim_ids) |related| {
            for (conflicts) |conflict| {
                if (r.contains(r.ClaimId, conflict.claim_ids, value.claim_id) and r.contains(r.ClaimId, conflict.claim_ids, related)) break;
            } else return .{ .rule = .conflict_coverage, .observed = .{ .disposition = value }, .expected = .{ .constraint = .conflict_pair_covered } };
        }
    }
    return null;
}
pub fn sameMembers(left: []const r.ClaimId, right: []const r.ClaimId) bool {
    r.sameSet(r.ClaimId, left, right) catch return false;
    return true;
}

fn summarySelectionAvailable(values: []const r.StatementProposal, selected: usize, ids: []const r.ClaimId) bool {
    for (values, 0..) |sibling, index| {
        if (index == selected) continue;
        for (ids) |id| if (r.contains(r.ClaimId, sibling.claim_ids, id)) return false;
    }
    return true;
}

pub fn signalSelectionAvailable(values: []const r.SignalProposal, selected: usize, ids: []const r.ClaimId) bool {
    for (values, 0..) |sibling, index| {
        if (index != selected and sameMembers(sibling.claim_ids, ids)) return false;
    }
    return true;
}

pub fn conflictSelectionAvailable(values: []const r.ConflictProposal, selected: usize, kind: r.ConflictKind, ids: []const r.ClaimId) bool {
    for (values, 0..) |sibling, index| {
        if (index != selected and sibling.kind == kind and sameMembers(sibling.claim_ids, ids)) return false;
    }
    return true;
}

/// Count occupied sets, not occupied IDs: overlapping signals remain legal.
/// Saturating cardinality avoids enumerating subsets or selecting model content.
fn signalSelectionExists(items: r.Items, values: []const r.SignalProposal, selected: usize, allowed: []const r.ClaimId) bool {
    var possible: usize = 0;
    for (allowed) |_| {
        possible = possible *| 2 +| 1;
        if (possible > values.len) return true;
    }
    var occupied: usize = 0;
    for (values, 0..) |sibling, index| {
        if (index == selected or claims(items, sibling.claim_ids, allowed) != null) continue;
        // Count each set once even when another candidate entry is invalid.
        if (!signalSelectionAvailable(values[0..index], selected, sibling.claim_ids)) continue;
        occupied += 1;
    }
    return possible > occupied;
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
        eligible_current = eligible_current and switch (rejection.unit) {
            .statement => |index| summarySelectionAvailable(parsed.proposal.summary.statements, index, value.claim_ids),
            .signal => |index| signalSelectionAvailable(parsed.proposal.global.signals, index, value.claim_ids),
            else => unreachable,
        };
        if (eligible_current) result.content = try selectedKind(items, value.claim_ids);
        for (parsed.input.partition.group.claim_ids) |id| {
            if (rejection.unit == .signal and !try signalEligible(dispositions, id)) continue;
            if (rejection.unit == .statement and !summarySelectionAvailable(parsed.proposal.summary.statements, rejection.unit.statement, &.{id})) continue;
            if (matchingKind(contentKind(value.content), claimKind(try r.item(items, id)))) try selections.append(a, id);
        }
        result.selection = try selections.toOwnedSlice(a);
        if (rejection.unit == .signal and !signalSelectionExists(items, parsed.proposal.global.signals, rejection.unit.signal, result.selection)) {
            a.free(result.selection);
            result.selection = &.{};
        }
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
                if (rejection.unit == .summary and try removableProjection(a, validator, ctx, parsed, dispositions, .{ .statement = index })) {
                    result.redundant = index;
                    return result;
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
                if (left.claim_id.ordinal < right.ordinal and try conflictRelated(dispositions, left.claim_id, right) and try conflictRelated(dispositions, right, left.claim_id) and
                    conflictSelectionAvailable(parsed.proposal.global.conflicts, index, parsed.proposal.global.conflicts[index].kind, &.{ left.claim_id, right })) try pairs.append(a, .{ .left = left.claim_id, .right = right });
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
    if (selected != null and result.redundant == null and try removableProjection(a, validator, ctx, parsed, dispositions, rejection.unit)) {
        result.redundant = switch (rejection.unit) {
            .statement => |index| index,
            .signal => |index| index,
            else => unreachable,
        };
    }
    return result;
}

/// An incorrectly bound extra projection is removable only when its content and
/// every selected claim survive independently in a fully valid collection.
/// This proof chooses no replacement content or evidence; merge still validates
/// the exact candidate/dependencies and reruns all dependent validators.
fn removableProjection(allocator: std.mem.Allocator, validator: r.text.Validator, ctx: TextContext, parsed: r.Parsed, dispositions: []const r.ClaimDisposition, unit: d.Unit) r.Error!bool {
    var scratch: std.heap.ArenaAllocator = .init(allocator);
    defer scratch.deinit();
    const a = scratch.allocator();
    const items = parsed.input.progress.plan.layout.items;
    const selected: r.SignalProposal = switch (unit) {
        .statement => |index| .{ .claim_ids = parsed.proposal.summary.statements[index].claim_ids, .content = parsed.proposal.summary.statements[index].content },
        .signal => |index| parsed.proposal.global.signals[index],
        else => return false,
    };
    if (claims(items, selected.claim_ids, parsed.input.partition.group.claim_ids) != null) return false;
    if (unit == .signal) for (selected.claim_ids) |id| {
        if (!try signalEligible(dispositions, id)) return false;
    };
    var candidate = parsed;
    const remaining: []const r.SignalProposal = switch (unit) {
        .statement => |index| blk: {
            const old = parsed.proposal.summary.statements;
            const values = try a.alloc(r.StatementProposal, old.len - 1);
            @memcpy(values[0..index], old[0..index]);
            @memcpy(values[index..], old[index + 1 ..]);
            candidate.proposal.summary.statements = values;
            const projections = try a.alloc(r.SignalProposal, values.len);
            for (values, projections) |value, *projection| projection.* = .{ .claim_ids = value.claim_ids, .content = value.content };
            break :blk projections;
        },
        .signal => |index| blk: {
            const old = parsed.proposal.global.signals;
            const values = try a.alloc(r.SignalProposal, old.len - 1);
            @memcpy(values[0..index], old[0..index]);
            @memcpy(values[index..], old[index + 1 ..]);
            candidate.proposal.global.signals = values;
            break :blk values;
        },
        else => unreachable,
    };
    for (selected.claim_ids) |id| {
        for (remaining) |value| {
            if (r.contains(r.ClaimId, value.claim_ids, id)) break;
        } else return false;
    }
    for (remaining) |witness| {
        if (try equivalentContent(a, validator, ctx, items, witness.claim_ids, witness.content, witness.claim_ids, selected.content)) break;
    } else return false;
    return switch (unit) {
        .statement => (try checkSummary(a, validator, candidate, ctx)) == .valid,
        .signal => (try checkSignals(a, validator, .{ .source = parsed.source, .input = parsed.input, .proposal = candidate.proposal.global, .dispositions = dispositions }, ctx)) == .valid,
        else => unreachable,
    };
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

pub fn checkSummary(allocator: std.mem.Allocator, validator: r.text.Validator, parsed: r.Parsed, context: TextContext) r.Error!d.Result(r.CheckedSummary) {
    if (parsed.input.purpose != .summary or parsed.proposal != .summary) return error.InvalidReferenceReconciliation;
    try input(allocator, parsed.input);
    if (parsed.source.revision == 0) return error.InvalidReferenceReconciliation;
    try bind(allocator, parsed.input.progress.plan.layout.items, context, validator);
    const proposal = parsed.proposal.summary;
    const statements = try allocator.alloc(r.ValidatedStatement, proposal.statements.len);
    var represented: std.ArrayList(r.ClaimId) = .empty;
    for (proposal.statements, statements, 0..) |statement, *result, index| {
        result.* = switch (try checkStatement(allocator, validator, context, parsed.input, proposal.statements, index)) {
            .valid => |value| value,
            .invalid => |issue| return d.reject(r.CheckedSummary, parsed.input, parsed.source, .{ .statement = index }, issue),
        };
        try represented.appendSlice(allocator, statement.claim_ids);
    }
    r.sameSet(r.ClaimId, represented.items, parsed.input.partition.group.claim_ids) catch return d.reject(r.CheckedSummary, parsed.input, parsed.source, .summary, .{ .rule = .membership, .observed = .{ .claims = represented.items }, .expected = .{ .claims = parsed.input.partition.group.claim_ids } });
    std.mem.sort(r.ValidatedStatement, statements, {}, struct {
        fn less(_: void, a: r.ValidatedStatement, b: r.ValidatedStatement) bool {
            return a.local_key < b.local_key;
        }
    }.less);
    return .{ .valid = .{ .input = parsed.input, .statements = statements } };
}

pub fn checkSignals(allocator: std.mem.Allocator, validator: r.text.Validator, prior: r.CheckedDispositions, context: TextContext) r.Error!d.Result(r.CheckedSignals) {
    const items = prior.input.progress.plan.layout.items;
    try input(allocator, prior.input);
    try bind(allocator, items, context, validator);
    const signals = try allocator.alloc(r.ValidatedSignal, prior.proposal.signals.len);
    for (signals, 0..) |*signal, index| {
        signal.* = switch (try checkSignal(allocator, validator, context, prior, index)) {
            .valid => |value| value,
            .invalid => |issue| return d.reject(r.CheckedSignals, prior.input, prior.source, .{ .signal = index }, issue),
        };
    }
    if (try signalCoverage(allocator, items, prior.dispositions, prior.proposal.signals)) |issue| return d.reject(r.CheckedSignals, prior.input, prior.source, .signals, issue);
    return .{ .valid = .{ .prior = prior, .signals = signals } };
}
