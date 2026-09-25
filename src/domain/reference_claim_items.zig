//! Canonical claim/citation joins, shared by live assembly and persisted review validation.
const std = @import("std");
const r = @import("reference_reconciliation.zig");

pub fn build(allocator: std.mem.Allocator, inputs: r.evidence.Inputs, ledger: r.extraction.Ledger) r.Error!r.Items {
    if (!inputs.corpus.state_id.eql(ledger.state_id)) return error.InvalidReferenceReconciliation;
    const tokens = r.extraction.tokens;
    const candidates = if (for (ledger.claims) |claim| {
        if (claim.content == .preserved_token) break true;
    } else false) candidates: {
        const facts = try tokens.extract(allocator, inputs);
        defer allocator.free(facts.entries);
        break :candidates try tokens.assign(allocator, inputs, facts);
    } else tokens.Candidates{ .state_id = inputs.corpus.state_id, .entries = &.{} };
    defer allocator.free(candidates.entries);
    const items = try allocator.alloc(r.Item, ledger.claims.len);
    for (ledger.claims, items, 1..) |claim, *entry, index| {
        if (claim.id.ordinal != index or claim.citation_ids.len == 0) return error.InvalidReferenceReconciliation;
        // Extraction model claims cite source selections. Canonical token IDs
        // belong to the separate preserved-token claim, never model prose.
        if (claim.content == .model) switch (claim.content.model) {
            .business, .scope_guard => |value| for (value.value.segments) |segment| {
                if (segment == .exact_copy) return error.InvalidReferenceReconciliation;
            },
            else => {},
        };
        const scope: r.evidence.Scope = .{ .state_id = ledger.state_id, .chunk_id = claim.chunk_id };
        const unit = try r.evidence.resolve(inputs, scope);
        const citations = try allocator.alloc(r.extraction.Citation, claim.citation_ids.len);
        const proposals = try allocator.alloc(r.evidence.CitationProposal, citations.len);
        try r.unique(r.CitationId, claim.citation_ids);
        for (claim.citation_ids, citations, proposals) |id, *citation, *proposal| {
            if (id.ordinal == 0 or id.ordinal > ledger.citations.len) return error.InvalidReferenceReconciliation;
            citation.* = ledger.citations[id.ordinal - 1];
            if (citation.id.ordinal != id.ordinal) return error.InvalidReferenceReconciliation;
            proposal.* = .{ .source_id = citation.value.source_id, .block_id = citation.value.block_id, .location = citation.value.location, .verbatim = citation.value.verbatim };
        }
        const checked = try @import("source_citations.zig").validate(allocator, inputs, .{ .scope = scope, .entries = proposals });
        for (citations, checked.entries) |*citation, value| {
            citation.value = value;
            if (value.verbatim) |bytes| citation.value.verbatim = try allocator.dupe(u8, bytes);
        }
        if (claim.content == .preserved_token) {
            const token = claim.content.preserved_token;
            if (citations.len != 1 or token.citation_id.ordinal != citations[0].id.ordinal) return error.InvalidReferenceReconciliation;
            const candidate = for (candidates.entries) |value| {
                if (std.meta.eql(value.id, token.value.candidate_id)) break value;
            } else return error.InvalidReferenceReconciliation;
            if (!tokens.equalFact(candidate.fact, .{ .extractor_id = token.value.candidate_id.extractor_id, .scope = scope, .citation = checked.entries[0] }) or
                !std.mem.eql(u8, token.value.raw_value.bytes, candidate.fact.citation.verbatim.?)) return error.InvalidReferenceReconciliation;
        }
        entry.* = .{ .claim = claim, .source_id = unit.source.id, .block_id = unit.chunk.block_id, .citations = citations };
    }
    return .{ .state_id = ledger.state_id, .entries = items, .extraction = ledger.chunks };
}
