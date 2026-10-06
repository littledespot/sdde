//! Exact-token projections are native consequences of accepted source facts.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
pub const SemanticContent = union(enum) { model: r.extraction.ProposalContent };
pub const SemanticStatement = struct { claim_ids: []const r.ClaimId, content: SemanticContent };
pub const SemanticSummary = struct { statements: []const SemanticStatement };
pub const SemanticSignal = SemanticStatement;
/// Complete model-authored membership; token evidence remains native-owned.
pub fn semanticClaimIds(a: std.mem.Allocator, items: []const r.Item) std.mem.Allocator.Error![]const r.ClaimId {
    var result: std.ArrayList(r.ClaimId) = .empty;
    errdefer result.deinit(a);
    for (items) |item| if (item.claim.content == .model) try result.append(a, item.claim.id);
    return result.toOwnedSlice(a);
}
pub fn signalClaimIds(a: std.mem.Allocator, prior: r.CheckedDispositions) r.Error![]const r.ClaimId {
    const semantic = try semanticClaimIds(a, prior.input.items);
    defer a.free(semantic);
    var result: std.ArrayList(r.ClaimId) = .empty;
    errdefer result.deinit(a);
    for (semantic) |id| if (try @import("reference_reconciliation_validation.zig").signalEligible(prior.dispositions, id)) try result.append(a, id);
    return result.toOwnedSlice(a);
}
pub fn token(item: r.Item) r.Error!r.ContentProposal {
    if (item.claim.content != .preserved_token) return error.InvalidReferenceReconciliation;
    return .{ .preserved_token = .{ .token_id = item.claim.content.preserved_token.value.id } };
}
pub fn summary(a: std.mem.Allocator, input: r.Input, supplied: []const SemanticStatement) r.Error!r.SummaryProposal {
    var result: std.ArrayList(r.StatementProposal) = .empty;
    for (supplied) |value| try result.append(a, .{ .claim_ids = value.claim_ids, .content = .{ .model = value.content.model } });
    for (input.items) |item| if (item.claim.content == .preserved_token) try result.append(a, .{ .claim_ids = try a.dupe(r.ClaimId, &.{item.claim.id}), .content = try token(item) });
    return .{ .statements = try result.toOwnedSlice(a) };
}
pub fn signals(a: std.mem.Allocator, prior: r.CheckedDispositions, supplied: []const SemanticSignal) r.Error![]const r.SignalProposal {
    var result: std.ArrayList(r.SignalProposal) = .empty;
    try result.appendSlice(a, prior.proposal.signals);
    for (supplied) |value| try result.append(a, .{ .claim_ids = value.claim_ids, .content = .{ .model = value.content.model } });
    for (prior.input.items) |item| if (item.claim.content == .preserved_token and prior.dispositions[item.claim.id.ordinal - 1].disposition != .conflicting) {
        for (result.items) |existing| {
            if (existing.content == .preserved_token and r.contains(r.ClaimId, existing.claim_ids, item.claim.id)) break;
        } else try result.append(a, .{ .claim_ids = try a.dupe(r.ClaimId, &.{item.claim.id}), .content = try token(item) });
    };
    return result.toOwnedSlice(a);
}
