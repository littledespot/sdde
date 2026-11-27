//! The repair authority a source omission grants: which producer may be repaired, the retry permit that
//! binds the repair, and the validation that discharges it. Vocabulary and validation stay in
//! `source_omission.zig`; the repair owners (extraction, reconciliation) consume this derivation, so it
//! imports neither of them.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const authority = @import("required_authority.zig");
const loss = @import("source_omission.zig");

/// Current runner facts, separate from the semantic assessment's projection.
/// Generation consumes source authority; later review cannot reopen producers.
pub fn requireRepairPhase(phase: @import("specification_generation_phase.zig").Phase) error{PostGenerationSourceRepairForbidden}!void {
    if (phase != .pre_generation) return error.PostGenerationSourceRepairForbidden;
}
pub const Support = struct { repair_phase: @import("specification_generation_phase.zig").Phase, review: @import("specification_support.zig").Source.Candidate, inputs: authority.Inputs, observations: authority.Observations, result: authority.Result };
pub const Error = authority.Error || r.Error || @import("specification_support.zig").Source.Error || error{ UnlocalizedSourceOmission, UnsupportedSourceOmission, PostGenerationSourceRepairForbidden };
const retry = @import("workflow_retry.zig");
const atomic = @import("atomic_repair.zig");
pub const Producer = enum { extraction, reconciliation };
const Family = enum { source_omission };
const Subject = union(enum) { requirement: authority.Id, token: r.extraction.tokens.CandidateId, signal_claims: []const r.ClaimId, conflict_claims: []const r.ClaimId };

fn subject(a: std.mem.Allocator, inputs: authority.Inputs, requirement: authority.Id) authority.Error!Subject {
    return switch (requirement.unit) {
        .feature, .source => .{ .requirement = requirement },
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
        .signal => |id| blk: {
            const records = inputs.references orelse return error.InvalidRequiredAuthority;
            for (records.signals) |signal| if (std.meta.eql(signal.id, id)) break :blk .{ .signal_claims = try orderedClaims(a, signal.value.claim_ids) };
            return error.InvalidRequiredAuthority;
        },
        .record, .decision => error.InvalidRequiredAuthority,
    };
}

fn orderedClaims(a: std.mem.Allocator, claims: []const r.ClaimId) std.mem.Allocator.Error![]const r.ClaimId {
    const result = try a.dupe(r.ClaimId, claims);
    std.mem.sort(r.ClaimId, result, {}, struct {
        fn less(_: void, lhs: r.ClaimId, rhs: r.ClaimId) bool {
            return lhs.ordinal < rhs.ordinal;
        }
    }.less);
    return result;
}

fn retryScope(a: std.mem.Allocator, producer: Producer, feature: @import("feature_identity.zig").FeatureId, state: r.extraction.identity.StateId, projection: authority.Projection) authority.Error![32]u8 {
    switch (projection) {
        .source_readiness, .source_preservation => {},
        .registered_obligations => return error.InvalidRequiredAuthority,
    }
    const scope = .{ .contract = @typeName(Family), .producer = producer, .feature = feature, .source_state = state, .projection = projection };
    return (try atomic.snapshot(@TypeOf(scope), a, scope)).bytes;
}

/// A pending source repair retains its original required review purpose. Ready
/// references alone cannot discharge that dependent semantic validation.
pub fn pendingReview(a: std.mem.Allocator, permit: retry.Permit, feature: @import("feature_identity.zig").FeatureId, state: r.extraction.identity.StateId) authority.Error!?authority.Projection {
    if (!std.mem.eql(u8, &permit.key.family, &(try atomic.snapshot(Family, a, .source_omission)).bytes)) return null;
    for ([_]authority.Projection{ .source_readiness, .source_preservation }) |projection| {
        for (std.meta.tags(Producer)) |producer| {
            if (std.mem.eql(u8, &permit.key.scope, &try retryScope(a, producer, feature, state, projection))) return projection;
        }
    }
    return error.InvalidRequiredAuthority;
}

/// The pass of the review that validates a pending repair of `projection`: a source-readiness
/// repair is validated by the dependent pass, which covers all it could have touched; a
/// source-preservation projection has one pass.
fn passFor(projection: authority.Projection) authority.Pass {
    return if (projection == .source_readiness) .dependent else .first;
}

/// The review pass a source-readiness projection serves: the pass that validates the pending
/// repair while one is pending, otherwise `first`.
pub fn reviewPass(a: std.mem.Allocator, permit: ?retry.Permit, feature: @import("feature_identity.zig").FeatureId, state: r.extraction.identity.StateId) authority.Error!authority.Pass {
    const pending = (try pendingReview(a, permit orelse return .first, feature, state)) orelse return .first;
    return passFor(pending);
}

/// Each native scope freezes its finite target population at first authorization (22-repair.md,
/// "Each native scope freezes"). A source-readiness scope is shared by every pass over one source
/// state, so its population is the full projection's seed count whichever pass authorizes first.
fn targetPopulation(a: std.mem.Allocator, inputs: authority.Inputs) authority.Error!u32 {
    const seeds = if (inputs.projection == .source_readiness)
        (try @import("specification_authority.zig").projectRecords(a, inputs.feature, inputs.references orelse return error.InvalidRequiredAuthority, .dependent)).seeds.len
    else
        inputs.seeds.len;
    return std.math.cast(u32, seeds) orelse error.InvalidRequiredAuthority;
}

pub fn retryPermit(a: std.mem.Allocator, producer: Producer, owner: @import("model_request_identity.zig").ImmutableUnitOwnerId, authorization: @import("model_request_identity.zig").RepairAuthorizationId, revision: u64, support: Support, selected: authority.Id, previous: ?retry.Permit) Error!retry.Permit {
    try requireRepairPhase(support.repair_phase);
    const records = support.inputs.references orelse return error.InvalidRequiredAuthority;
    var result = try atomic.permit(Subject, Family, a, owner, try subject(a, support.inputs, selected), .source_omission, authorization, revision, try targetPopulation(a, support.inputs));
    result.key.scope = try retryScope(a, producer, support.inputs.feature, records.items.state_id, support.inputs.projection);
    if (previous) |prior| if (std.mem.eql(u8, &prior.key.scope, &result.key.scope)) {
        result.maximum_targets = prior.maximum_targets;
    };
    return result;
}

/// The existing Source owner has already admitted this complete collection.
/// Reuse that proof without capturing fresh pipeline dependencies at Apply.
pub fn admittedValidation(a: std.mem.Allocator, permit: retry.Permit, admitted: @FieldType(@import("specification_support.zig").Source.Collection, "accepted")) authority.Error!?retry.Transition {
    const inputs = admitted.inputs;
    const records = inputs.references orelse return error.InvalidRequiredAuthority;
    const projection = (try pendingReview(a, permit, inputs.feature, records.items.state_id)) orelse return null;
    if (projection != inputs.projection) return error.InvalidRequiredAuthority;
    // The review must be the pass that validates this repair. This sits before the conflict-group branch,
    // which returns before `authority.build` re-derives the projection.
    if (inputs.pass != passFor(projection)) return error.InvalidRequiredAuthority;
    const repaired_claims = admitted.candidate.omission_conflict_claims;
    if (repaired_claims.len != 0 and std.mem.eql(u8, &permit.key.target, &(try atomic.snapshot(Subject, a, .{ .conflict_claims = try orderedClaims(a, repaired_claims) })).bytes)) {
        var resolved = true;
        for (repaired_claims) |claim| {
            _ = r.item(records.items, claim) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidRequiredAuthority;
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

pub fn select(a: std.mem.Allocator, sources: r.evidence.Inputs, support: Support) Error!loss.Evidence {
    var unreviewed = support.inputs;
    unreviewed.evidence = &.{};
    unreviewed.candidates = &.{};
    const checked = try @import("specification_support.zig").Source.validate(a, unreviewed, sources, support.review);
    if (checked != .accepted or !std.meta.eql(try @import("atomic_repair.zig").snapshot(authority.Inputs, a, checked.accepted.inputs), try @import("atomic_repair.zig").snapshot(authority.Inputs, a, support.inputs))) return error.InvalidRequiredAuthority;
    var unlocalized = false;
    var unsupported = false;
    for (support.result.entries) |entry| {
        const finding = (try authority.supportedOmission(a, support.inputs, support.observations, support.result, entry.requirement)) orelse continue;
        try @import("specification_support_evidence.zig").validate(a, support.inputs, sources, finding);
        for (support.review.review.entries) |review| if (review.requirement_ordinal == finding.id.ordinal) {
            if (review.value.loss == .source_association or review.value.loss == .unsupported_summary) {
                unsupported = true;
                continue;
            }
            if (!loss.isUpstream(review.value.loss)) {
                unlocalized = true;
                continue;
            }
            return .{ .finding = finding, .location = review.value.loss };
        };
    }
    return if (unsupported) error.UnsupportedSourceOmission else if (unlocalized) error.UnlocalizedSourceOmission else error.InvalidRequiredAuthority;
}
