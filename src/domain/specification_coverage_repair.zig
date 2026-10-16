//! Repairs of source-backed omissions in a completed specification. Native
//! exact-copy reconstruction and reviewed omissions share the same edit contract.
const std = @import("std");
const sessions = @import("specification_session.zig");
const g = @import("specification_generation.zig");
const coverage = @import("specification_coverage.zig");
const candidates = @import("specification_candidate.zig");
const p = @import("specification_provenance.zig");
const r = @import("reference_reconciliation.zig");
const shared = @import("atomic_repair.zig");
const authority = @import("required_authority.zig");
const descriptions = @import("required_authority_description.zig");
const retry = @import("workflow_retry.zig");
const RepairSubject = union(enum) { requirement: authority.Id };
pub const Support = struct { inputs: authority.Inputs, observations: authority.Observations, result: authority.Result };
pub const Facts = struct {
    support: ?Support = null,
    session: sessions.Session,
    candidate: g.spec.IdentifiedContent,
    references: p.Dependencies,
};
pub const Target = struct {
    unit: usize,
    part: union(enum) { value: struct { subject: candidates.Subject, field: candidates.ValueField }, record: usize },
    pub fn guidance(self: Target) union(enum) { value: @FieldType(@FieldType(Target, "part"), "value"), record } {
        return switch (self.part) {
            .value => |value| .{ .value = value },
            .record => .record,
        };
    }
};
pub const Replacement = union(enum) { value: g.spec.BusinessValue, record: g.spec.Model.RecordProposal };
const Rule = union(enum) {
    omission: authority.Evidence,
    pub fn guidance(self: @This()) union(enum) { omission: authority.ReviewEvidence } {
        return switch (self) {
            .omission => |value| .{ .omission = value.review.? },
        };
    }
};
const atomic = shared.Contract(Target, Replacement, Facts, Rule);
pub const Authorization = atomic.Authorization;
pub const ModelRepair = struct { authorization: Authorization, response: ?struct { value: Replacement, origin: @import("model_candidate_origin.zig").Origin } = null };
pub const Decision = union(enum) { blocked: coverage.Rejection };
pub const Error = sessions.Error || atomic.Error || candidates.Error || authority.Error || coverage.Error || @import("specification_support.zig").Source.Error || error{ InvalidSpecificationCoverageRepair, UnsafeSpecificationOmissionRepair };

pub fn capture(a: std.mem.Allocator, current: sessions.Session, context: p.Context, candidate: g.spec.IdentifiedContent) Error!Facts {
    if (current.completed != sessions.unit_count or !current.reference_state.eql(context.inputs.corpus.state_id)) return error.InvalidSpecificationCoverageRepair;
    return .{ .session = current, .candidate = candidate, .references = try p.dependencies(a, context) };
}
pub fn stamp(a: std.mem.Allocator, current: sessions.Session, context: p.Context, candidate: g.spec.IdentifiedContent) Error!shared.Snapshot {
    const facts = try capture(a, current, context, candidate);
    defer a.free(facts.references.lineage.history);
    return shared.snapshot(Facts, a, facts);
}
pub fn authorize(a: std.mem.Allocator, current: sessions.Session, context: p.Context, candidate: g.spec.IdentifiedContent, rejection: coverage.Rejection) Error!Decision {
    const facts = try capture(a, current, context, candidate);
    defer a.free(facts.references.lineage.history);
    if (rejection.revision != current.revision or !std.meta.eql(rejection.dependencies orelse return error.InvalidSpecificationCoverageRepair, try shared.snapshot(Facts, a, facts))) return error.InvalidSpecificationCoverageRepair;
    // A whole-field literal-to-insertion replacement would discard the prose
    // required by every behavioral obligation field. Native code cannot invent
    // that missing meaning or treat an incidental identity label as coverage.
    var blocked = rejection;
    blocked.blocked = .no_independent_supported_target;
    return .{ .blocked = blocked };
}

fn reviewedFacts(a: std.mem.Allocator, current: sessions.Session, context: p.Context, candidate: g.spec.IdentifiedContent, support: Support) Error!Facts {
    try checkReviewedCandidate(a, current, candidate, support.inputs);
    _ = try authority.validate(a, support.inputs, support.observations, support.result);
    var facts = try capture(a, current, context, candidate);
    facts.support = support;
    return facts;
}
/// Native authorization rejection; retained evidence names the reviewed work that
/// could not be authorized. It grants neither a target nor permission to repair.
pub const AuthorizationRejection = struct {
    reason: @import("operation_error.zig").Code(Error),
    revision: u64,
    outstanding_requirements: []const authority.Entry,
    review_origin: ?@import("model_candidate_origin.zig").Origin,
    targets: []const TargetAssessment,
};

/// Observations from the actual authorization attempt, never a second permission
/// calculation. Unchecked targets retain no derived owner or producer.
pub const TargetAssessment = struct {
    requirement: authority.Id,
    reason: enum { not_checked, invalid_evidence, no_supported_omission, upstream_owner, unsupported_owner, missing_claim_evidence, unsupported_target, incompatible_record_binding, claim_evidence_mismatch, citation_evidence_mismatch, authorized } = .not_checked,
    owner: ?@import("source_omission.zig").Location = null,
    target: ?Target = null,
    reviewed_provenance: ?g.spec.Provenance = null,
    target_provenance: ?g.spec.Provenance = null,
    target_origin: ?@import("model_candidate_origin.zig").Origin = null,
    finding_origin: ?@import("model_candidate_origin.zig").Origin = null,
    comparison_origin: ?@import("model_candidate_origin.zig").Origin = null,
};
/// Initialize once per attempt. The caller owns targets; its evidence slices
/// borrow the same inputs/arena as the authorization. Copy before their release.
pub const AuthorizationTrace = struct { targets: []TargetAssessment = &.{} };

pub fn authorizationRejection(a: std.mem.Allocator, support: Support, trace: AuthorizationTrace, cause: Error) std.mem.Allocator.Error!AuthorizationRejection {
    var outstanding: std.ArrayList(authority.Entry) = .empty;
    for (support.result.entries) |entry| if (entry.candidate_defect != null) {
        try outstanding.append(a, entry);
    };
    return .{
        .reason = @import("operation_error.zig").code(Error, cause),
        .revision = support.inputs.revision,
        .outstanding_requirements = try outstanding.toOwnedSlice(a),
        .review_origin = support.inputs.review_origin,
        .targets = trace.targets,
    };
}

/// Only a current, shared-classified omission may select a native content slot.
/// No coverage row, source record or review verdict is a repair target.
pub fn authorizeOmission(a: std.mem.Allocator, validator: @import("typed_text.zig").Validator, current: sessions.Session, context: p.Context, candidate: g.spec.IdentifiedContent, support: Support, trace: *AuthorizationTrace) Error!Authorization {
    var count: usize = 0;
    for (support.result.entries) |entry| if (entry.candidate_defect != null) {
        count += 1;
    };
    trace.targets = try a.alloc(TargetAssessment, count);
    var index: usize = 0;
    for (support.result.entries) |entry| if (entry.candidate_defect != null) {
        trace.targets[index] = .{ .requirement = entry.requirement };
        index += 1;
    };
    const rebuilt = try sessions.assemble(a, validator, context, current);
    if (!try g.spec.sameContent(a, rebuilt.content, candidate)) return error.InvalidSpecificationCoverageRepair;
    const facts = try reviewedFacts(a, current, context, candidate, support);
    defer a.free(facts.references.lineage.history);
    for (trace.targets) |*assessment| {
        assessment.reason = .invalid_evidence;
        const evidence = (try authority.supportedOmission(a, support.inputs, support.observations, support.result, assessment.requirement)) orelse {
            assessment.reason = .no_supported_omission;
            continue;
        };
        for (support.inputs.evidence, 0..) |item, evidence_index| if (std.meta.eql(item.id, evidence.id)) {
            if (evidence_index < support.inputs.review_origins.len) assessment.finding_origin = support.inputs.review_origins[evidence_index];
            break;
        };
        if (evidence.review) |review| if (review.preservation) |proof| {
            assessment.comparison_origin = proof.origin;
        };
        try @import("specification_support_evidence.zig").validate(a, support.inputs, context.inputs, evidence);
        assessment.reviewed_provenance = evidence.review.?.provenance;
        assessment.owner = evidence.review.?.loss orelse return error.InvalidSpecificationCoverageRepair;
        const selected_target = omissionTarget(candidate, assessment.requirement, current) catch |err| switch (err) {
            error.UnsafeSpecificationOmissionRepair => null,
            else => return err,
        };
        assessment.target = selected_target;
        if (selected_target) |target| assessment.target_origin = current.units[target.unit].?.origins.at(switch (target.part) {
            .record => .unit,
            .value => |value| .{ .target = .{ .value = .{ .subject = value.subject, .field = value.field } } },
        });
        if (@import("source_omission.zig").isUpstream(assessment.owner.?)) {
            assessment.reason = .upstream_owner;
            continue;
        }
        if (assessment.owner.? == .source_association or assessment.owner.? == .unsupported_summary) {
            assessment.reason = .unsupported_owner;
            continue;
        }
        if (evidence.review.?.provenance.claim_ids.len == 0) {
            assessment.reason = .missing_claim_evidence;
            continue;
        }
        const target = selected_target orelse {
            assessment.reason = .unsupported_target;
            continue;
        };
        if (target.part == .record) {
            _ = authoredRecordSelection(a, support, context.inputs, evidence) catch |err| switch (err) {
                error.InvalidSpecificationBinding, error.InvalidSpecificationCoverageRepair => {
                    assessment.reason = .incompatible_record_binding;
                    continue;
                },
                else => return err,
            };
            const authorized = try bindRetry(a, try atomic.authorizeInsert(a, try sessions.ownerFor(a, current, target.unit), current.revision, target, .record, facts, .{ .omission = evidence }));
            assessment.reason = .authorized;
            return authorized;
        }
        const selected = target.part.value;
        const value = try candidates.attributedValue(.canonical, current.units[target.unit].?.response, selected.subject, selected.field);
        const provenance = evidence.review.?.provenance;
        const effective = try effectiveTarget(a, current.units[target.unit].?, selected.subject, selected.field);
        assessment.target_provenance = value.provenance;
        assessment.target_provenance.?.claim_ids = effective;
        r.sameSet(r.ClaimId, provenance.claim_ids, effective) catch |err| switch (err) {
            error.InvalidReferenceReconciliation => {
                assessment.reason = .claim_evidence_mismatch;
                continue;
            },
            else => return err,
        };
        r.sameSet(r.CitationId, provenance.citation_ids, value.provenance.citation_ids) catch |err| switch (err) {
            error.InvalidReferenceReconciliation => {
                assessment.reason = .citation_evidence_mismatch;
                continue;
            },
            else => return err,
        };
        const authorized = try bindRetry(a, try atomic.authorize(a, try sessions.ownerFor(a, current, target.unit), current.revision, target, .{ .value = value.value }, facts, .{ .omission = evidence }));
        assessment.reason = .authorized;
        return authorized;
    }
    return error.UnsafeSpecificationOmissionRepair;
}
/// The reviewed requirement owns insertion kind, independently of request grouping.
pub fn omissionRecordKind(id: authority.Id) Error!g.spec.Kind {
    if (id.kind != .feature_intent or id.unit != .feature or authority.policy(id) == null) return error.UnsafeSpecificationOmissionRepair;
    return switch (id.slot) {
        .acceptance_criteria, .scenario_coverage => .acceptance_criterion,
        .functional_requirements => .functional_requirement,
        else => error.UnsafeSpecificationOmissionRepair,
    };
}
fn omissionTarget(content: g.spec.IdentifiedContent, id: authority.Id, current: sessions.Session) Error!Target {
    if (id.kind != .feature_intent or authority.policy(id) == null) return error.UnsafeSpecificationOmissionRepair;
    switch (id.unit) {
        .feature => return switch (id.slot) {
            .acceptance_criteria, .scenario_coverage, .functional_requirements => insert: {
                const index = sessions.records_index;
                break :insert .{ .unit = index, .part = .{ .record = current.units[index].?.response.content.records.len } };
            },
            .display_name => .{ .unit = 0, .part = .{ .value = .{ .subject = .title, .field = .value } } },
            .description => .{ .unit = 0, .part = .{ .value = .{ .subject = .description, .field = .value } } },
            .primary_goal => .{ .unit = 0, .part = .{ .value = .{ .subject = .primary_goal, .field = .value } } },
            .primary_user_story => .{ .unit = 1, .part = .{ .value = .{ .subject = .story, .field = .value } } },
            else => error.UnsafeSpecificationOmissionRepair,
        },
        .record => |selected| {
            for (content.records) |record| {
                if (std.meta.eql(record.id, selected)) {
                    const field = @import("specification_authority.zig").valueField(id) catch return error.UnsafeSpecificationOmissionRepair;
                    return .{ .unit = sessions.records_index, .part = .{ .value = .{ .subject = .{ .record = try sessions.recordIndex(current, selected) }, .field = field } } };
                }
            }
            return error.UnsafeSpecificationOmissionRepair;
        },
        else => return error.UnsafeSpecificationOmissionRepair,
    }
}
pub fn omissionPacket(a: std.mem.Allocator, current: sessions.Session, context: p.Context, candidate: g.spec.IdentifiedContent, support: Support, authorization: Authorization) Error!*@import("model_input_packet.zig").Packet {
    if (authorization.rule != .omission) return error.InvalidSpecificationCoverageRepair;
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const facts = try reviewedFacts(arena.allocator(), current, context, candidate, support);
    try atomic.checkDependencies(a, authorization, facts);
    const packets = @import("model_input_packet.zig");
    const allowed: ?[]const r.ClaimId = if (authorization.target.part == .value) allowed: {
        const selected = authorization.target.part.value;
        break :allowed try effectiveTarget(arena.allocator(), current.units[authorization.target.unit].?, selected.subject, selected.field);
    } else null;
    const task = if (authorization.target.part == .record)
        try descriptions.record(arena.allocator(), try omissionRecordKind(authorization.rule.omission.requirement))
    else
        try descriptions.task(arena.allocator(), authorization.rule.omission.requirement);
    const base = try sessions.packetForOptions(a, current, context, authorization.target.unit, .{ .exact_claims = allowed, .task = task });
    defer packets.release(base);
    const contextual = try packets.withContext(g.spec.IdentifiedContent, a, base, "candidate", candidate);
    defer packets.release(contextual);
    const definition = if (authorization.target.part == .record) try std.fmt.allocPrint(a, "repair_record_{s}", .{@tagName(try omissionRecordKind(authorization.rule.omission.requirement))}) else "value";
    defer if (authorization.target.part == .record) a.free(definition);
    const narrowed = if (authorization.target.part == .value) narrow: {
        const target = authorization.target.part.value;
        const value = try candidates.attributedValue(.canonical, current.units[authorization.target.unit].?.response, target.subject, target.field);
        break :narrow try sessions.withSelectionChoices(a, contextual, context, .{ .claim_ids = allowed.?, .clarification_response_ids = value.provenance.clarification_response_ids });
    } else try packets.withExcludedVariants(a, contextual, contextual.excludedVariants());
    defer packets.release(narrowed);
    const text_field: ?@import("text_field_policy.zig").Field = switch (authorization.target.part) {
        .record => null,
        .value => |value| if (value.subject == .record) try candidates.recordTextField(current.units[authorization.target.unit].?.response.content.records[value.subject.record].content, value.field) else try candidates.singletonTextField(value.subject),
    };
    return atomic.packet(a, authorization, narrowed, .{ .bytes = definition }, current.units[authorization.target.unit].?.origins.at(switch (authorization.target.part) {
        .record => .unit,
        .value => |field| .{ .target = .{ .value = .{ .subject = field.subject, .field = field.field } } },
    }), .{ .fields = .{ .replacement = .{ .inherited = text_field } } });
}
pub fn parseOmission(a: std.mem.Allocator, authorization: Authorization, input: *const @import("model_input_packet.zig").Packet, bytes: []const u8) Error!Replacement {
    if (authorization.rule != .omission) return error.InvalidSpecificationCoverageRepair;
    const kind = try atomic.checkRequest(authorization, input);
    const codec = @import("model_candidate_json.zig");
    const canonical = try codec.constructBound(a, bytes, input.integerChoices());
    defer a.free(canonical);
    return switch (kind) {
        .value => .{ .value = try codec.decode(g.spec.BusinessValue, a, canonical) },
        .record => blk: {
            const wire = try codec.decode(g.spec.Wire.RecordProposal, a, canonical);
            const support = authorization.dependencies.support orelse return error.InvalidSpecificationCoverageRepair;
            const bound = try authoredRecordSelection(a, support, authorization.dependencies.references.text.inputs, authorization.rule.omission);
            break :blk .{ .record = .{ .content = wire.content, .source_group_ids = try a.dupe(r.SignalId, &.{bound.group}), .provenance = bound.selection } };
        },
    };
}
pub fn mergeOmission(a: std.mem.Allocator, canonical: @import("typed_text.zig").CanonicalText, validator: @import("typed_text.zig").Validator, current: sessions.Session, context: p.Context, candidate: g.spec.IdentifiedContent, support: Support, authorization: Authorization, proposed: Replacement, origin: ?@import("model_candidate_origin.zig").Origin) Error!sessions.Session {
    if (!canonical.matchesInputs(context.inputs)) return error.InvalidAtomicRepair;
    if (authorization.rule != .omission) return error.InvalidSpecificationCoverageRepair;
    const facts = try reviewedFacts(a, current, context, candidate, support);
    defer a.free(facts.references.lineage.history);
    return mergeChecked(a, canonical, validator, context, facts, authorization, proposed, origin);
}

fn mergeChecked(a: std.mem.Allocator, canonical: @import("typed_text.zig").CanonicalText, validator: @import("typed_text.zig").Validator, context: p.Context, facts: Facts, authorization: Authorization, proposed: Replacement, origin: ?@import("model_candidate_origin.zig").Origin) Error!sessions.Session {
    const current = facts.session;
    const target = authorization.target;
    if (target.unit >= current.units.len) return error.InvalidSpecificationCoverageRepair;
    const checked = current.units[target.unit] orelse return error.InvalidSpecificationCoverageRepair;
    const expected: ?Replacement = switch (target.part) {
        .record => null,
        .value => |field| .{ .value = (try candidates.attributedValue(.canonical, checked.response, field.subject, field.field)).value },
    };
    const merged = try atomic.checkMerge(a, canonical, try sessions.ownerFor(a, current, target.unit), current.revision, expected, facts, authorization, proposed, origin);
    const replacement = try atomic.copyReplacement(a, proposed);
    var response = checked.response;
    const origin_target: candidates.Target = switch (target.part) {
        .value => |field| target_value: {
            if (replacement != .value) return error.InvalidSpecificationCoverageRepair;
            response = try candidates.replaceCanonicalValue(a, response, field.subject, field.field, replacement.value);
            const prior = try candidates.attributedValue(.canonical, checked.response, field.subject, field.field);
            const updated = try candidates.attributedValue(.canonical, response, field.subject, field.field);
            const values = if (field.subject == .record)
                try p.recordValues(a, response.content.records[field.subject.record].content)
            else
                &.{updated.value};
            const resolved = try p.lineageForRepair(a, context, .{ .claim_ids = updated.provenance.claim_ids, .clarification_response_ids = updated.provenance.clarification_response_ids }, values);
            try r.sameSet(r.ClaimId, try effectiveTarget(a, checked, field.subject, field.field), resolved.effective_claim_ids);
            try r.sameSet(r.CitationId, prior.provenance.citation_ids, resolved.provenance.citation_ids);
            response = try candidates.replaceCanonicalProvenance(a, response, field.subject, resolved.provenance);
            break :target_value .{ .value = .{ .subject = field.subject, .field = field.field } };
        },
        .record => |index| record: {
            if (authorization.rule != .omission or replacement != .record or response.content != .records or index != response.content.records.len) return error.InvalidSpecificationCoverageRepair;
            if (std.meta.activeTag(replacement.record.content) != try omissionRecordKind(authorization.rule.omission.requirement)) return error.InvalidSpecificationCoverageRepair;
            const support = facts.support orelse return error.InvalidSpecificationCoverageRepair;
            const bound = try authoredRecordSelection(a, support, context.inputs, authorization.rule.omission);
            if (replacement.record.source_group_ids.len != 1 or replacement.record.source_group_ids[0].ordinal != bound.group.ordinal) return error.InvalidSpecificationCoverageRepair;
            try r.sameSet(r.ClaimId, authorization.rule.omission.review.?.provenance.claim_ids, replacement.record.provenance.claim_ids);
            const added = try p.checkRecord(.model, a, validator, context, replacement.record);
            const records = try a.alloc(g.spec.RecordProposal, index + 1);
            @memcpy(records[0..index], response.content.records);
            records[index] = added;
            response.content.records = records;
            break :record .{ .record = index };
        },
    };
    var origins = try checked.origins.replacing(a, origin_target, origin);
    if (authorization.operation == .insert) origins.record_occurrences = try origins.record_occurrences.inserting(a, target.part.record, checked.response.content.records.len);
    var next = try sessions.replaceCompleted(a, validator, context, current, target.unit, response, merged, origins);
    const permit = authorization.retry orelse return error.InvalidSpecificationCoverageRepair;
    next.omission_target_bound = permit.maximum_targets;
    return next;
}

/// Insertion retains one explicitly authored current group. Claim equality is a
/// precondition, never a search for a convenient group in the eligible catalogue.
fn authoredRecordSelection(a: std.mem.Allocator, support: Support, sources: r.evidence.Inputs, evidence: authority.Evidence) Error!struct { group: r.SignalId, selection: g.spec.Selection } {
    const review = evidence.review orelse return error.InvalidSpecificationCoverageRepair;
    const ids = try @import("source_omission_binding.zig").authoredGroupIds(a, support.inputs, evidence.requirement);
    defer a.free(ids);
    if (ids.len != 1) return error.InvalidSpecificationCoverageRepair;
    const records = support.inputs.references orelse return error.InvalidSpecificationCoverageRepair;
    const bound = try @import("specification_source_binding.zig").recordForGroup(a, records, sources, ids[0]);
    r.sameSet(r.ClaimId, bound.records.selection.claim_ids, review.provenance.claim_ids) catch return error.InvalidSpecificationCoverageRepair;
    return .{ .group = ids[0], .selection = bound.records.selection };
}

fn effectiveTarget(a: std.mem.Allocator, checked: g.Checked, subject: candidates.Subject, field: candidates.ValueField) Error![]const r.ClaimId {
    const value = try candidates.attributedValue(.canonical, checked.response, subject, field);
    const values = if (subject == .record)
        try p.recordValues(a, checked.response.content.records[subject.record].content)
    else
        &.{value.value};
    return p.effectiveClaims(a, value.provenance.claim_ids, values);
}

fn repairSubject(rule: Rule) Error!RepairSubject {
    return switch (rule) {
        .omission => |evidence| .{ .requirement = evidence.requirement },
    };
}
fn bindRetry(a: std.mem.Allocator, authorization: Authorization) Error!Authorization {
    var result = authorization;
    result.retry = try retryPermit(a, authorization);
    return result;
}
pub fn retryPermit(a: std.mem.Allocator, authorization: Authorization) Error!retry.Permit {
    const current = authorization.dependencies.session;
    const subject = try repairSubject(authorization.rule);
    const count: usize = switch (authorization.rule) {
        .omission => current.omission_target_bound orelse (authorization.dependencies.support orelse return error.InvalidSpecificationCoverageRepair).inputs.seeds.len,
    };
    const bound = std.math.cast(u32, count) orelse return error.InvalidSpecificationCoverageRepair;
    var owner = authorization.owner;
    owner.specification_unit.unit_slot_id.bytes = "specification-omission";
    var permit = try shared.permit(RepairSubject, std.meta.Tag(Rule), a, owner, subject, std.meta.activeTag(authorization.rule), authorization.id, authorization.revision, bound);
    permit.key.scope = try omissionScope(a, current.feature, current.reference_state);
    return permit;
}
fn omissionScope(a: std.mem.Allocator, feature: @import("feature_identity.zig").FeatureId, state: @import("reference_identity.zig").StateId) Error![32]u8 {
    const scope = .{ .contract = @typeName(Rule), .purpose = @as(std.meta.Tag(Rule), .omission), .feature = feature, .source_state = state };
    return (try shared.snapshot(@TypeOf(scope), a, scope)).bytes;
}

/// The runner supplies the active native permit; accepted review inputs already
/// carry the current source and candidate proof. Do not recapture old producers.
pub fn admittedOmissionValidation(a: std.mem.Allocator, permit: retry.Permit, admitted: @FieldType(@import("specification_support.zig").Source.Collection, "accepted")) Error!?retry.Transition {
    const inputs = admitted.inputs;
    if (!std.meta.eql(permit.key.family, (try shared.snapshot(std.meta.Tag(Rule), a, .omission)).bytes)) return null;
    const records = inputs.references orelse return error.InvalidSpecificationCoverageRepair;
    if (inputs.projection != .specification or inputs.specification == null or inputs.brief == null or
        inputs.revision <= permit.revision or
        !std.meta.eql(permit.key.scope, try omissionScope(a, inputs.feature, records.items.state_id))) return error.InvalidSpecificationCoverageRepair;
    const ledger = try authority.build(a, inputs);
    const result = try authority.reconcile(a, ledger, try authority.buildObservations(a, ledger));
    const selected = for (result.entries) |entry| {
        if (std.meta.eql(permit.key.target, (try shared.snapshot(RepairSubject, a, .{ .requirement = entry.requirement })).bytes)) break entry;
    } else return error.InvalidSpecificationCoverageRepair;
    const resolved = selected.candidate_defect == null and switch (selected.outcome) {
        .resolved_exactly_one, .resolved_explicit_not_applicable, .resolved_explicit_exception => true,
        .clarification_required, .upstream_rework_required, .administrative_block => false,
    };
    return .{ .validated = .{ .permit = permit, .revision = inputs.revision, .result = if (resolved) .resolved else .recurring } };
}

fn checkReviewedCandidate(a: std.mem.Allocator, current: sessions.Session, candidate: g.spec.IdentifiedContent, inputs: authority.Inputs) Error!void {
    if (inputs.revision != current.revision or inputs.specification == null or inputs.brief == null or
        !std.mem.eql(u8, inputs.feature.bytes, current.feature.bytes) or
        !try g.spec.sameContent(a, candidate, inputs.specification.?) or
        !std.meta.eql(try shared.snapshot(g.Brief, a, current.units[0].?.response.content.brief), try shared.snapshot(g.Brief, a, inputs.brief.?))) return error.InvalidSpecificationCoverageRepair;
}
