//! Mechanical coverage rejection has no independently supported repair target.
//! Semantic review cannot authorize edits to completed generated content.
const std = @import("std");
const sessions = @import("specification_session.zig");
const g = @import("specification_generation.zig");
const coverage = @import("specification_coverage.zig");
const p = @import("specification_provenance.zig");
const shared = @import("atomic_repair.zig");
pub const Facts = struct { session: sessions.Session, candidate: g.spec.IdentifiedContent, references: p.Dependencies };
pub const Decision = union(enum) { blocked: coverage.Rejection };
pub const Error = sessions.Error || coverage.Error || error{InvalidSpecificationCoverageRepair};

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
    // Filling an aggregate gap would invent meaning or change another owning
    // association. The mechanical diagnostic remains blocking, without repair.
    var blocked = rejection;
    blocked.blocked = .no_independent_supported_target;
    return .{ .blocked = blocked };
}
