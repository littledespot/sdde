//! Unreviewed extraction candidates, never a reconciled reference snapshot.
const std = @import("std");
const evidence = @import("reference_evidence.zig");
pub const identity = @import("reference_identity.zig");
pub const text = @import("typed_text.zig");
pub const tokens = @import("structured_tokens.zig");
pub const Error = text.Error || tokens.Error || error{InvalidReferenceExtraction};
const Origin = @import("model_candidate_origin.zig").Origin;

/// Native decoding projects the assembled fields' actual producers once. The
/// entry's origin remains the original candidate association for retry identity.
pub const ProducerOrigins = struct { content: ?Origin, classifications: ?Origin };

/// Syntax-validated interpretation is still not reconciled business authority.
pub const ProposalContent = ContentOf(text.BusinessText, text.ReferenceSemanticText);
pub const Content = ContentOf(text.ValidatedBusinessText, text.ValidatedReferenceSemanticText);
pub const Kind = enum { business, design, technical, validation, implementation_assumption, open_question, scope_guard };
fn ContentOf(comptime Business: type, comptime Reference: type) type {
    return union(Kind) { business: Business, design: Reference, technical: Reference, validation: Reference, implementation_assumption: Reference, open_question: Reference, scope_guard: Business };
}
pub const Proposal = struct { content: ProposalContent, citations: []const @import("source_selections.zig").Selection };
pub const TextValidatedProposal = struct {
    content: Content,
    citations: []const @import("source_selections.zig").Selection,
    origin: ?@import("model_candidate_origin.zig").Origin = null,
    citations_origin: ?Origin = null,
    citation_origins: []const ?@import("model_candidate_origin.zig").Origin,

    pub fn rejectionOrigin(self: TextValidatedProposal, issue: @import("source_selections.zig").Issue) Error!?@import("model_candidate_origin.zig").Origin {
        if (self.citations.len != self.citation_origins.len) return error.InvalidReferenceExtraction;
        return if (issue.rejected == null) self.citations_origin else if (issue.index < self.citation_origins.len) self.citation_origins[issue.index] else error.InvalidReferenceExtraction;
    }
};
pub const PreparedContent = union(enum) { model: Content, preserved_token: tokens.Value };
pub const PreparedClaim = union(enum) { model: TextValidatedProposal, preserved_token: struct { value: tokens.Value, citation: evidence.ValidatedCitation } };
pub const ValidatedClaim = struct { content: PreparedContent, citations: []const evidence.ValidatedCitation };
pub const BlockReason = enum { extraction_failed };
pub const RawResult = struct {
    scope: evidence.Scope,
    /// Frozen association for this native candidate, independent of producers.
    origin: ?@import("model_candidate_origin.zig").Origin = null,
    producers: ?ProducerOrigins = null,
    /// Only the engine supplies scope and failure; neither is in model JSON.
    result: union(enum) { response: []const u8, blocked: BlockReason },
};
pub const Raw = struct { entries: []const RawResult };
pub const ParsedResult = struct {
    scope: evidence.Scope,
    origin: ?@import("model_candidate_origin.zig").Origin = null,
    producers: ?ProducerOrigins = null,
    text_origins: []const TextOrigin = &.{},
    token_classifications: []const tokens.Classification,
    outcome: union(enum) { claims: []const Proposal, no_feature_claim: text.ReferenceSemanticText, blocked: BlockReason },
};
pub const TextTarget = union(enum) { claim: usize, reason };
pub const TextOrigin = struct { target: TextTarget, origin: ?@import("model_candidate_origin.zig").Origin };
pub fn textOrigin(entry: ParsedResult, target: TextTarget) ?@import("model_candidate_origin.zig").Origin {
    for (entry.text_origins) |value| if (std.meta.eql(value.target, target)) return value.origin;
    return if (entry.producers) |producers| producers.content else entry.origin;
}
pub const Parsed = struct {
    revision: u64 = 1,
    last_repair: ?@import("atomic_repair.zig").Merge = null,
    pending_repair: ?@import("atomic_repair.zig").Pending(@import("reference_extraction_text_repair.zig").Target) = null,
    entries: []const ParsedResult,
};
pub const TextRejection = struct {
    scope: evidence.Scope,
    revision: u64,
    target: TextTarget,
    origin: ?@import("model_candidate_origin.zig").Origin,
    issue: text.Issue,
    observed: union(enum) { content: ProposalContent, reason: text.ReferenceSemanticText },
    dependencies: @import("atomic_repair.zig").Snapshot,
};
pub const TextResult = union(enum) { valid: TextValidated, invalid: TextRejection };
pub const TextValidatedResult = struct {
    scope: evidence.Scope,
    origin: ?@import("model_candidate_origin.zig").Origin = null,
    /// Immutable, index-aligned provenance owned together with the current values.
    classification_origins: []const ?Origin = &.{},
    token_classifications: []const tokens.Classification,
    outcome: union(enum) { claims: []const TextValidatedProposal, no_feature_claim: text.ValidatedReferenceSemanticText, blocked: BlockReason },
};
pub const TextValidated = struct {
    revision: u64 = 1,
    last_repair: ?@import("atomic_repair.zig").Merge = null,
    pending_repair: ?@import("atomic_repair.zig").Pending(@import("reference_extraction_repair.zig").Target) = null,
    omission_retry: ?@import("workflow_retry.zig").Permit = null,
    entries: []const TextValidatedResult,
};
pub const Classified = struct { dependencies: ?@import("atomic_repair.zig").Snapshot = null, text_validated: TextValidated, selections: []const tokens.Selected };
pub const TokenAssignments = struct { classified: Classified, entries: []const tokens.Assignment, next_token_ordinal: u32 };
pub const PreparedResult = struct {
    scope: evidence.Scope,
    token_classifications: []const tokens.Classification = &.{},
    outcome: union(enum) { claims: []const PreparedClaim, no_feature_claim: text.ValidatedReferenceSemanticText, blocked: BlockReason },
};
pub const Prepared = struct { dependencies: ?@import("atomic_repair.zig").Snapshot = null, revision: u64, entries: []const PreparedResult };
pub const ValidatedResult = struct {
    scope: evidence.Scope,
    token_classifications: []const tokens.Classification = &.{},
    outcome: union(enum) { claims: []const ValidatedClaim, no_feature_claim: text.ValidatedReferenceSemanticText, blocked: BlockReason },
};
pub const Validated = struct { state_id: identity.StateId, entries: []const ValidatedResult };
pub const Validation = union(enum) { valid: Validated, invalid: @import("reference_selection_validation.zig").Rejection };
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
pub const ClaimContent = union(enum) { model: Content, preserved_token: tokens.Token };
pub const Claim = struct { id: ClaimId, chunk_id: identity.ChunkId, content: ClaimContent, citation_ids: []const CitationId };
pub const ChunkResult = struct {
    scope: evidence.Scope,
    token_classifications: []const tokens.Classification = &.{},
    outcome: union(enum) { claims: []const ClaimId, no_feature_claim: text.ValidatedReferenceSemanticText, blocked: BlockReason },
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
