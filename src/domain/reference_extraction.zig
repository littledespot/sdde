//! Unreviewed extraction candidates, never a reconciled reference snapshot.
const std = @import("std");
const evidence = @import("reference_evidence.zig");
pub const identity = @import("reference_identity.zig");
pub const Error = evidence.Error || error{InvalidReferenceExtraction};

/// Text remains untrusted source interpretation. BusinessText/passive-literal
/// and semantic reconciliation checks are required before downstream authority.
pub const Content = struct {
    kind: enum { business, design, technical, validation, implementation_assumption, open_question, scope_guard },
    text: []const u8,
};
pub const Proposal = struct { content: Content, citations: []const evidence.CitationProposal };
pub const ValidatedClaim = struct { content: Content, citations: []const evidence.ValidatedCitation };
pub const BlockReason = enum { extraction_failed };
pub const RawResult = struct {
    scope: evidence.Scope,
    /// Only the engine supplies scope and failure; neither is in model JSON.
    result: union(enum) { response: []const u8, blocked: BlockReason },
};
pub const Raw = struct { entries: []const RawResult };
pub const ParsedResult = struct {
    scope: evidence.Scope,
    outcome: union(enum) { claims: []const Proposal, no_feature_claim: []const u8, blocked: BlockReason },
};
pub const Parsed = struct { entries: []const ParsedResult };
pub const ValidatedResult = struct {
    scope: evidence.Scope,
    outcome: union(enum) { claims: []const ValidatedClaim, no_feature_claim: []const u8, blocked: BlockReason },
};
pub const Validated = struct { state_id: identity.StateId, entries: []const ValidatedResult };
pub const ClaimId = identity.ClaimId;
pub const CitationId = identity.CitationId;
pub const Assignment = struct { claim_id: ClaimId, citation_ids: []const CitationId };
pub const Assignments = struct {
    validated: Validated,
    claims: []const Assignment,
    next_claim_ordinal: u32,
    next_citation_ordinal: u32,
};
pub const Citation = struct { id: CitationId, value: evidence.ValidatedCitation };
pub const Claim = struct { id: ClaimId, chunk_id: identity.ChunkId, content: Content, citation_ids: []const CitationId };
pub const ChunkResult = struct {
    scope: evidence.Scope,
    outcome: union(enum) { claims: []const ClaimId, no_feature_claim: []const u8, blocked: BlockReason },
};
pub const Ledger = struct {
    state_id: identity.StateId,
    chunks: []const ChunkResult,
    claims: []const Claim,
    citations: []const Citation,
    next_claim_ordinal: u32,
    next_citation_ordinal: u32,
};
pub const Accounted = struct { ledger: Ledger, outcome: enum { complete, blocked } };

pub fn nonempty(text: []const u8) bool {
    return std.unicode.utf8ValidateSlice(text) and std.mem.trim(u8, text, " \t\r\n").len != 0;
}
