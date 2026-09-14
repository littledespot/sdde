//! Native generation dependencies; presentation bytes never bind authorization.
const std = @import("std");
const session = @import("specification_session.zig");
const provenance = @import("specification_provenance.zig");
const candidates = @import("specification_candidate.zig");
pub const Facts = struct {
    session: session.Session,
    references: provenance.Dependencies,
    candidate: candidates.Candidate,
};
pub fn capture(a: std.mem.Allocator, current: session.Session, context: provenance.Context, candidate: candidates.Candidate) session.Error!Facts {
    return .{ .session = current, .references = try provenance.dependencies(a, context), .candidate = candidate };
}
pub fn snapshot(a: std.mem.Allocator, current: session.Session, context: provenance.Context, candidate: candidates.Candidate) session.Error!@import("atomic_repair.zig").Snapshot {
    const facts = try capture(a, current, context, candidate);
    defer a.free(facts.references.lineage.history);
    return @import("atomic_repair.zig").snapshot(Facts, a, facts);
}
