//! Canonical claim/citation joins, shared by live assembly and persisted review validation.
const std = @import("std");
const r = @import("reference_reconciliation.zig");

pub fn build(allocator: std.mem.Allocator, inputs: r.evidence.Inputs, ledger: r.extraction.Ledger) r.Error!r.Items {
    if (!inputs.corpus.state_id.eql(ledger.state_id)) return error.InvalidReferenceReconciliation;
    const items = try allocator.alloc(r.Item, ledger.claims.len);
    for (ledger.claims, items, 1..) |claim, *entry, index| {
        if (claim.id.ordinal != index or claim.citation_ids.len == 0) return error.InvalidReferenceReconciliation;
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
        entry.* = .{ .claim = claim, .source_id = unit.source.id, .block_id = unit.chunk.block_id, .citations = citations };
    }
    return .{ .state_id = ledger.state_id, .entries = items, .extraction = ledger.chunks };
}
