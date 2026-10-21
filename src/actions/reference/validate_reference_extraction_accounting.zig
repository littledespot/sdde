const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const evidence = @import("../../domain/reference_evidence.zig");
const extraction = @import("../../domain/reference_extraction.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-reference-extraction-accounting",
        .kind = .action,
        .requires = &.{ .citable_reference_inputs, .preserved_token_identities, .reference_extraction_ledger },
        .produces = &.{.accounted_reference_extraction},
        .side_effect = .none,
    };
    /// The current partition has one chunk per source block. Exact chunk cover
    /// therefore proves block cover too; no second block-status authority.
    pub fn execute(_: Action, inputs: evidence.Inputs, assigned: extraction.TokenAssignments, ledger: extraction.Ledger) extraction.Error!extraction.Accounted {
        if (!ledger.state_id.eql(inputs.corpus.state_id) or ledger.chunks.len != inputs.chunks.entries.len) return error.InvalidReferenceExtraction;
        var claim_index: usize = 0;
        var citation_index: usize = 0;
        var token_index: usize = 0;
        var selection_index: usize = 0;
        var blocked = false;
        for (inputs.chunks.entries, ledger.chunks) |chunk, entry| {
            if (!entry.scope.state_id.eql(ledger.state_id) or !entry.scope.chunk_id.eql(chunk.id)) return error.InvalidReferenceExtraction;
            while (selection_index < assigned.classified.selections.len) : (selection_index += 1) {
                const selection = assigned.classified.selections[selection_index];
                if (!selection.candidate.fact.scope.chunk_id.eql(chunk.id)) break;
                if (!selection.candidate.fact.scope.state_id.eql(ledger.state_id)) return error.InvalidStructuredTokens;
                if ((selection.decision == .blocked) != (entry.outcome == .blocked)) return error.InvalidStructuredTokens;
                if (selection.decision != .preserve) continue;
                if (entry.outcome != .claims or token_index >= assigned.entries.len) return error.InvalidStructuredTokens;
                const assignment = assigned.entries[token_index];
                if (assignment.selection_index != selection_index or assignment.id.ordinal != token_index + 1) return error.InvalidStructuredTokens;
                token_index += 1;
            }
            switch (entry.outcome) {
                .blocked => blocked = true,
                .no_feature_claim => {},
                .claims => |ids| {
                    if (ids.len == 0) return error.InvalidReferenceExtraction;
                    for (ids) |id| {
                        if (claim_index >= ledger.claims.len or id.ordinal != claim_index + 1) return error.InvalidReferenceExtraction;
                        const claim = ledger.claims[claim_index];
                        claim_index += 1;
                        if (claim.id.ordinal != id.ordinal or !claim.chunk_id.eql(chunk.id) or claim.citation_ids.len == 0) return error.InvalidReferenceExtraction;
                        if (claim.content == .preserved_token) {
                            const token = claim.content.preserved_token;
                            if (token.value.id.ordinal == 0 or token.value.id.ordinal > assigned.entries.len or claim.citation_ids.len != 1 or token.citation_id.ordinal != claim.citation_ids[0].ordinal) return error.InvalidStructuredTokens;
                            const assignment = assigned.entries[token.value.id.ordinal - 1];
                            if (assignment.selection_index >= assigned.classified.selections.len) return error.InvalidStructuredTokens;
                            const selection = assigned.classified.selections[assignment.selection_index];
                            if (selection.decision != .preserve or !selection.candidate.fact.scope.chunk_id.eql(chunk.id) or !std.meta.eql(token.value.candidate_id, selection.candidate.id) or token.value.kind != selection.decision.preserve or token.value.downstream_obligation_id.token_id.ordinal != token.value.id.ordinal or !std.mem.eql(u8, token.value.raw_value.bytes, selection.candidate.fact.citation.verbatim.?)) return error.InvalidStructuredTokens;
                            if (citation_index >= ledger.citations.len) return error.InvalidStructuredTokens;
                            const actual = ledger.citations[citation_index].value;
                            const expected = selection.candidate.fact.citation;
                            if (!std.meta.eql(actual.location, expected.location) or actual.verbatim == null or !std.mem.eql(u8, actual.verbatim.?, token.value.raw_value.bytes)) return error.InvalidStructuredTokens;
                        }
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
        if (selection_index != assigned.classified.selections.len or token_index != assigned.entries.len or assigned.next_token_ordinal != token_index + 1) return error.InvalidStructuredTokens;
        // Exactly one deterministic claim per preserved identity: no dropped,
        // duplicate or invented token can hide behind complete chunk coverage.
        var next_token: u32 = 1;
        for (ledger.claims) |claim| if (claim.content == .preserved_token) {
            if (claim.content.preserved_token.value.id.ordinal != next_token) return error.InvalidStructuredTokens;
            next_token = std.math.add(u32, next_token, 1) catch return error.InvalidStructuredTokens;
        };
        if (next_token != assigned.next_token_ordinal) return error.InvalidStructuredTokens;
        return .{ .ledger = ledger, .outcome = if (blocked) .blocked else .complete };
    }
};
