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
    reconciliation_conflict: r.ConflictId,
};
pub const Support = struct { review: @import("specification_support.zig").Source.Candidate, inputs: authority.Inputs, observations: authority.Observations, result: authority.Result };
pub const Evidence = struct { finding: authority.Evidence, location: Location };
pub const Rejection = enum {
    unlocalized_omission,
    invalid_repair_authority,

    pub fn explanation(self: Rejection) []const u8 {
        return switch (self) {
            .unlocalized_omission => "The source review reports an omission without identifying a defective producer. No safe repair target can be authorized; the workflow stops without a repair call or publication.",
            .invalid_repair_authority => "The source omission cannot establish current repair authority. The workflow stops without a repair call or publication.",
        };
    }
};
pub const Error = authority.Error || r.Error || @import("specification_support.zig").Source.Error || error{UnlocalizedSourceOmission};
const retry = @import("workflow_retry.zig");
const atomic = @import("atomic_repair.zig");
pub const Producer = enum { extraction, reconciliation };
const Family = enum { source_omission };
const Subject = union(enum) { feature: authority.Id, token: r.extraction.tokens.CandidateId, regenerated: authority.Id, conflict_claims: []const r.ClaimId };

fn subject(a: std.mem.Allocator, inputs: authority.Inputs, requirement: authority.Id) Error!Subject {
    return switch (requirement.unit) {
        .feature => .{ .feature = requirement },
        .token => |id| token: {
            for ((inputs.references orelse return error.InvalidRequiredAuthority).items.entries) |entry| {
                if (entry.claim.content != .preserved_token) continue;
                const value = entry.claim.content.preserved_token.value;
                if (std.meta.eql(value.id, id)) break :token .{ .token = value.candidate_id };
            }
            return error.InvalidRequiredAuthority;
        },
        .conflict => |id| blk: {
            const records = inputs.references orelse return error.InvalidRequiredAuthority;
            for (records.conflicts) |conflict| if (std.meta.eql(conflict.id, id)) break :blk .{ .conflict_claims = try orderedClaims(a, conflict.value.claim_ids) };
            return error.InvalidRequiredAuthority;
        },
        .record, .signal, .decision => .{ .regenerated = requirement },
    };
}

fn orderedClaims(a: std.mem.Allocator, claims: []const r.ClaimId) Error![]const r.ClaimId {
    const result = try a.dupe(r.ClaimId, claims);
    std.mem.sort(r.ClaimId, result, {}, struct {
        fn less(_: void, lhs: r.ClaimId, rhs: r.ClaimId) bool {
            return lhs.ordinal < rhs.ordinal;
        }
    }.less);
    return result;
}

fn retryScope(a: std.mem.Allocator, producer: Producer, feature: @import("feature_identity.zig").FeatureId, state: r.extraction.identity.StateId) Error![32]u8 {
    const scope = .{ .contract = @typeName(Family), .producer = producer, .feature = feature, .source_state = state };
    return (try atomic.snapshot(@TypeOf(scope), a, scope)).bytes;
}

pub fn retryPermit(a: std.mem.Allocator, producer: Producer, owner: @import("model_request_identity.zig").ImmutableUnitOwnerId, authorization: @import("model_request_identity.zig").RepairAuthorizationId, revision: u64, support: Support, selected: authority.Id, previous: ?retry.Permit) Error!retry.Permit {
    const records = support.inputs.references orelse return error.InvalidRequiredAuthority;
    var result = try atomic.permit(Subject, Family, a, owner, try subject(a, support.inputs, selected), .source_omission, authorization, revision, std.math.cast(u32, support.inputs.seeds.len) orelse return error.InvalidRequiredAuthority);
    result.key.scope = try retryScope(a, producer, support.inputs.feature, records.items.state_id);
    if (previous) |prior| if (std.mem.eql(u8, &prior.key.scope, &result.key.scope)) {
        result.maximum_targets = prior.maximum_targets;
    };
    return result;
}

/// The existing Source owner has already admitted this complete collection.
/// Reuse that proof without capturing fresh pipeline dependencies at Apply.
pub fn admittedValidation(a: std.mem.Allocator, permit: retry.Permit, admitted: @FieldType(@import("specification_support.zig").Source.Collection, "accepted")) Error!?retry.Transition {
    const inputs = admitted.inputs;
    if (!std.mem.eql(u8, &permit.key.family, &(try atomic.snapshot(Family, a, .source_omission)).bytes)) return null;
    const records = inputs.references orelse return error.InvalidRequiredAuthority;
    const matched_scope = for (std.meta.tags(Producer)) |producer| {
        if (std.mem.eql(u8, &permit.key.scope, &try retryScope(a, producer, inputs.feature, records.items.state_id))) break true;
    } else false;
    if (!matched_scope) return error.InvalidRequiredAuthority;
    const repaired_claims = admitted.candidate.omission_conflict_claims;
    if (repaired_claims.len != 0 and std.mem.eql(u8, &permit.key.target, &(try atomic.snapshot(Subject, a, .{ .conflict_claims = try orderedClaims(a, repaired_claims) })).bytes)) {
        var resolved = true;
        for (repaired_claims) |claim| {
            _ = try r.item(records.items, claim);
            var supported = false;
            for (inputs.evidence) |finding| if (finding.review) |review| {
                if (!r.contains(r.ClaimId, review.provenance.claim_ids, claim)) continue;
                if (finding.finding == .supported) supported = true else resolved = false;
            };
            if (!supported) resolved = false;
            for (records.conflicts) |conflict| if (r.contains(r.ClaimId, conflict.value.claim_ids, claim)) {
                resolved = false;
            };
        }
        return .{ .validated = .{ .permit = permit, .revision = std.math.add(u64, permit.revision, 1) catch return error.InvalidRequiredAuthority, .result = if (resolved) .resolved else .recurring } };
    }
    const ledger = try authority.build(a, inputs);
    const result = try authority.reconcile(a, ledger, try authority.buildObservations(a, ledger));
    const revision = std.math.add(u64, permit.revision, 1) catch return error.InvalidRequiredAuthority;
    for (result.entries) |entry| {
        const selected = try subject(a, inputs, entry.requirement);
        if (!std.mem.eql(u8, &permit.key.target, &(try atomic.snapshot(Subject, a, selected)).bytes)) continue;
        if (selected == .regenerated) break;
        const resolved = entry.candidate_defect == null and switch (entry.outcome) {
            .resolved_exactly_one, .resolved_explicit_not_applicable, .resolved_explicit_exception => true,
            .clarification_required, .upstream_rework_required, .administrative_block => false,
        };
        return .{ .validated = .{ .permit = permit, .revision = revision, .result = if (resolved) .resolved else .recurring } };
    }
    // A reused ordinal or removed subject cannot establish semantic progress.
    if (result.continuation == .all_resolved) return error.InvalidRequiredAuthority;
    return .{ .validated = .{ .permit = permit, .revision = revision, .result = .recurring } };
}

pub fn select(a: std.mem.Allocator, sources: r.evidence.Inputs, support: Support) Error!Evidence {
    var unreviewed = support.inputs;
    unreviewed.evidence = &.{};
    unreviewed.candidates = &.{};
    const checked = try @import("specification_support.zig").Source.validate(a, unreviewed, sources, support.review);
    if (checked != .accepted or !std.meta.eql(try @import("atomic_repair.zig").snapshot(authority.Inputs, a, checked.accepted.inputs), try @import("atomic_repair.zig").snapshot(authority.Inputs, a, support.inputs))) return error.InvalidRequiredAuthority;
    var unlocalized = false;
    for (support.result.entries) |entry| {
        const finding = (try authority.supportedOmission(a, support.inputs, support.observations, support.result, entry.requirement)) orelse continue;
        try @import("specification_support_evidence.zig").validate(a, support.inputs, sources, finding);
        for (support.review.review.entries) |review| if (review.requirement_ordinal == finding.id.ordinal) {
            if (review.value.loss == .unlocalized) {
                unlocalized = true;
                continue;
            }
            return .{ .finding = finding, .location = review.value.loss };
        };
    }
    return if (unlocalized) error.UnlocalizedSourceOmission else error.InvalidRequiredAuthority;
}

/// Diagnostic claims belong to the named producer, independently of whether
/// that producer's output is eligible as positive business content.
pub fn diagnosticClaims(records: @import("reference_support.zig").Records, location: Location) ?[]const r.ClaimId {
    return switch (location) {
        .unlocalized => null,
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
