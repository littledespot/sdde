//! Semantic loss attribution is evidence, never write authority. Candidate
//! owners derive the smallest repair and bind its current revision separately.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const authority = @import("required_authority.zig");
pub const Location = union(enum) {
    unlocalized: struct {},
    extraction_claim: r.extraction.identity.ChunkId,
    token_classification: r.extraction.tokens.CandidateId,
    reconciliation_signal: r.SignalId,
    reconciliation_disposition: r.ClaimId,
};
pub const Support = struct { review: @import("specification_support.zig").Source.Candidate, inputs: authority.Inputs, observations: authority.Observations, result: authority.Result };
pub const Evidence = struct { finding: authority.Evidence, location: Location };
pub const Error = authority.Error || r.Error || @import("specification_support.zig").Source.Error;

pub fn select(a: std.mem.Allocator, sources: r.evidence.Inputs, support: Support) Error!Evidence {
    var unreviewed = support.inputs;
    unreviewed.evidence = &.{};
    unreviewed.candidates = &.{};
    const checked = try @import("specification_support.zig").Source.validate(a, unreviewed, sources, support.review);
    if (checked != .accepted or !std.meta.eql(try @import("atomic_repair.zig").snapshot(authority.Inputs, a, checked.accepted.inputs), try @import("atomic_repair.zig").snapshot(authority.Inputs, a, support.inputs))) return error.InvalidRequiredAuthority;
    for (support.result.entries) |entry| {
        const finding = (try authority.supportedOmission(a, support.inputs, support.observations, support.result, entry.requirement)) orelse continue;
        try @import("specification_support_evidence.zig").validate(a, support.inputs, sources, finding);
        for (support.review.review.entries) |review| if (review.requirement_ordinal == finding.id.ordinal) {
            if (review.value.loss == .unlocalized) return error.InvalidRequiredAuthority;
            return .{ .finding = finding, .location = review.value.loss };
        };
        return error.InvalidRequiredAuthority;
    }
    return error.InvalidRequiredAuthority;
}

/// Verify all mechanical joins. Meaning and loss attribution remain explicitly
/// model-assisted; absence of a unique location cannot authorize a repair.
pub fn validate(inputs: authority.Inputs, sources: r.evidence.Inputs, finding: authority.Finding, review: authority.ReviewEvidence, location: Location) Error!void {
    if (location == .unlocalized) return;
    if (finding != .candidate_omission or review.source_ids.len == 0) return error.InvalidRequiredAuthority;
    const records = inputs.references orelse return error.InvalidRequiredAuthority;
    switch (location) {
        .unlocalized => unreachable,
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
        .reconciliation_disposition => |id| {
            try sourceForClaim(records.items, id, review.source_ids);
            for (records.dispositions) |disposition| if (std.meta.eql(disposition.claim_id, id)) {
                if (disposition.disposition == .conflicting or disposition.disposition == .retained) return error.InvalidRequiredAuthority;
                return;
            };
            return error.InvalidRequiredAuthority;
        },
    }
}
fn sourceForClaim(items: r.Items, id: r.ClaimId, sources: []const r.extraction.identity.SourceId) Error!void {
    if (!r.contains(r.extraction.identity.SourceId, sources, (try r.item(items, id)).source_id)) return error.InvalidRequiredAuthority;
}

// Execution-private association retained by the existing candidate storage.
pub const Authorization = union(enum) {
    extraction: @import("reference_extraction_repair.zig").Omission.Authorization,
    reconciliation: @import("reference_reconciliation_repair.zig").Omission.Authorization,
};
pub const Replacement = union(enum) {
    extraction: @import("reference_extraction_repair.zig").Omission.Replacement,
    reconciliation: @import("reference_reconciliation_repair.zig").Replacement,
};
pub const Repair = struct {
    authorization: Authorization,
    response: ?struct { value: Replacement, origin: @import("model_candidate_origin.zig").Origin } = null,
};

/// The compiler sees the exact invalidation set for each registered binding.
pub const Scope = enum { references, specification };
pub const specification_dependents = [_]@import("pipeline.zig").DataKey{ .specification_generation_session, .identified_specification_content, .specification_id_ledger, .specification_coverage };
const merge_context = [_]@import("pipeline.zig").DataKey{ .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .required_authority_inputs, .required_authority_observations, .required_authority_result, .specification_support_review, .source_omission_repair };
pub const extraction_requires = merge_context ++ [_]@import("pipeline.zig").DataKey{ .structured_token_candidates, .text_validated_reference_extraction };
pub const extraction_dependents = [_]@import("pipeline.zig").DataKey{ .validated_reference_selections, .preserved_token_identities, .prepared_reference_claims, .validated_reference_claims, .reference_claim_identities, .reference_extraction_ledger, .accounted_reference_extraction, .reference_reconciliation_items, .reference_reconciliation_layout, .reference_reconciliation_plan, .reference_reconciliation_progress, .reference_reconciliation_input, .raw_reference_reconciliation, .parsed_reference_reconciliation, .validated_reference_dispositions, .validated_reference_signals, .validated_reference_conflicts, .reference_reconciliation_identities, .reference_reconciliation_records, .accounted_reference_reconciliation, .specification_support_review, .required_authority_inputs, .required_authority_ledger, .required_authority_observations, .required_authority_result, .required_authority_gate, .source_omission_repair };
pub const reconciliation_requires = merge_context ++ [_]@import("pipeline.zig").DataKey{.parsed_reference_reconciliation};
pub const reconciliation_dependents = [_]@import("pipeline.zig").DataKey{ .validated_reference_dispositions, .validated_reference_signals, .validated_reference_conflicts, .reference_reconciliation_identities, .reference_reconciliation_records, .accounted_reference_reconciliation, .specification_support_review, .required_authority_inputs, .required_authority_ledger, .required_authority_observations, .required_authority_result, .required_authority_gate, .source_omission_repair };
