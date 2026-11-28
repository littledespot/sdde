//! The reference reconciliation as the user's answers leave it. A resolved choice among the claims of a conflict makes the
//! chosen claim retained and the others superseded by it, drops the conflict and gives the chosen claim a signal, so the
//! result is an ordinary reconciliation: every reconciliation rule holds for it, the persisted reference snapshot
//! validates, and generation, review, scenarios and rendering read the chosen claim as they read any retained claim. The
//! chosen claims are also recorded (`answer_retained`), since a kept `open_question` claim is decided by the answer. The
//! engine applies the choice; no model reads it and no code judges its prose (ADR 0025).
//!
//! A conflict is answered only when it can be: its claims are model claims of one kind, the claim the answer keeps is in no
//! other conflict, and a claim it supersedes is in another conflict only when that conflict is left with one claim, a
//! model claim in no further conflict. That conflict is dropped too and its last claim retained with a signal of its own.
//! Any other conflict, two answers that touch one conflict, and an answer whose option no claim of the conflict offers
//! any more leave it unresolved, so the form stays protected and its need is raised again.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const refs = @import("reference_support.zig");
const resolution = @import("clarification_resolution.zig");
const model_evidence = @import("model_evidence.zig");
const clarifications = @import("required_authority_clarifications.zig");

pub const Error = std.mem.Allocator.Error || error{InvalidReferenceReconciliation};

/// An answer to one conflict: the claim it keeps, and the other conflicts its supersessions leave with one claim.
const Applied = struct { conflict: usize, chosen: r.ClaimId, dropped: []const usize };

/// The caller's arena owns everything returned and everything allocated on the way, as the reconciliation's builders do.
pub fn apply(allocator: std.mem.Allocator, source_inputs: r.evidence.Inputs, records: r.Records, all: []const resolution.ConflictChoice) Error!r.Records {
    if (all.len == 0 or records.conflicts.len == 0) return records;
    const held = refs.records(.{ .records = records, .outcome = .blocked });
    var candidates: std.ArrayList(Applied) = .empty;
    defer candidates.deinit(allocator);
    // Every conflict the user answered, whether or not that answer can be applied.
    var answered: std.ArrayList(usize) = .empty;
    defer answered.deinit(allocator);
    for (records.conflicts, 0..) |conflict, index| {
        const subject = clarifications.subjectFor(allocator, source_inputs, held, .{ .kind = .reference_meaning, .unit = .{ .conflict = conflict.id }, .slot = .disposition }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceReconciliation;
        const choice = resolution.answerFor(all, subject) orelse continue;
        try answered.append(allocator, index);
        const chosen = (resolution.chosenClaim(allocator, source_inputs.corpus.sources, held, conflict, choice.key, choice.label) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceReconciliation) orelse continue;
        const dropped = (try answerable(allocator, held.items, records.conflicts, conflict, index, chosen)) orelse continue;
        try candidates.append(allocator, .{ .conflict = index, .chosen = chosen, .dropped = dropped });
    }
    // Two answers that touch one conflict apply nothing: neither can account for what the other changes. Nor does an
    // answer that would drop a conflict the user answered too, applicable or not, since that would set the user's own
    // choice there aside unasked.
    var applied: std.ArrayList(Applied) = .empty;
    defer applied.deinit(allocator);
    for (candidates.items, 0..) |entry, at| {
        const clash = for (candidates.items, 0..) |other, other_at| {
            if (other_at != at and touches(entry, other)) break true;
        } else false;
        const overrides = for (entry.dropped) |dropped| {
            if (std.mem.indexOfScalar(usize, answered.items, dropped) != null) break true;
        } else false;
        if (!clash and !overrides) try applied.append(allocator, entry);
    }
    if (applied.items.len == 0) return records;

    const global = records.assignments.global();
    const dispositions = try allocator.dupe(r.ClaimDisposition, global.dispositions);
    const proposed = try allocator.dupe(r.ClaimDispositionProposal, global.proposal.claim_dispositions);
    var signals: std.ArrayList(r.Signal) = .empty;
    try signals.appendSlice(allocator, records.signals);
    var proposed_signals: std.ArrayList(r.SignalProposal) = .empty;
    try proposed_signals.appendSlice(allocator, global.proposal.signals);
    var kept: std.ArrayList(r.Conflict) = .empty;
    var proposed_conflicts: std.ArrayList(r.ConflictProposal) = .empty;
    for (global.proposal.conflicts) |proposal| if (!removedClaims(records, applied.items, proposal.claim_ids)) try proposed_conflicts.append(allocator, proposal);
    var groups: std.ArrayList(@import("reference_conflict_groups.zig").Group) = .empty;
    for (global.proposal.conflict_groups) |group| if (!removedClaims(records, applied.items, group.claim_ids)) try groups.append(allocator, group);

    var answer_superseded: std.ArrayList(r.ClaimId) = .empty;
    var answer_retained: std.ArrayList(r.ClaimId) = .empty;
    for (applied.items) |entry| {
        const conflict = records.conflicts[entry.conflict];
        // Only the claim the user chose: the last claim of a conflict the supersession dropped was not decided by an answer.
        try answer_retained.append(allocator, entry.chosen);
        const related = try allocator.dupe(r.ClaimId, &.{entry.chosen});
        for (conflict.value.claim_ids) |claim| {
            const superseded = claim.ordinal != entry.chosen.ordinal;
            try decide(dispositions, proposed, claim, if (superseded) related else null);
            if (superseded) try answer_superseded.append(allocator, claim);
        }
        try retain(allocator, held.items, &signals, &proposed_signals, entry.chosen);
        // A conflict the supersession left with one claim is dropped with it, and its last claim stands alone.
        for (entry.dropped) |index| {
            const last = for (records.conflicts[index].value.claim_ids) |claim| {
                if (!r.contains(r.ClaimId, conflict.value.claim_ids, claim)) break claim;
            } else return error.InvalidReferenceReconciliation;
            try decide(dispositions, proposed, last, null);
            try retain(allocator, held.items, &signals, &proposed_signals, last);
        }
    }
    for (records.conflicts, 0..) |conflict, index| {
        if (removedIndex(applied.items, index)) continue;
        try kept.append(allocator, .{ .id = .{ .ordinal = @intCast(kept.items.len + 1) }, .value = conflict.value });
    }

    const validated_signals = try allocator.alloc(r.ValidatedSignal, signals.items.len);
    const signal_ids = try allocator.alloc(r.SignalId, signals.items.len);
    for (signals.items, validated_signals, signal_ids) |signal, *value, *id| {
        value.* = signal.value;
        id.* = signal.id;
    }
    const validated_conflicts = try allocator.alloc(r.ValidatedConflict, kept.items.len);
    const conflict_ids = try allocator.alloc(r.ConflictId, kept.items.len);
    for (kept.items, validated_conflicts, conflict_ids) |conflict, *value, *id| {
        value.* = conflict.value;
        id.* = conflict.id;
    }
    var proposal = global.proposal;
    proposal.claim_dispositions = proposed;
    proposal.signals = try proposed_signals.toOwnedSlice(allocator);
    proposal.conflicts = try proposed_conflicts.toOwnedSlice(allocator);
    proposal.conflict_groups = try groups.toOwnedSlice(allocator);
    return .{
        .assignments = records.assignments.rebuilt(dispositions, proposal, validated_signals, signal_ids, validated_conflicts, conflict_ids),
        .signals = try signals.toOwnedSlice(allocator),
        .conflicts = try kept.toOwnedSlice(allocator),
        .answer_superseded = try answer_superseded.toOwnedSlice(allocator),
        .answer_retained = try answer_retained.toOwnedSlice(allocator),
    };
}

/// Sets a claim's disposition and its proposal entry: superseded by the claims in `by`, or retained when `by` is null.
fn decide(dispositions: []r.ClaimDisposition, proposed: []r.ClaimDispositionProposal, claim: r.ClaimId, by: ?[]const r.ClaimId) Error!void {
    dispositions[claim.ordinal - 1] = if (by) |related|
        .{ .claim_id = claim, .disposition = .superseded, .related_claim_ids = related }
    else
        .{ .claim_id = claim, .disposition = .retained, .related_claim_ids = &.{} };
    // The proposal lists the model's dispositions in its order and the preserved tokens after them, so an entry is
    // found by its claim, never by its position.
    const at = for (proposed, 0..) |entry_proposal, position| {
        if (entry_proposal.claim_id.ordinal == claim.ordinal) break position;
    } else return error.InvalidReferenceReconciliation;
    proposed[at] = .{ .claim_id = claim, .disposition = if (by) |related| .{ .superseded = .{ .related_claim_ids = related } } else .{ .retained = .{} } };
}

/// Gives a retained model claim a signal of its own.
fn retain(allocator: std.mem.Allocator, items: r.Items, signals: *std.ArrayList(r.Signal), proposed: *std.ArrayList(r.SignalProposal), claim: r.ClaimId) Error!void {
    const item = r.item(items, claim) catch return error.InvalidReferenceReconciliation;
    if (item.claim.content != .model) return error.InvalidReferenceReconciliation;
    const claims = try allocator.dupe(r.ClaimId, &.{claim});
    const value: r.ValidatedSignal = .{ .claim_ids = claims, .citation_ids = item.claim.citation_ids, .content = .{ .model = item.claim.content.model } };
    try signals.append(allocator, .{ .id = .{ .ordinal = @intCast(signals.items.len + 1) }, .value = value });
    try proposed.append(allocator, .{ .claim_ids = claims, .content = model_evidence.content(value.content) });
}

/// Whether the conflict at `index` is answered or dropped by an applied answer.
fn removedIndex(applied: []const Applied, index: usize) bool {
    for (applied) |entry| {
        if (entry.conflict == index) return true;
        for (entry.dropped) |dropped| if (dropped == index) return true;
    }
    return false;
}

/// Whether the claims are those of a conflict an applied answer removes.
fn removedClaims(records: r.Records, applied: []const Applied, claims: []const r.ClaimId) bool {
    const same = @import("reference_reconciliation_validation.zig").sameMembers;
    for (applied) |entry| {
        if (same(records.conflicts[entry.conflict].value.claim_ids, claims)) return true;
        for (entry.dropped) |dropped| if (same(records.conflicts[dropped].value.claim_ids, claims)) return true;
    }
    return false;
}

/// Whether two answers change one conflict.
fn touches(left: Applied, right: Applied) bool {
    for ([_]Applied{ left, right }, [_]Applied{ right, left }) |one, other| {
        if (one.conflict == other.conflict) return true;
        for (one.dropped) |dropped| {
            if (dropped == other.conflict) return true;
            for (other.dropped) |also| if (also == dropped) return true;
        }
    }
    return false;
}

/// A conflict is answerable when every claim is a model claim of one kind, which a supersession requires, and the claim the
/// answer keeps is in no other conflict, whose disposition would then have to stay `conflicting`. A claim the answer
/// supersedes may be in another conflict only when that conflict is left with one claim, a model claim in no further
/// conflict: a conflict left with two claims would keep a summary written for claims it no longer holds. Returns the
/// conflicts the answer drops, or null when it is not answerable.
fn answerable(allocator: std.mem.Allocator, items: r.Items, conflicts: []const r.Conflict, conflict: r.Conflict, index: usize, chosen: r.ClaimId) Error!?[]const usize {
    const first = (r.item(items, conflict.value.claim_ids[0]) catch return error.InvalidReferenceReconciliation).claim.content;
    if (first != .model) return null;
    for (conflict.value.claim_ids) |claim| {
        const content = (r.item(items, claim) catch return error.InvalidReferenceReconciliation).claim.content;
        if (content != .model or std.meta.activeTag(content.model) != std.meta.activeTag(first.model)) return null;
    }
    var dropped: std.ArrayList(usize) = .empty;
    for (conflicts, 0..) |other, other_index| {
        if (other_index == index) continue;
        var shared = false;
        var left: usize = 0;
        var remaining: ?r.ClaimId = null;
        for (other.value.claim_ids) |claim| {
            if (!r.contains(r.ClaimId, conflict.value.claim_ids, claim)) {
                left += 1;
                remaining = claim;
            } else if (claim.ordinal == chosen.ordinal) return null else shared = true;
        }
        if (!shared) continue;
        if (left != 1) return null;
        const last = remaining.?;
        if ((r.item(items, last) catch return error.InvalidReferenceReconciliation).claim.content != .model) return null;
        for (conflicts, 0..) |further, further_index| {
            if (further_index != index and further_index != other_index and r.contains(r.ClaimId, further.value.claim_ids, last)) return null;
        }
        try dropped.append(allocator, other_index);
    }
    return try dropped.toOwnedSlice(allocator);
}
