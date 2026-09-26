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
const retry = @import("workflow_retry.zig");
const RepairSubject = union(enum) { token: coverage.TokenSubject, requirement: authority.Id };
pub const Support = struct { inputs: authority.Inputs, observations: authority.Observations, result: authority.Result };
pub const Facts = struct {
    support: ?Support = null,
    session: sessions.Session,
    candidate: g.spec.IdentifiedContent,
    references: p.Dependencies,
};
const ValueTarget = struct { unit: usize, subject: candidates.Subject, field: candidates.ValueField };
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
    coverage: coverage.Rejection,
    omission: authority.Evidence,
    pub fn guidance(self: @This()) union(enum) { coverage: coverage.Rejection, omission: authority.ReviewEvidence } {
        return switch (self) {
            .coverage => |value| .{ .coverage = value },
            .omission => |value| .{ .omission = value.review.? },
        };
    }
};
const atomic = shared.Contract(Target, Replacement, Facts, Rule);
pub const Authorization = atomic.Authorization;
pub const ModelRepair = struct { authorization: Authorization, response: ?struct { value: Replacement, origin: @import("model_candidate_origin.zig").Origin } = null };
pub const Decision = union(enum) { authorized: Authorization, blocked: coverage.Rejection };
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
    if (rejection.issue == .missing_exact_copy) {
        for (current.units, 0..) |entry, index| {
            const checked = entry orelse return error.InvalidSpecificationCoverageRepair;
            switch (checked.response.content) {
                .brief => inline for (.{ candidates.Subject.title, candidates.Subject.description, candidates.Subject.primary_goal }) |subject| {
                    if (try matching(a, context, checked, .{ .unit = index, .subject = subject, .field = .value }, rejection)) |target| return authorizeTarget(a, facts, target, rejection);
                },
                .primary_user_story, .entities => {
                    const subject: candidates.Subject = if (checked.response.content == .entities) .entity_basis else .story;
                    if (try matching(a, context, checked, .{ .unit = index, .subject = subject, .field = .value }, rejection)) |target| return authorizeTarget(a, facts, target, rejection);
                },
                .records => |records| for (records, 0..) |record, ordinal| switch (record.content) {
                    inline else => |fields| inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                        if (comptime field.type == g.spec.BusinessValue) {
                            if (try matching(a, context, checked, .{ .unit = index, .subject = .{ .record = ordinal }, .field = @field(candidates.ValueField, field.name) }, rejection)) |target| return authorizeTarget(a, facts, target, rejection);
                        } else for (@field(fields, field.name), 0..) |_, relationship| {
                            if (try matching(a, context, checked, .{ .unit = index, .subject = .{ .record = ordinal }, .field = .{ .relationship = relationship } }, rejection)) |target| return authorizeTarget(a, facts, target, rejection);
                        }
                    },
                },
            }
        }
    }
    var blocked = rejection;
    blocked.blocked = .no_independent_supported_target;
    return .{ .blocked = blocked };
}
fn matching(a: std.mem.Allocator, context: p.Context, checked: g.Checked, target: ValueTarget, rejection: coverage.Rejection) Error!?ValueTarget {
    const value = try candidates.attributedValue(.canonical, checked.response, target.subject, target.field);
    if (!r.contains(r.ClaimId, value.provenance.claim_ids, rejection.claim_id)) return null;
    // Reuse the canonical text projector, including passive references and any
    // literal segmentation. Equality proves no business bytes are discarded.
    const scalar = if (target.subject == .record)
        try @import("specification_projection.zig").recordScalar(a, context, checked.response.content.records[target.subject.record], value.value)
    else
        try @import("specification_projection.zig").scalar(a, context, value);
    return if (std.mem.eql(u8, scalar.bytes, rejection.issue.missing_exact_copy.value.raw_value.bytes)) target else null;
}
fn authorizeTarget(a: std.mem.Allocator, facts: Facts, target: ValueTarget, rejection: coverage.Rejection) Error!Decision {
    const checked = facts.session.units[target.unit].?;
    var native = rejection;
    native.origin = checked.origins.at(.{ .target = .{ .value = .{ .subject = target.subject, .field = target.field } } });
    return .{ .authorized = try bindRetry(a, try atomic.authorize(a, try sessions.ownerFor(a, facts.session, target.unit), facts.session.revision, .{ .unit = target.unit, .part = .{ .value = .{ .subject = target.subject, .field = target.field } } }, .{ .value = (try candidates.attributedValue(.canonical, checked.response, target.subject, target.field)).value }, facts, .{ .coverage = native })) };
}
pub fn merge(a: std.mem.Allocator, validator: @import("typed_text.zig").Validator, current: sessions.Session, context: p.Context, candidate: g.spec.IdentifiedContent, authorization: Authorization) Error!sessions.Session {
    const facts = try capture(a, current, context, candidate);
    defer a.free(facts.references.lineage.history);
    const target = authorization.target;
    if (target.part != .value or authorization.rule != .coverage) return error.InvalidSpecificationCoverageRepair;
    if (authorization.rule.coverage.issue != .missing_exact_copy) return error.InvalidSpecificationCoverageRepair;
    return mergeChecked(a, validator, context, facts, authorization, .{ .value = .{ .segments = &.{.{ .exact_copy = .{ .claim_id = authorization.rule.coverage.claim_id } }} } }, null);
}

fn reviewedFacts(a: std.mem.Allocator, current: sessions.Session, context: p.Context, candidate: g.spec.IdentifiedContent, support: Support) Error!Facts {
    try checkReviewedCandidate(a, current, candidate, support.inputs);
    _ = try authority.validate(a, support.inputs, support.observations, support.result);
    var facts = try capture(a, current, context, candidate);
    facts.support = support;
    return facts;
}
/// Only a current, shared-classified omission may select a native content slot.
/// No coverage row, source record or review verdict is a repair target.
pub fn authorizeOmission(a: std.mem.Allocator, validator: @import("typed_text.zig").Validator, current: sessions.Session, context: p.Context, candidate: g.spec.IdentifiedContent, support: Support) Error!Authorization {
    const rebuilt = try sessions.assemble(a, validator, context, current);
    if (!try g.spec.sameContent(a, rebuilt.content, candidate)) return error.InvalidSpecificationCoverageRepair;
    const facts = try reviewedFacts(a, current, context, candidate, support);
    defer a.free(facts.references.lineage.history);
    for (support.result.entries) |entry| {
        const evidence = (try authority.supportedOmission(a, support.inputs, support.observations, support.result, entry.requirement)) orelse continue;
        try @import("specification_support_evidence.zig").validate(a, support.inputs, context.inputs, evidence);
        if (evidence.review.?.provenance.claim_ids.len == 0) continue;
        const target = omissionTarget(candidate, entry.requirement, current) catch |err| switch (err) {
            error.UnsafeSpecificationOmissionRepair => continue,
            else => return err,
        };
        if (target.part == .record) return bindRetry(a, try atomic.authorizeInsert(a, try sessions.ownerFor(a, current, target.unit), current.revision, target, .record, facts, .{ .omission = evidence }));
        const selected = target.part.value;
        const value = try candidates.attributedValue(.canonical, current.units[target.unit].?.response, selected.subject, selected.field);
        const provenance = evidence.review.?.provenance;
        const effective = try effectiveTarget(a, current.units[target.unit].?, selected.subject, selected.field);
        r.sameSet(r.ClaimId, provenance.claim_ids, effective) catch |err| switch (err) {
            error.InvalidReferenceReconciliation => continue,
            else => return err,
        };
        r.sameSet(r.CitationId, provenance.citation_ids, value.provenance.citation_ids) catch |err| switch (err) {
            error.InvalidReferenceReconciliation => continue,
            else => return err,
        };
        return bindRetry(a, try atomic.authorize(a, try sessions.ownerFor(a, current, target.unit), current.revision, target, .{ .value = value.value }, facts, .{ .omission = evidence }));
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
                    const field: candidates.ValueField = if (id.slot == .relationship) .{ .relationship = std.math.sub(usize, id.member, 1) catch return error.UnsafeSpecificationOmissionRepair } else field: {
                        inline for (std.meta.fields(candidates.ValueField)) |value| {
                            if (comptime value.type == void) if (std.mem.eql(u8, value.name, @tagName(id.slot))) break :field @unionInit(candidates.ValueField, value.name, {});
                        }
                        return error.UnsafeSpecificationOmissionRepair;
                    };
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
        break :allowed try effectiveTarget(a, current.units[authorization.target.unit].?, selected.subject, selected.field);
    } else null;
    const base = try sessions.packetForChoices(a, current, context, authorization.target.unit, allowed);
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
    return atomic.packet(a, authorization, narrowed, .{ .bytes = definition }, current.units[authorization.target.unit].?.origins.at(switch (authorization.target.part) {
        .record => .unit,
        .value => |field| .{ .target = .{ .value = .{ .subject = field.subject, .field = field.field } } },
    }));
}
pub const parseOmission = atomic.parse;
pub fn mergeOmission(a: std.mem.Allocator, validator: @import("typed_text.zig").Validator, current: sessions.Session, context: p.Context, candidate: g.spec.IdentifiedContent, support: Support, authorization: Authorization, proposed: Replacement, origin: ?@import("model_candidate_origin.zig").Origin) Error!sessions.Session {
    if (authorization.rule != .omission) return error.InvalidSpecificationCoverageRepair;
    const facts = try reviewedFacts(a, current, context, candidate, support);
    defer a.free(facts.references.lineage.history);
    return mergeChecked(a, validator, context, facts, authorization, proposed, origin);
}

fn mergeChecked(a: std.mem.Allocator, validator: @import("typed_text.zig").Validator, context: p.Context, facts: Facts, authorization: Authorization, proposed: Replacement, origin: ?@import("model_candidate_origin.zig").Origin) Error!sessions.Session {
    const current = facts.session;
    const target = authorization.target;
    if (target.unit >= current.units.len) return error.InvalidSpecificationCoverageRepair;
    const checked = current.units[target.unit] orelse return error.InvalidSpecificationCoverageRepair;
    const expected: ?Replacement = switch (target.part) {
        .record => null,
        .value => |field| .{ .value = (try candidates.attributedValue(.canonical, checked.response, field.subject, field.field)).value },
    };
    const merged = try atomic.checkMerge(a, try sessions.ownerFor(a, current, target.unit), current.revision, expected, facts, authorization, proposed, origin);
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
            try r.sameSet(r.ClaimId, authorization.rule.omission.review.?.provenance.claim_ids, replacement.record.provenance.claim_ids);
            const added = try p.checkRecord(.model, a, validator, context, replacement.record);
            const records = try a.alloc(g.spec.RecordProposal, index + 1);
            @memcpy(records[0..index], response.content.records);
            records[index] = added;
            response.content.records = records;
            break :record .{ .record = index };
        },
    };
    var origins = if (authorization.rule == .coverage) checked.origins else try checked.origins.replacing(a, origin_target, origin);
    if (authorization.operation == .insert) origins.record_occurrences = try origins.record_occurrences.inserting(a, target.part.record, checked.response.content.records.len);
    var next = try sessions.replaceCompleted(a, validator, context, current, target.unit, response, merged, origins);
    const permit = authorization.retry orelse return error.InvalidSpecificationCoverageRepair;
    switch (try repairSubject(authorization.rule)) {
        .token => |target_subject| next.pending_coverage_repair = .{ .permit = permit, .target = target_subject },
        .requirement => next.omission_target_bound = permit.maximum_targets,
    }
    return next;
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
        .coverage => |rejection| if (rejection.issue == .missing_exact_copy) .{ .token = rejection.claim_id } else error.InvalidSpecificationCoverageRepair,
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
        .coverage => authorization.dependencies.references.lineage.plan.layout.items.entries.len,
        .omission => current.omission_target_bound orelse (authorization.dependencies.support orelse return error.InvalidSpecificationCoverageRepair).inputs.seeds.len,
    };
    const bound = std.math.cast(u32, count) orelse return error.InvalidSpecificationCoverageRepair;
    var owner = authorization.owner;
    owner.specification_unit.unit_slot_id.bytes = if (subject == .token) "specification-coverage" else "specification-omission";
    var permit = try shared.permit(RepairSubject, std.meta.Tag(Rule), a, owner, subject, std.meta.activeTag(authorization.rule), authorization.id, authorization.revision, bound);
    const Scope = struct { owner: @import("model_request_identity.zig").ImmutableUnitOwnerId, origin: ?@import("model_candidate_origin.zig").Origin };
    permit.key.scope = if (subject == .requirement) try omissionScope(a, current.feature, current.reference_state) else (try shared.snapshot(Scope, a, .{ .owner = owner, .origin = (current.units[0] orelse return error.InvalidSpecificationCoverageRepair).origins.initial })).bytes;
    return permit;
}
/// The canonical token obligation owns progress, independently of which field
/// supplied its exact-copy representation or which sibling fails next.
pub fn coverageValidation(a: std.mem.Allocator, current: sessions.Session, context: p.Context, candidate: g.spec.IdentifiedContent) Error!?retry.Transition {
    const receipt = current.pending_coverage_repair orelse return null;
    if (current.revision != std.math.add(u64, receipt.permit.revision, 1) catch return error.InvalidSpecificationCoverageRepair) return error.InvalidSpecificationCoverageRepair;
    const claim = (try r.item(try p.items(context), receipt.target)).claim;
    if (claim.content != .preserved_token) return error.InvalidSpecificationCoverageRepair;
    const targets = try coverage.exactTargets(a, current.units[0].?.response.content.brief, candidate, receipt.target);
    defer a.free(targets);
    return .{ .validated = .{ .permit = receipt.permit, .revision = current.revision, .result = if (targets.len != 0) .resolved else .recurring } };
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
