//! The reference reconciliation as the user's answers leave it. A resolved choice among the claims of a conflict makes the
//! chosen claim retained and the others superseded by it, drops the conflict and gives the chosen claim a signal, so the
//! result is an ordinary reconciliation: every reconciliation rule holds for it, the persisted reference snapshot
//! validates, and generation, review, scenarios and rendering read the chosen claim as they read any retained claim. The
//! engine applies the choice; no model reads it and no code judges its prose (ADR 0025).
//!
//! A conflict is answered only when it can be: its claims are model claims of one kind, and none is in another conflict.
//! Any other conflict, and an answer whose option no claim of the conflict offers any more, leaves it unresolved, so
//! the form stays protected and its need is raised again.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const refs = @import("reference_support.zig");
const resolution = @import("clarification_resolution.zig");
const model_evidence = @import("model_evidence.zig");
const clarifications = @import("required_authority_clarifications.zig");

pub const Error = std.mem.Allocator.Error || error{InvalidReferenceReconciliation};

const Applied = struct { conflict: usize, chosen: r.ClaimId };

/// The caller's arena owns everything returned and everything allocated on the way, as the reconciliation's builders do.
pub fn apply(allocator: std.mem.Allocator, source_inputs: r.evidence.Inputs, records: r.Records, all: []const resolution.ConflictChoice) Error!r.Records {
    if (all.len == 0 or records.conflicts.len == 0) return records;
    const held = refs.records(.{ .records = records, .outcome = .blocked });
    var applied: std.ArrayList(Applied) = .empty;
    defer applied.deinit(allocator);
    for (records.conflicts, 0..) |conflict, index| {
        const subject = clarifications.subjectFor(allocator, source_inputs, held, .{ .kind = .reference_meaning, .unit = .{ .conflict = conflict.id }, .slot = .disposition }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceReconciliation;
        const choice = resolution.answerFor(all, subject) orelse continue;
        const chosen = (resolution.chosenClaim(allocator, source_inputs.corpus.sources, held, conflict, choice.key, choice.label) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceReconciliation) orelse continue;
        if (!try answerable(held.items, records.conflicts, conflict, index)) continue;
        try applied.append(allocator, .{ .conflict = index, .chosen = chosen });
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
    for (global.proposal.conflicts) |proposal| if (!answeredClaims(records, applied.items, proposal.claim_ids)) try proposed_conflicts.append(allocator, proposal);
    var groups: std.ArrayList(@import("reference_conflict_groups.zig").Group) = .empty;
    for (global.proposal.conflict_groups) |group| if (!answeredClaims(records, applied.items, group.claim_ids)) try groups.append(allocator, group);

    for (applied.items) |entry| {
        const conflict = records.conflicts[entry.conflict];
        const related = try allocator.dupe(r.ClaimId, &.{entry.chosen});
        for (conflict.value.claim_ids) |claim| {
            const value: r.ClaimDisposition = if (claim.ordinal == entry.chosen.ordinal)
                .{ .claim_id = claim, .disposition = .retained, .related_claim_ids = &.{} }
            else
                .{ .claim_id = claim, .disposition = .superseded, .related_claim_ids = related };
            dispositions[claim.ordinal - 1] = value;
            // The proposal lists the model's dispositions in its order and the preserved tokens after them, so an entry is
            // found by its claim, never by its position.
            const at = for (proposed, 0..) |entry_proposal, position| {
                if (entry_proposal.claim_id.ordinal == claim.ordinal) break position;
            } else return error.InvalidReferenceReconciliation;
            proposed[at] = .{ .claim_id = claim, .disposition = if (claim.ordinal == entry.chosen.ordinal) .{ .retained = .{} } else .{ .superseded = .{ .related_claim_ids = related } } };
        }
        const item = r.item(held.items, entry.chosen) catch return error.InvalidReferenceReconciliation;
        const value: r.ValidatedSignal = .{ .claim_ids = related, .citation_ids = item.claim.citation_ids, .content = .{ .model = item.claim.content.model } };
        try signals.append(allocator, .{ .id = .{ .ordinal = @intCast(signals.items.len + 1) }, .value = value });
        try proposed_signals.append(allocator, .{ .claim_ids = related, .content = model_evidence.content(value.content) });
    }
    for (records.conflicts, 0..) |conflict, index| {
        if (answeredIndex(applied.items, index)) continue;
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
    };
}

fn answeredIndex(applied: []const Applied, index: usize) bool {
    for (applied) |entry| if (entry.conflict == index) return true;
    return false;
}

/// Whether the claims are those of an answered conflict.
fn answeredClaims(records: r.Records, applied: []const Applied, claims: []const r.ClaimId) bool {
    for (applied) |entry| if (@import("reference_reconciliation_validation.zig").sameMembers(records.conflicts[entry.conflict].value.claim_ids, claims)) return true;
    return false;
}

/// A conflict is answerable when every claim is a model claim of one kind, which a supersession requires, and no claim is
/// also in another conflict, whose disposition would then have to stay `conflicting`.
fn answerable(items: r.Items, conflicts: []const r.Conflict, conflict: r.Conflict, index: usize) Error!bool {
    const first = (r.item(items, conflict.value.claim_ids[0]) catch return error.InvalidReferenceReconciliation).claim.content;
    if (first != .model) return false;
    for (conflict.value.claim_ids) |claim| {
        const content = (r.item(items, claim) catch return error.InvalidReferenceReconciliation).claim.content;
        if (content != .model or std.meta.activeTag(content.model) != std.meta.activeTag(first.model)) return false;
        for (conflicts, 0..) |other, other_index| {
            if (other_index != index and r.contains(r.ClaimId, other.value.claim_ids, claim)) return false;
        }
    }
    return true;
}
