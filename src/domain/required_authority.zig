//! Shared execution-local authority accounting. Evidence identity/currentness is
//! mechanical; a semantic finding remains model-assisted, never proof of truth.
//! Allocated projections borrow their inputs and use a caller-owned arena.
const std = @import("std");
pub const Stage = @import("clarification_inputs.zig").Stage;
pub const DetectionStage = enum { spec, plan, tasks, implement, recovery };
pub const Error = std.mem.Allocator.Error || error{InvalidRequiredAuthority};
pub const version: u32 = 1;
pub const Kind = enum { feature_intent, reference_meaning, entity_applicability, preservation, design_decision, executable_decomposition, policy_predicate };
pub const Slot = enum { display_name, description, primary_goal, primary_user_story, acceptance_criteria, functional_requirements, scenario_coverage, text, given, when, then, condition, expected_outcome, name, business_meaning, relationship, entities, disposition, value, decision, compliance };
pub const Unit = union(enum) {
    feature: enum { singleton },
    record: @import("specification.zig").Id,
    signal: @import("reference_reconciliation.zig").SignalId,
    conflict: @import("reference_reconciliation.zig").ConflictId,
    token: @import("structured_tokens.zig").Id,
    decision: struct { ordinal: u32 },
};
pub const Id = struct { kind: Kind, unit: Unit, slot: Slot, member: u32 = 0, contract_version: u32 = version };
pub const Authority = @import("authority_identity.zig").Authority;
pub const EvidenceId = struct { ordinal: u32 };
pub const CandidateId = struct { ordinal: u32, revision: u64 };
pub const Candidate = struct { id: CandidateId, requirement: Id };
pub const ExceptionId = struct { ordinal: u32 };
pub const Rule = enum { no_business_data, authenticated_exact_scope };
pub const Requiredness = union(enum) {
    schema: enum { specification },
    obligation: enum { reference_accounting, exact_preservation },
    policy: enum { design, decomposition, compliance },
    accepted_authority: Authority,
};
/// Produced by native schema/policy/obligation projections, never parsed from a
/// model or configurable requiredness list. The registry owns all permissions.
pub const Seed = struct { id: Id, requiredness: Requiredness, input_authorities: []const Authority };
pub const Policy = struct { owner: Stage, not_applicable: ?Rule = null, exception: ?Rule = null };

pub fn policy(id: Id) ?Policy {
    if (id.contract_version != version) return null;
    return switch (id.kind) {
        .feature_intent => switch (id.unit) {
            .feature => switch (id.slot) {
                .display_name, .description, .primary_goal, .primary_user_story, .acceptance_criteria, .functional_requirements, .scenario_coverage => .{ .owner = .spec },
                else => null,
            },
            .record => |record| if (record.ordinal != 0 and recordField(record.kind, id.slot)) .{ .owner = .spec } else null,
            else => null,
        },
        .entity_applicability => if (id.unit == .feature and id.slot == .entities) .{ .owner = .spec, .not_applicable = .no_business_data } else null,
        .reference_meaning => if ((id.unit == .signal or id.unit == .conflict) and id.slot == .disposition) .{ .owner = .spec } else null,
        .preservation => if (id.unit == .token and id.slot == .value) .{ .owner = .spec } else null,
        .design_decision => if (id.unit == .decision and id.slot == .decision) .{ .owner = .plan } else null,
        .executable_decomposition => if (id.unit == .decision and id.slot == .decision) .{ .owner = .tasks } else null,
        .policy_predicate => if (id.unit == .decision and id.slot == .compliance) .{ .owner = .plan, .exception = .authenticated_exact_scope } else null,
    };
}

fn recordField(kind: @import("specification.zig").Kind, slot: Slot) bool {
    const Content = @import("specification.zig").Content(@import("specification.zig").BusinessValue);
    switch (kind) {
        inline else => |tag| inline for (@typeInfo(@FieldType(Content, @tagName(tag))).@"struct".fields) |field| {
            const name = if (comptime std.mem.eql(u8, field.name, "relationships")) "relationship" else field.name;
            if (std.mem.eql(u8, @tagName(slot), name)) return true;
        },
    }
    return false;
}

pub const Resolution = union(enum) { existing_authority: Authority, supported_candidate: CandidateId, not_applicable: Rule, exception: ExceptionId };
/// Native, scope-checked evidence supplied by an owning validator/reviewer.
/// Observation JSON can reference these IDs but cannot create this registry.
pub const Evidence = struct {
    id: EvidenceId,
    requirement: Id,
    authorities: []const Authority,
    resolution: Resolution,
    finding: enum { supported, ambiguous, conflicting, unsupported },
    method: enum { deterministic, model_assisted },
    reference_support: []const union(enum) { signal: @import("reference_reconciliation.zig").SignalId, conflict: @import("reference_reconciliation.zig").ConflictId } = &.{},
};
pub const Exception = struct { id: ExceptionId, requirement: Id, authority: Authority, authenticated_actor_ordinal: u64 };
pub const ForcedGap = struct { requirement: Id, reason: GapReason };
pub const Inputs = struct {
    feature: @import("feature_identity.zig").FeatureId,
    projection: enum { specification, registered_obligations } = .registered_obligations,
    specification: ?@import("specification.zig").IdentifiedContent = null,
    brief: ?@import("specification.zig").Brief = null,
    detected_at: DetectionStage,
    authorities: []const Authority,
    seeds: []const Seed,
    evidence: []const Evidence,
    candidates: []const Candidate = &.{},
    exceptions: []const Exception = &.{},
    forced_gaps: []const ForcedGap = &.{},
    references: ?@import("reference_reconciliation.zig").Accounted = null,
};
pub const Requirement = struct { seed: Seed, registered_policy: ?Policy };
pub const Ledger = struct { inputs: Inputs, requirements: []const Requirement };
pub const Observation = struct { requirement: Id, inspected_authorities: []const Authority, evidence_ids: []const EvidenceId };
pub const Observations = struct { entries: []const Observation };
pub const GapReason = enum { missing, ambiguous, conflicting, multiple_non_equivalent, stale, unsupported, unregistered_ownership_or_policy };
pub const Gap = struct { owner: Stage, reason: GapReason };
pub const BlockReason = enum { unregistered_ownership_or_policy, unauthorized_authority_creation };
pub const Outcome = union(enum) {
    resolved_exactly_one: Resolution,
    resolved_explicit_not_applicable: Rule,
    resolved_explicit_exception: ExceptionId,
    clarification_required: Gap,
    upstream_rework_required: struct { owner: Stage, detected_at: DetectionStage, reason: GapReason },
    administrative_block: BlockReason,
};
pub const Entry = struct { requirement: Id, outcome: Outcome, evidence_ids: []const EvidenceId, input_authorities: []const Authority };
pub const Result = struct { feature: @import("feature_identity.zig").FeatureId, entries: []const Entry, continuation: enum { all_resolved, needs_user, blocked } };

pub fn build(allocator: std.mem.Allocator, inputs: Inputs) Error!Ledger {
    if (@import("feature_identity.zig").FeatureId.parse(inputs.feature.bytes) == null) return error.InvalidRequiredAuthority;
    if (inputs.projection == .specification) {
        const expected = try @import("specification_authority.zig").project(allocator, inputs.feature, inputs.references orelse return error.InvalidRequiredAuthority, inputs.specification, inputs.brief);
        if (expected.seeds.len != inputs.seeds.len) return error.InvalidRequiredAuthority;
        for (expected.seeds, inputs.seeds) |required, actual| {
            if (!std.meta.eql(required.id, actual.id) or !std.meta.eql(required.requiredness, actual.requiredness)) return error.InvalidRequiredAuthority;
            try sameSet(Authority, required.input_authorities, actual.input_authorities);
        }
        try sameSet(ForcedGap, expected.forced_gaps, inputs.forced_gaps);
    }
    try unique(Authority, inputs.authorities);
    for (inputs.authorities, 0..) |authority, index| {
        if (!authority.valid()) return error.InvalidRequiredAuthority;
        for (inputs.authorities[0..index]) |other| {
            if (other == .canonical and authority == .canonical and other.canonical.kind == authority.canonical.kind and other.canonical.ordinal == authority.canonical.ordinal) return error.InvalidRequiredAuthority;
        }
    }
    const requirements = try allocator.alloc(Requirement, inputs.seeds.len);
    for (inputs.seeds, requirements, 0..) |seed, *requirement, index| {
        if (!validId(seed.id)) return error.InvalidRequiredAuthority;
        for (inputs.seeds[0..index]) |other| if (std.meta.eql(other.id, seed.id)) return error.InvalidRequiredAuthority;
        try unique(Authority, seed.input_authorities);
        for (seed.input_authorities) |authority| if (!authority.valid()) return error.InvalidRequiredAuthority;
        const registered = policy(seed.id);
        if (registered != null and !validRequiredness(seed)) return error.InvalidRequiredAuthority;
        requirement.* = .{ .seed = seed, .registered_policy = registered };
    }
    // Requirement identity, not candidate/model order, determines output order.
    std.mem.sort(Requirement, requirements, {}, lessRequirement);
    for (inputs.evidence, 0..) |evidence, index| {
        if (evidence.id.ordinal == 0 or findRequirement(requirements, evidence.requirement) == null) return error.InvalidRequiredAuthority;
        for (inputs.evidence[0..index]) |other| if (std.meta.eql(other.id, evidence.id)) return error.InvalidRequiredAuthority;
        try unique(Authority, evidence.authorities);
    }
    for (inputs.exceptions, 0..) |exception, index| {
        if (exception.id.ordinal == 0 or findRequirement(requirements, exception.requirement) == null) return error.InvalidRequiredAuthority;
        for (inputs.exceptions[0..index]) |other| if (std.meta.eql(other.id, exception.id)) return error.InvalidRequiredAuthority;
    }
    for (inputs.candidates, 0..) |candidate, index| {
        if (candidate.id.ordinal == 0 or candidate.id.revision == 0 or findRequirement(requirements, candidate.requirement) == null) return error.InvalidRequiredAuthority;
        for (inputs.candidates[0..index]) |other| if (other.id.ordinal == candidate.id.ordinal) return error.InvalidRequiredAuthority;
    }
    for (inputs.forced_gaps, 0..) |gap, index| {
        if (findRequirement(requirements, gap.requirement) == null) return error.InvalidRequiredAuthority;
        for (inputs.forced_gaps[0..index]) |other| if (std.meta.eql(other.requirement, gap.requirement)) return error.InvalidRequiredAuthority;
    }
    return .{ .inputs = inputs, .requirements = requirements };
}

pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) Error!Observations {
    return @import("strict_json.zig").decode(Observations, allocator, bytes, .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth }) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidJsonDocument => error.InvalidRequiredAuthority,
    };
}

pub fn reconcile(allocator: std.mem.Allocator, ledger: Ledger, observations: Observations) Error!Result {
    if (ledger.requirements.len != observations.entries.len) return error.InvalidRequiredAuthority;
    for (observations.entries, 0..) |observation, index| {
        if (findRequirement(ledger.requirements, observation.requirement) == null) return error.InvalidRequiredAuthority;
        for (observations.entries[0..index]) |other| if (std.meta.eql(other.requirement, observation.requirement)) return error.InvalidRequiredAuthority;
    }
    const entries = try allocator.alloc(Entry, ledger.requirements.len);
    var result: Result = .{ .feature = ledger.inputs.feature, .entries = entries, .continuation = .all_resolved };
    for (ledger.requirements, entries) |requirement, *entry| {
        const observation = for (observations.entries) |value| {
            if (std.meta.eql(value.requirement, requirement.seed.id)) break value;
        } else return error.InvalidRequiredAuthority;
        try sameSet(Authority, requirement.seed.input_authorities, observation.inspected_authorities);
        try unique(EvidenceId, observation.evidence_ids);
        var expected_count: usize = 0;
        for (ledger.inputs.evidence) |evidence| {
            if (!std.meta.eql(evidence.requirement, requirement.seed.id)) continue;
            expected_count += 1;
            if (!contains(EvidenceId, observation.evidence_ids, evidence.id)) return error.InvalidRequiredAuthority;
        }
        if (observation.evidence_ids.len != expected_count) return error.InvalidRequiredAuthority;
        const evidence_ids = try allocator.dupe(EvidenceId, observation.evidence_ids);
        std.mem.sort(EvidenceId, evidence_ids, {}, struct {
            fn less(_: void, a: EvidenceId, b: EvidenceId) bool {
                return a.ordinal < b.ordinal;
            }
        }.less);
        const outcome = try resolve(requirement, ledger.inputs);
        entry.* = .{ .requirement = requirement.seed.id, .outcome = outcome, .evidence_ids = evidence_ids, .input_authorities = requirement.seed.input_authorities };
        switch (outcome) {
            .resolved_exactly_one, .resolved_explicit_exception, .resolved_explicit_not_applicable => {},
            .clarification_required => if (result.continuation == .all_resolved) {
                result.continuation = .needs_user;
            },
            .upstream_rework_required, .administrative_block => result.continuation = .blocked,
        }
    }
    return result;
}

fn resolve(requirement: Requirement, inputs: Inputs) Error!Outcome {
    const registered = requirement.registered_policy orelse return .{ .administrative_block = .unregistered_ownership_or_policy };
    const seed = requirement.seed;
    for (seed.input_authorities) |authority| if (!contains(Authority, inputs.authorities, authority)) return route(inputs.detected_at, registered.owner, .stale);
    for (inputs.forced_gaps) |gap| if (std.meta.eql(gap.requirement, seed.id)) return route(inputs.detected_at, registered.owner, gap.reason);
    var resolution: ?Resolution = null;
    var reason: ?GapReason = null;
    for (inputs.evidence) |evidence| {
        if (!std.meta.eql(evidence.requirement, seed.id)) continue;
        if (evidence.authorities.len == 0) reason = stronger(reason, .unsupported);
        for (evidence.authorities) |authority| {
            if (!contains(Authority, seed.input_authorities, authority)) reason = stronger(reason, .unsupported);
            if (!contains(Authority, inputs.authorities, authority)) reason = stronger(reason, .stale);
        }
        if (evidence.reference_support.len != 0) {
            const references = inputs.references orelse return error.InvalidRequiredAuthority;
            const state = references.records.assignments.checked.prior.prior.input.progress.plan.layout.items.state_id;
            if (!contains(Authority, evidence.authorities, .{ .reference = state })) reason = stronger(reason, .stale);
            for (evidence.reference_support, 0..) |support, index| {
                for (evidence.reference_support[0..index]) |previous| if (std.meta.eql(previous, support)) return error.InvalidRequiredAuthority;
                switch (support) {
                    .signal => |id| {
                        for (references.records.signals) |signal| {
                            if (std.meta.eql(signal.id, id)) break;
                        } else return error.InvalidRequiredAuthority;
                    },
                    .conflict => |id| {
                        for (references.records.conflicts) |conflict| {
                            if (std.meta.eql(conflict.id, id)) break;
                        } else return error.InvalidRequiredAuthority;
                        reason = stronger(reason, .conflicting);
                    },
                }
            }
        }
        switch (evidence.finding) {
            .supported => {},
            .ambiguous => reason = stronger(reason, .ambiguous),
            .conflicting => reason = stronger(reason, .conflicting),
            .unsupported => reason = stronger(reason, .unsupported),
        }
        switch (evidence.resolution) {
            .existing_authority => |authority| if (!contains(Authority, evidence.authorities, authority)) {
                reason = stronger(reason, .unsupported);
            },
            .supported_candidate => |candidate| if (!contains(Candidate, inputs.candidates, .{ .id = candidate, .requirement = seed.id })) {
                reason = stronger(reason, .stale);
            },
            .not_applicable => |rule| if (registered.not_applicable != rule) {
                reason = stronger(reason, .unsupported);
            },
            .exception => |id| {
                if (registered.exception != .authenticated_exact_scope) return .{ .administrative_block = .unauthorized_authority_creation };
                const exception = for (inputs.exceptions) |value| {
                    if (std.meta.eql(value.id, id)) break value;
                } else return .{ .administrative_block = .unauthorized_authority_creation };
                if (!std.meta.eql(exception.requirement, seed.id) or exception.authenticated_actor_ordinal == 0 or !contains(Authority, evidence.authorities, exception.authority)) return .{ .administrative_block = .unauthorized_authority_creation };
            },
        }
        if (resolution) |previous| {
            // Only direct identity/revision equality is a registered equivalence.
            // Every equivalent member's evidence is retained in the result.
            if (!sameResolution(previous, evidence.resolution)) reason = stronger(reason, .multiple_non_equivalent);
        } else resolution = evidence.resolution;
    }
    if (reason) |gap| return route(inputs.detected_at, registered.owner, gap);
    const value = resolution orelse return route(inputs.detected_at, registered.owner, .missing);
    return switch (value) {
        .existing_authority, .supported_candidate => .{ .resolved_exactly_one = value },
        .not_applicable => |rule| .{ .resolved_explicit_not_applicable = rule },
        .exception => |id| .{ .resolved_explicit_exception = id },
    };
}

pub fn route(stage: DetectionStage, owner: Stage, reason: GapReason) Outcome {
    if (reason == .unregistered_ownership_or_policy) return .{ .administrative_block = .unregistered_ownership_or_policy };
    if (stage == .recovery or @intFromEnum(stage) > @intFromEnum(owner)) return .{ .upstream_rework_required = .{ .owner = owner, .detected_at = stage, .reason = reason } };
    return .{ .clarification_required = .{ .owner = owner, .reason = reason } };
}

/// Rebuild from current native inputs; a prior ledger/result cannot certify a
/// newer revision. Callers get a decision, never a repaired/defaulted result.
pub fn validate(allocator: std.mem.Allocator, inputs: Inputs, observations: Observations, result: Result) Error!bool {
    const current = try reconcile(allocator, try build(allocator, inputs), observations);
    if (!std.mem.eql(u8, current.feature.bytes, result.feature.bytes) or current.continuation != result.continuation or current.entries.len != result.entries.len) return error.InvalidRequiredAuthority;
    for (current.entries, result.entries) |expected, actual| {
        if (!std.meta.eql(expected.requirement, actual.requirement) or !sameOutcome(expected.outcome, actual.outcome)) return error.InvalidRequiredAuthority;
        try sameSet(EvidenceId, expected.evidence_ids, actual.evidence_ids);
        try sameSet(Authority, expected.input_authorities, actual.input_authorities);
    }
    return current.continuation == .all_resolved;
}

fn validRequiredness(seed: Seed) bool {
    return switch (seed.requiredness) {
        .schema => seed.id.kind == .feature_intent or seed.id.kind == .entity_applicability,
        .obligation => |rule| switch (rule) {
            .reference_accounting => seed.id.kind == .reference_meaning,
            .exact_preservation => seed.id.kind == .preservation,
        },
        .policy => |rule| switch (rule) {
            .design => seed.id.kind == .design_decision,
            .decomposition => seed.id.kind == .executable_decomposition,
            .compliance => seed.id.kind == .policy_predicate,
        },
        .accepted_authority => |authority| contains(Authority, seed.input_authorities, authority),
    };
}
fn validId(id: Id) bool {
    if (id.member != 0 and id.slot != .relationship) return false;
    if (id.slot == .relationship and id.member == 0) return false;
    return switch (id.unit) {
        .feature => true,
        .record => |record| record.ordinal != 0,
        inline .signal, .conflict, .token, .decision => |value| value.ordinal != 0,
    };
}
fn findRequirement(requirements: []const Requirement, id: Id) ?Requirement {
    for (requirements) |requirement| if (std.meta.eql(requirement.seed.id, id)) return requirement;
    return null;
}
fn stronger(prior: ?GapReason, next: GapReason) GapReason {
    return if (prior == null or @intFromEnum(next) > @intFromEnum(prior.?)) next else prior.?;
}
fn lessRequirement(_: void, a: Requirement, b: Requirement) bool {
    const left = a.seed.id;
    const right = b.seed.id;
    if (left.kind != right.kind) return @intFromEnum(left.kind) < @intFromEnum(right.kind);
    if (@as(std.meta.Tag(Unit), left.unit) != @as(std.meta.Tag(Unit), right.unit)) return @intFromEnum(left.unit) < @intFromEnum(right.unit);
    const x = unitOrdinal(left.unit);
    const y = unitOrdinal(right.unit);
    if (x != y) return x < y;
    if (left.slot != right.slot) return @intFromEnum(left.slot) < @intFromEnum(right.slot);
    if (left.member != right.member) return left.member < right.member;
    return left.contract_version < right.contract_version;
}
fn unitOrdinal(unit: Unit) u64 {
    return switch (unit) {
        .feature => 0,
        .record => |id| (@as(u64, @intFromEnum(id.kind)) << 32) | id.ordinal,
        inline .signal, .conflict, .token, .decision => |id| id.ordinal,
    };
}
pub fn contains(comptime T: type, list: []const T, value: T) bool {
    for (list) |item| if (if (T == Authority) item.eql(value) else std.meta.eql(item, value)) return true;
    return false;
}
fn sameResolution(a: Resolution, b: Resolution) bool {
    if (@as(std.meta.Tag(Resolution), a) != @as(std.meta.Tag(Resolution), b)) return false;
    return switch (a) {
        .existing_authority => |authority| authority.eql(b.existing_authority),
        else => std.meta.eql(a, b),
    };
}
fn sameOutcome(a: Outcome, b: Outcome) bool {
    if (@as(std.meta.Tag(Outcome), a) != @as(std.meta.Tag(Outcome), b)) return false;
    return switch (a) {
        .resolved_exactly_one => |resolution| sameResolution(resolution, b.resolved_exactly_one),
        else => std.meta.eql(a, b),
    };
}
fn unique(comptime T: type, list: []const T) Error!void {
    for (list, 0..) |item, index| if (contains(T, list[0..index], item)) return error.InvalidRequiredAuthority;
}
fn sameSet(comptime T: type, a: []const T, b: []const T) Error!void {
    try unique(T, a);
    try unique(T, b);
    if (a.len != b.len) return error.InvalidRequiredAuthority;
    for (a) |item| if (!contains(T, b, item)) return error.InvalidRequiredAuthority;
}
