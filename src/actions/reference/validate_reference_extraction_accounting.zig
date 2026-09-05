const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const evidence = @import("../../domain/reference_evidence.zig");
const extraction = @import("../../domain/reference_extraction.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-reference-extraction-accounting@1",
        .kind = .action,
        .requires = &.{ .citable_reference_inputs, .reference_extraction_ledger },
        .produces = &.{.accounted_reference_extraction},
        .side_effect = .none,
    };
    /// The current partition has one chunk per source block. Exact chunk cover
    /// therefore proves block cover too; no second block-status authority.
    pub fn execute(_: Action, inputs: evidence.Inputs, ledger: extraction.Ledger) extraction.Error!extraction.Accounted {
        if (!ledger.state_id.eql(inputs.corpus.state_id) or ledger.chunks.len != inputs.chunks.entries.len) return error.InvalidReferenceExtraction;
        var claim_index: usize = 0;
        var citation_index: usize = 0;
        var blocked = false;
        for (inputs.chunks.entries, ledger.chunks) |chunk, entry| {
            if (!entry.scope.state_id.eql(ledger.state_id) or !entry.scope.chunk_id.eql(chunk.id)) return error.InvalidReferenceExtraction;
            switch (entry.outcome) {
                .blocked => blocked = true,
                .no_feature_claim => |reason| if (!extraction.nonempty(reason)) {
                    return error.InvalidReferenceExtraction;
                },
                .claims => |ids| {
                    if (ids.len == 0) return error.InvalidReferenceExtraction;
                    for (ids) |id| {
                        if (claim_index >= ledger.claims.len or id.ordinal != claim_index + 1) return error.InvalidReferenceExtraction;
                        const claim = ledger.claims[claim_index];
                        claim_index += 1;
                        if (claim.id.ordinal != id.ordinal or !claim.chunk_id.eql(chunk.id) or claim.citation_ids.len == 0 or !extraction.nonempty(claim.content.text)) return error.InvalidReferenceExtraction;
                        for (claim.citation_ids) |citation_id| {
                            if (citation_index >= ledger.citations.len or citation_id.ordinal != citation_index + 1) return error.InvalidReferenceExtraction;
                            const citation = ledger.citations[citation_index];
                            citation_index += 1;
                            if (citation.id.ordinal != citation_id.ordinal or citation.value.source_id.ordinal != chunk.source_id.ordinal or citation.value.block_id.ordinal != chunk.block_id.ordinal) return error.InvalidReferenceExtraction;
                        }
                    }
                },
            }
        }
        if (claim_index != ledger.claims.len or citation_index != ledger.citations.len or ledger.next_claim_ordinal != claim_index + 1 or ledger.next_citation_ordinal != citation_index + 1) return error.InvalidReferenceExtraction;
        return .{ .ledger = ledger, .outcome = if (blocked) .blocked else .complete };
    }
};
