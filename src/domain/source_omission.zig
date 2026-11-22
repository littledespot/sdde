//! Semantic loss attribution is evidence, never write authority. Candidate
//! owners derive the smallest repair and bind its current revision separately.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const authority = @import("required_authority.zig");
/// Shared native comparison admission and attribution.
pub const comparisons = @import("source_omission_comparison.zig");
pub const Location = union(enum) {
    unlocalized: struct {},
    candidate: struct {},
    /// Source meaning survived upstream but was not selected for this exact
    /// authored requirement. This is evidence for rework, not write permission.
    source_association: authority.Id,
    unsupported_summary: r.SummaryId,
    extraction_claim: r.extraction.identity.ChunkId,
    token_classification: r.extraction.tokens.CandidateId,
    reconciliation_signal: r.SignalId,
    reconciliation_disposition: r.ClaimId,
    reconciliation_conflict: r.ConflictId,

    pub fn eql(self: Location, other: Location) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(other)) return false;
        return switch (self) {
            .extraction_claim => |id| id.eql(other.extraction_claim),
            inline else => |value, tag| std.meta.eql(value, @field(other, @tagName(tag))),
        };
    }
};
/// Candidate loss and unresolved attribution grant no upstream repair target.
pub fn isUpstream(location: Location) bool {
    return switch (location) {
        .unlocalized, .candidate, .source_association, .unsupported_summary => false,
        .extraction_claim, .token_classification, .reconciliation_signal, .reconciliation_disposition, .reconciliation_conflict => true,
    };
}
pub const SourceLines = struct { chunk_id: r.extraction.identity.ChunkId, source_id: r.extraction.identity.SourceId, lines: []const @import("source_selections.zig").Choice };

/// Allocations belong to the caller's request arena.
pub fn sourceLines(a: std.mem.Allocator, sources: r.evidence.Inputs) r.Error![]const SourceLines {
    var result: std.ArrayList(SourceLines) = .empty;
    for (sources.chunks.entries) |chunk| {
        try result.append(a, .{ .chunk_id = chunk.id, .source_id = chunk.source_id, .lines = try @import("source_selections.zig").project(a, sources, .{ .state_id = sources.corpus.state_id, .chunk_id = chunk.id }) });
    }
    return result.toOwnedSlice(a);
}

pub const Evidence = struct { finding: authority.Evidence, location: Location };
pub const Rejection = enum {
    unlocalized_omission,
    invalid_repair_authority,
    post_generation_source_repair_forbidden,

    pub fn explanation(self: Rejection) []const u8 {
        return switch (self) {
            .unlocalized_omission => "The source review reports an omission without establishing a defective upstream producer. No upstream repair target can be authorized.",
            .invalid_repair_authority => "The source omission cannot establish current repair authority. The workflow stops without a repair call or publication.",
            .post_generation_source_repair_forbidden => "Generation has started. Semantic review cannot authorize mutation of consumed source authority.",
        };
    }
};
/// Diagnostic claims belong to the named producer, independently of whether
/// that producer's output is eligible as positive business content.
pub fn diagnosticClaims(records: @import("reference_support.zig").Records, location: Location) ?[]const r.ClaimId {
    return switch (location) {
        .unlocalized, .candidate, .source_association, .unsupported_summary => null,
        .extraction_claim, .token_classification => &.{},
        .reconciliation_signal => |id| for (records.signals) |signal| {
            if (std.meta.eql(signal.id, id)) break signal.value.claim_ids;
        } else null,
        .reconciliation_conflict => |id| for (records.conflicts) |conflict| {
            if (std.meta.eql(conflict.id, id)) break conflict.value.claim_ids;
        } else null,
        // A disposition loss has one claim. The caller uses the existing item
        // storage so the returned slice does not borrow a temporary union value.
        .reconciliation_disposition => |id| for (records.dispositions) |*disposition| {
            if (std.meta.eql(disposition.claim_id, id)) break @as(*const [1]r.ClaimId, &disposition.claim_id)[0..];
        } else null,
    };
}

/// Verify all mechanical joins. Meaning and loss attribution remain explicitly
/// model-assisted; absence of a unique location cannot authorize a repair.
pub fn validate(a: std.mem.Allocator, inputs: authority.Inputs, sources: r.evidence.Inputs, subject_id: authority.Id, finding: authority.Finding, review: authority.ReviewEvidence, location: Location) (authority.Error || r.Error)!void {
    if (!@import("specification_support_evidence.zig").validObligation(finding, review.missing_obligation)) return error.InvalidRequiredAuthority;
    if (review.preservation) |proof| {
        if (finding != .candidate_omission) return error.InvalidRequiredAuthority;
        const derived = comparisons.validate(a, inputs, sources, subject_id, review, proof) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidRequiredAuthority;
        if (!comparisons.location(derived).eql(location)) return error.InvalidRequiredAuthority;
    } else if (location != .unlocalized) return error.InvalidRequiredAuthority;
    try validateLocation(inputs, sources, subject_id, finding, review, location);
}

fn validateLocation(inputs: authority.Inputs, sources: r.evidence.Inputs, subject_id: authority.Id, finding: authority.Finding, review: authority.ReviewEvidence, location: Location) (authority.Error || r.Error)!void {
    if (location == .source_association) {
        if (finding != .candidate_omission or !std.meta.eql(location.source_association, subject_id)) return error.InvalidRequiredAuthority;
        switch (subject_id.unit) {
            .feature, .record => {},
            else => return error.InvalidRequiredAuthority,
        }
        return;
    }
    if (location == .unlocalized or location == .unsupported_summary) return;
    if (finding != .candidate_omission) return error.InvalidRequiredAuthority;
    // No candidate exists before generation, so none can be blamed.
    if (location == .candidate) return error.InvalidRequiredAuthority;
    if (review.source_ids.len == 0) return error.InvalidRequiredAuthority;
    const records = inputs.references orelse return error.InvalidRequiredAuthority;
    switch (location) {
        .unlocalized, .candidate, .source_association, .unsupported_summary => unreachable,
        .extraction_claim => |id| {
            if (review.provenance.claim_ids.len != 0) return error.InvalidRequiredAuthority;
            const scope: r.evidence.Scope = .{ .state_id = records.items.state_id, .chunk_id = id };
            const view = try r.evidence.resolve(sources, scope);
            if (!r.contains(r.extraction.identity.SourceId, review.source_ids, view.source.id)) return error.InvalidRequiredAuthority;
            for (records.items.extraction) |chunk| if (chunk.scope.chunk_id.eql(id)) {
                if (chunk.outcome == .blocked) return error.InvalidRequiredAuthority;
                return;
            };
            return error.InvalidRequiredAuthority;
        },
        .token_classification => |id| {
            for (records.items.extraction) |chunk| for (chunk.token_classifications) |classification| {
                if (!std.meta.eql(classification.id(), id)) continue;
                const view = try r.evidence.resolve(sources, chunk.scope);
                if (chunk.outcome != .claims or classification != .irrelevant or !r.contains(r.extraction.identity.SourceId, review.source_ids, view.source.id)) return error.InvalidRequiredAuthority;
                return;
            };
            return error.InvalidRequiredAuthority;
        },
        .reconciliation_signal => |id| {
            for (records.signals) |signal| if (std.meta.eql(signal.id, id)) {
                try r.sameSet(r.ClaimId, signal.value.claim_ids, review.provenance.claim_ids);
                for (signal.value.claim_ids) |claim| try sourceForClaim(records.items, claim, review.source_ids);
                return;
            };
            return error.InvalidRequiredAuthority;
        },
        .reconciliation_conflict => |id| {
            for (records.conflicts) |conflict| if (std.meta.eql(conflict.id, id)) {
                try r.sameSet(r.ClaimId, conflict.value.claim_ids, review.provenance.claim_ids);
                for (conflict.value.claim_ids) |claim| try sourceForClaim(records.items, claim, review.source_ids);
                return;
            };
            return error.InvalidRequiredAuthority;
        },
        .reconciliation_disposition => |id| {
            try sourceForClaim(records.items, id, review.source_ids);
            if ((try r.item(records.items, id)).claim.content != .model) return error.InvalidRequiredAuthority;
            for (records.dispositions) |disposition| if (std.meta.eql(disposition.claim_id, id)) {
                if (disposition.disposition == .conflicting or disposition.disposition == .retained) return error.InvalidRequiredAuthority;
                return;
            };
            return error.InvalidRequiredAuthority;
        },
    }
}

/// Existing producer identities, independently of whether this finding may select
/// them for repair. Comparison evidence must not disappear with repair eligibility.
pub fn producerLocations(a: std.mem.Allocator, records: @import("reference_support.zig").Records) std.mem.Allocator.Error![]const Location {
    var candidates: std.ArrayList(Location) = .empty;
    errdefer candidates.deinit(a);
    for (records.items.extraction) |chunk| {
        try candidates.append(a, .{ .extraction_claim = chunk.scope.chunk_id });
        for (chunk.token_classifications) |classification| try candidates.append(a, .{ .token_classification = classification.id() });
    }
    for (records.dispositions) |disposition| try candidates.append(a, .{ .reconciliation_disposition = disposition.claim_id });
    for (records.signals) |signal| try candidates.append(a, .{ .reconciliation_signal = signal.id });
    for (records.conflicts) |conflict| try candidates.append(a, .{ .reconciliation_conflict = conflict.id });
    return candidates.toOwnedSlice(a);
}

fn sourceForClaim(items: r.Items, id: r.ClaimId, sources: []const r.extraction.identity.SourceId) (authority.Error || r.Error)!void {
    if (!r.contains(r.extraction.identity.SourceId, sources, (try r.item(items, id)).source_id)) return error.InvalidRequiredAuthority;
}

/// The compiler sees the exact invalidation set for each registered binding.
const merge_context = [_]@import("pipeline.zig").DataKey{ .citable_reference_inputs, .reference_passive_literals, .required_authority_inputs, .required_authority_observations, .required_authority_result, .specification_support_review, .source_omission_repair };
pub const extraction_requires = merge_context ++ [_]@import("pipeline.zig").DataKey{ .structured_token_candidates, .text_validated_reference_extraction };
// Summary parsing consumes raw_reference_reconciliation before review. It is
// already retired here, so the dependent set contains only surviving facts.
pub const extraction_dependents = [_]@import("pipeline.zig").DataKey{ .validated_token_classifications, .preserved_token_identities, .prepared_reference_claims, .validated_reference_claims, .reference_claim_identities, .reference_extraction_ledger, .accounted_reference_extraction, .reference_reconciliation_items, .reference_reconciliation_layout, .reference_reconciliation_plan, .reference_reconciliation_progress, .reference_reconciliation_input, .parsed_reference_reconciliation, .validated_reference_dispositions, .validated_reference_signals, .validated_reference_conflicts, .reference_reconciliation_identities, .reference_reconciliation_records, .accounted_reference_reconciliation, .specification_support_review, .required_authority_inputs, .required_authority_ledger, .required_authority_observations, .required_authority_result, .required_authority_gate, .source_omission_repair };
pub const reconciliation_requires = merge_context ++ [_]@import("pipeline.zig").DataKey{.parsed_reference_reconciliation};
pub const reconciliation_dependents = [_]@import("pipeline.zig").DataKey{ .validated_reference_dispositions, .validated_reference_signals, .validated_reference_conflicts, .reference_reconciliation_identities, .reference_reconciliation_records, .accounted_reference_reconciliation, .specification_support_review, .required_authority_inputs, .required_authority_ledger, .required_authority_observations, .required_authority_result, .required_authority_gate, .source_omission_repair };
