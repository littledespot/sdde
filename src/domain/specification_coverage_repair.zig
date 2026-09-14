//! Native repair of a missing exact-token reference when existing validated
//! business bytes already equal that token. No new business statement is chosen.
const std = @import("std");
const sessions = @import("specification_session.zig");
const g = @import("specification_generation.zig");
const coverage = @import("specification_coverage.zig");
const candidates = @import("specification_candidate.zig");
const p = @import("specification_provenance.zig");
const r = @import("reference_reconciliation.zig");
const shared = @import("atomic_repair.zig");
pub const Facts = struct {
    session: sessions.Session,
    candidate: g.spec.IdentifiedContent,
    references: p.Dependencies,
};
pub const Target = struct { unit: usize, subject: candidates.Subject, field: candidates.ValueField };
const Replacement = union(enum) { value: g.spec.BusinessValue };
const Rule = struct { validator: enum { specification_coverage_v1 } = .specification_coverage_v1, rejection: coverage.Rejection };
const atomic = shared.Contract(Target, Replacement, Facts, Rule);
pub const Authorization = atomic.Authorization;
pub const Decision = union(enum) { authorized: Authorization, blocked: coverage.Rejection };
pub const Error = sessions.Error || atomic.Error || candidates.Error || error{InvalidSpecificationCoverageRepair};

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
fn matching(a: std.mem.Allocator, context: p.Context, checked: g.Checked, target: Target, rejection: coverage.Rejection) Error!?Target {
    const value = try candidates.canonicalValue(checked.response, target.subject, target.field);
    if (value.value != .normalized or !r.contains(r.ClaimId, value.provenance.claim_ids, rejection.claim_id)) return null;
    // Reuse the canonical text projector, including passive references and any
    // literal segmentation. Equality proves no business bytes are discarded.
    const scalar = try @import("specification_projection.zig").scalar(a, context, value);
    return if (std.mem.eql(u8, scalar.bytes, rejection.issue.missing_exact_copy.value.raw_value.bytes)) target else null;
}
fn authorizeTarget(a: std.mem.Allocator, facts: Facts, target: Target, rejection: coverage.Rejection) Error!Decision {
    const checked = facts.session.units[target.unit].?;
    var native = rejection;
    native.origin = checked.origins.at(.{ .target = .{ .value = .{ .subject = target.subject, .field = target.field } } });
    return .{ .authorized = try atomic.authorize(a, try owner(a, facts.session, target), facts.session.revision, target, .{ .value = (try candidates.canonicalValue(checked.response, target.subject, target.field)).value }, facts, .{ .rejection = native }) };
}
fn owner(a: std.mem.Allocator, current: sessions.Session, target: Target) Error!@import("model_request_identity.zig").ImmutableUnitOwnerId {
    var selected = current;
    selected.completed = target.unit;
    return sessions.owner(a, selected);
}
pub fn merge(a: std.mem.Allocator, validator: @import("typed_text.zig").Validator, current: sessions.Session, context: p.Context, candidate: g.spec.IdentifiedContent, authorization: Authorization) Error!sessions.Session {
    const facts = try capture(a, current, context, candidate);
    defer a.free(facts.references.lineage.history);
    const target = authorization.target;
    if (target.unit >= current.units.len) return error.InvalidSpecificationCoverageRepair;
    const checked = current.units[target.unit] orelse return error.InvalidSpecificationCoverageRepair;
    const token = authorization.rule.rejection.issue.missing_exact_copy;
    const replacement: g.spec.BusinessValue = .{ .exact_copy = .{ .token_id = token.value.id, .citation_id = token.citation_id } };
    var next = current;
    const merged = try atomic.checkMerge(a, try owner(a, current, target), current.revision, .{ .value = (try candidates.canonicalValue(checked.response, target.subject, target.field)).value }, facts, authorization, .{ .value = replacement }, null);
    next.revision = merged.revision_after;
    const proposal = try candidates.replaceCanonicalValue(a, checked.response, target.subject, target.field, replacement);
    // Checked session units cannot contain unvalidated data. The existing owning
    // validator proves this unit before it re-enters full session assembly.
    var accepted = switch (try g.revalidate(a, validator, context, checked.unit, proposal)) {
        .valid => |value| value,
        .invalid => return error.InvalidSpecificationCoverageRepair,
    };
    accepted.last_repair = merged;
    accepted.origins = checked.origins; // Engine reconstruction made no model call.
    next.units[target.unit] = accepted;
    return next;
}
