//! Engine-owned monotonic record allocation. Persistence belongs to publication.
const std = @import("std");
const spec = @import("specification.zig");
pub const Error = std.mem.Allocator.Error || spec.Error;
pub const Ledger = struct {
    next: [std.meta.tags(spec.Kind).len]u32 = @splat(1),
};
pub const Assigned = struct { content: spec.IdentifiedContent, ledger: Ledger };
/// An edge case's link to the acceptance criterion whose Then it prints, as indexes into the
/// records `assign` receives (`scenario_link.zig`).
pub const Outcome = struct { edge_case: usize, criterion: usize };
/// `outcomes` holds exactly one link for each edge case of `candidate`, to a criterion
/// `scenario_link.candidate` accepts: the rule readback rechecks. The IDs each link stores are the
/// ones this assignment gives, so nothing else predicts them.
pub fn assign(allocator: std.mem.Allocator, candidate: spec.ContentProposal, prior: Ledger, outcomes: []const Outcome) Error!Assigned {
    for (prior.next) |ordinal| if (ordinal == 0) return error.InvalidSpecification;
    var next = prior;
    const records = try allocator.alloc(spec.IdentifiedRecord, candidate.records.len);
    errdefer allocator.free(records);
    var previous: ?spec.Kind = null;
    var edge_cases: usize = 0;
    for (candidate.records, records) |proposal, *record| {
        const kind: spec.Kind = proposal.content;
        if (previous != null and @intFromEnum(kind) < @intFromEnum(previous.?)) return error.InvalidSpecification;
        previous = kind;
        const index = @intFromEnum(kind);
        const ordinal = next.next[index];
        next.next[index] = std.math.add(u32, ordinal, 1) catch return error.InvalidSpecification;
        if (kind.showsOutcome()) edge_cases += 1;
        record.* = .{ .id = .{ .kind = kind, .ordinal = ordinal }, .proposal = proposal, .outcome_of = null };
    }
    if (outcomes.len != edge_cases) return error.InvalidSpecification;
    // One link per edge case: as many links as edge cases, and none sets an outcome twice.
    for (outcomes) |outcome| {
        if (outcome.edge_case >= records.len or outcome.criterion >= records.len) return error.InvalidSpecification;
        const edge = &records[outcome.edge_case];
        if (!edge.id.kind.showsOutcome() or edge.outcome_of != null) return error.InvalidSpecification;
        const criterion = records[outcome.criterion];
        if (!@import("scenario_link.zig").candidate(edge.proposal, criterion.proposal)) return error.InvalidSpecification;
        edge.outcome_of = criterion.id;
    }
    return .{
        .content = .{ .display_name = candidate.display_name, .primary_user_story = candidate.primary_user_story, .records = records, .entities = candidate.entities },
        .ledger = next,
    };
}
