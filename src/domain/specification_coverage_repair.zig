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
pub const Support = struct { inputs: authority.Inputs, observations: authority.Observations, result: authority.Result };
pub const Facts = struct {
    support: ?Support = null,
    session: sessions.Session,
    candidate: g.spec.IdentifiedContent,
    references: p.Dependencies,
};
const ValueTarget = struct { unit: usize, subject: candidates.Subject, field: candidates.ValueField };
pub const Target = struct { unit: usize, part: union(enum) { value: struct { subject: candidates.Subject, field: candidates.ValueField }, record: usize } };
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
pub const Error = sessions.Error || atomic.Error || candidates.Error || authority.Error || error{ InvalidSpecificationCoverageRepair, UnsafeSpecificationOmissionRepair };

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
    const value = try candidates.canonicalValue(checked.response, target.subject, target.field);
    if (value.value != .normalized or !r.contains(r.ClaimId, value.provenance.claim_ids, rejection.claim_id)) return null;
    // Reuse the canonical text projector, including passive references and any
    // literal segmentation. Equality proves no business bytes are discarded.
    const scalar = try @import("specification_projection.zig").scalar(a, context, value);
    return if (std.mem.eql(u8, scalar.bytes, rejection.issue.missing_exact_copy.value.raw_value.bytes)) target else null;
}
fn authorizeTarget(a: std.mem.Allocator, facts: Facts, target: ValueTarget, rejection: coverage.Rejection) Error!Decision {
    const checked = facts.session.units[target.unit].?;
    var native = rejection;
    native.origin = checked.origins.at(.{ .target = .{ .value = .{ .subject = target.subject, .field = target.field } } });
    return .{ .authorized = try atomic.authorize(a, try sessions.ownerFor(a, facts.session, target.unit), facts.session.revision, .{ .unit = target.unit, .part = .{ .value = .{ .subject = target.subject, .field = target.field } } }, .{ .value = (try candidates.canonicalValue(checked.response, target.subject, target.field)).value }, facts, .{ .coverage = native }) };
}
pub fn merge(a: std.mem.Allocator, validator: @import("typed_text.zig").Validator, current: sessions.Session, context: p.Context, candidate: g.spec.IdentifiedContent, authorization: Authorization) Error!sessions.Session {
    const facts = try capture(a, current, context, candidate);
    defer a.free(facts.references.lineage.history);
    const target = authorization.target;
    if (target.part != .value or authorization.rule != .coverage) return error.InvalidSpecificationCoverageRepair;
    if (authorization.rule.coverage.issue != .missing_exact_copy) return error.InvalidSpecificationCoverageRepair;
    const token = authorization.rule.coverage.issue.missing_exact_copy;
    return mergeChecked(a, validator, context, facts, authorization, .{ .value = .{ .exact_copy = .{ .token_id = token.value.id, .citation_id = token.citation_id } } }, null);
}

fn reviewedFacts(a: std.mem.Allocator, current: sessions.Session, context: p.Context, candidate: g.spec.IdentifiedContent, support: Support) Error!Facts {
    if (support.inputs.revision != current.revision or support.inputs.specification == null or
        !std.mem.eql(u8, support.inputs.feature.bytes, current.feature.bytes) or
        !try g.spec.sameContent(a, candidate, support.inputs.specification.?)) return error.InvalidSpecificationCoverageRepair;
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
        if (evidence.review.?.provenance.claim_ids.len == 0) return error.UnsafeSpecificationOmissionRepair;
        const target = try omissionTarget(candidate, entry.requirement, current);
        if (target.part == .record) return atomic.authorizeInsert(a, try sessions.ownerFor(a, current, target.unit), current.revision, target, .record, facts, .{ .omission = evidence });
        const selected = target.part.value;
        const value = try candidates.canonicalValue(current.units[target.unit].?.response, selected.subject, selected.field);
        const provenance = evidence.review.?.provenance;
        try r.sameSet(r.ClaimId, provenance.claim_ids, value.provenance.claim_ids);
        try r.sameSet(r.CitationId, provenance.citation_ids, value.provenance.citation_ids);
        return atomic.authorize(a, try sessions.ownerFor(a, current, target.unit), current.revision, target, .{ .value = value.value }, facts, .{ .omission = evidence });
    }
    return error.UnsafeSpecificationOmissionRepair;
}
fn omissionTarget(content: g.spec.IdentifiedContent, id: authority.Id, current: sessions.Session) Error!Target {
    if (id.kind != .feature_intent or authority.policy(id) == null) return error.UnsafeSpecificationOmissionRepair;
    switch (id.unit) {
        .feature => return switch (id.slot) {
            .acceptance_criteria, .scenario_coverage, .functional_requirements => insert: {
                const kind: g.spec.Kind = if (id.slot == .functional_requirements) .functional_requirement else .acceptance_criterion;
                const index = 3 + @as(usize, @intFromEnum(kind));
                break :insert .{ .unit = index, .part = .{ .record = current.units[index].?.response.content.records.len } };
            },
            .display_name => .{ .unit = 0, .part = .{ .value = .{ .subject = .title, .field = .value } } },
            .description => .{ .unit = 0, .part = .{ .value = .{ .subject = .description, .field = .value } } },
            .primary_goal => .{ .unit = 0, .part = .{ .value = .{ .subject = .primary_goal, .field = .value } } },
            .primary_user_story => .{ .unit = 1, .part = .{ .value = .{ .subject = .story, .field = .value } } },
            else => error.UnsafeSpecificationOmissionRepair,
        },
        .record => |selected| {
            var index: usize = 0;
            for (content.records) |record| {
                if (record.id.kind != selected.kind) continue;
                if (std.meta.eql(record.id, selected)) {
                    const field: candidates.ValueField = if (id.slot == .relationship) .{ .relationship = std.math.sub(usize, id.member, 1) catch return error.UnsafeSpecificationOmissionRepair } else field: {
                        inline for (std.meta.fields(candidates.ValueField)) |value| {
                            if (comptime value.type == void) if (std.mem.eql(u8, value.name, @tagName(id.slot))) break :field @unionInit(candidates.ValueField, value.name, {});
                        }
                        return error.UnsafeSpecificationOmissionRepair;
                    };
                    return .{ .unit = 3 + @as(usize, @intFromEnum(selected.kind)), .part = .{ .value = .{ .subject = .{ .record = index }, .field = field } } };
                }
                index += 1;
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
    const base = try sessions.packetFor(a, current, context, authorization.target.unit);
    defer packets.release(base);
    const contextual = try packets.withContext(g.spec.IdentifiedContent, a, base, "candidate", candidate);
    defer packets.release(contextual);
    const definition = if (authorization.target.part == .record) try std.fmt.allocPrint(a, "record_{s}", .{@tagName((try sessions.unit(authorization.target.unit)).records)}) else "value";
    defer if (authorization.target.part == .record) a.free(definition);
    return atomic.packet(a, authorization, contextual, .{ .bytes = definition });
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
        .value => |field| .{ .value = (try candidates.canonicalValue(checked.response, field.subject, field.field)).value },
    };
    const merged = try atomic.checkMerge(a, try sessions.ownerFor(a, current, target.unit), current.revision, expected, facts, authorization, proposed, origin);
    const replacement = try atomic.copyReplacement(a, proposed);
    var response = checked.response;
    const origin_target: candidates.Target = switch (target.part) {
        .value => |field| target_value: {
            if (replacement != .value) return error.InvalidSpecificationCoverageRepair;
            response = try candidates.replaceCanonicalValue(a, response, field.subject, field.field, replacement.value);
            break :target_value .{ .value = .{ .subject = field.subject, .field = field.field } };
        },
        .record => |index| record: {
            if (authorization.rule != .omission or replacement != .record or response.content != .records or index != response.content.records.len) return error.InvalidSpecificationCoverageRepair;
            try r.sameSet(r.ClaimId, authorization.rule.omission.review.?.provenance.claim_ids, replacement.record.provenance.claim_ids);
            const added = try p.checkRecord(.model, a, validator, context, replacement.record);
            const records = try a.alloc(g.spec.RecordProposal, index + 1);
            @memcpy(records[0..index], response.content.records);
            records[index] = added;
            response.content.records = records;
            break :record .{ .record = index };
        },
    };
    return sessions.replaceCompleted(a, validator, context, current, target.unit, response, merged, if (authorization.rule == .coverage) checked.origins else try checked.origins.replacing(a, origin_target, origin));
}
