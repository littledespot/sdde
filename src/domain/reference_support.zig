//! Borrowed canonical reference evidence; no execution history or continuation.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
pub const Records = struct {
    items: r.Items,
    dispositions: []const r.ClaimDisposition,
    signals: []const r.Signal,
    conflicts: []const r.Conflict,
};
pub fn records(value: r.Accounted) Records {
    const global = value.records.assignments.checked.prior.prior;
    return .{ .items = global.input.progress.plan.layout.items, .dispositions = global.dispositions, .signals = value.records.signals, .conflicts = value.records.conflicts };
}
pub fn snapshot(a: std.mem.Allocator, value: @import("reference_snapshot.zig").Snapshot) r.Error!Records {
    return .{ .items = try @import("reference_claim_items.zig").build(a, value.inputs, value.extraction), .dispositions = value.dispositions, .signals = value.signals, .conflicts = value.conflicts };
}
pub const Resolved = struct {
    claim_ids: []const r.ClaimId,
    citation_ids: []const r.CitationId,
    scopes: []const r.evidence.Scope,
};
/// One preserved occurrence, addressed by its canonical claim rather than a
/// model-assembled token/citation tuple.
pub fn exact(items: r.Items, id: r.ClaimId) r.Error!r.extraction.tokens.Token {
    const claim = (try r.item(items, id)).claim;
    if (claim.content != .preserved_token) return error.InvalidReferenceReconciliation;
    return claim.content.preserved_token;
}

/// Stable evidence order: explicit selections first, then exact occurrences
/// in the caller's declared field order. Explicit duplicates remain invalid.
pub fn lineage(a: std.mem.Allocator, explicit: []const r.ClaimId, exact_claims: []const r.ClaimId) (std.mem.Allocator.Error || r.Error)![]const r.ClaimId {
    try r.unique(r.ClaimId, explicit);
    var result: std.ArrayList(r.ClaimId) = .empty;
    errdefer result.deinit(a);
    try result.appendSlice(a, explicit);
    for (exact_claims) |id| {
        if (!r.contains(r.ClaimId, result.items, id)) try result.append(a, id);
    }
    return result.toOwnedSlice(a);
}
/// Resolve reference mechanics; consumers retain their eligibility and other support policy.
pub fn select(a: std.mem.Allocator, items: r.Items, inputs: r.evidence.Inputs, claim_ids: []const r.ClaimId) (r.Error || error{InvalidReferenceState})!Resolved {
    if (!items.state_id.eql(inputs.corpus.state_id)) return error.InvalidReferenceState;
    try r.unique(r.ClaimId, claim_ids);
    const scopes = try a.alloc(r.evidence.Scope, claim_ids.len);
    errdefer a.free(scopes);
    for (claim_ids, scopes) |id, *scope| {
        const claim = (try r.item(items, id)).claim;
        scope.* = .{ .state_id = items.state_id, .chunk_id = claim.chunk_id };
        _ = try r.evidence.resolve(inputs, scope.*);
    }
    return .{ .claim_ids = claim_ids, .citation_ids = try r.citationUnion(a, items, claim_ids), .scopes = scopes };
}
