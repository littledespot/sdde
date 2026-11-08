//! Engine-owned monotonic record allocation. Persistence belongs to publication.
const std = @import("std");
const spec = @import("specification.zig");
pub const Error = std.mem.Allocator.Error || spec.Error;
pub const Ledger = struct {
    next: [std.meta.tags(spec.Kind).len]u32 = @splat(1),
};
pub const Assigned = struct { content: spec.IdentifiedContent, ledger: Ledger };
/// An edge case's link to the acceptance criterion whose Then it prints, by the IDs this
/// assignment gives them (`scenario_link.zig`).
pub const Outcome = struct { edge_case: spec.Id, criterion: spec.Id };
/// `outcomes` holds exactly one link for each edge case of `candidate`.
pub fn assign(allocator: std.mem.Allocator, candidate: spec.ContentProposal, prior: Ledger, outcomes: []const Outcome) Error!Assigned {
    for (prior.next) |ordinal| if (ordinal == 0) return error.InvalidSpecification;
    var next = prior;
    const records = try allocator.alloc(spec.IdentifiedRecord, candidate.records.len);
    var previous: ?spec.Kind = null;
    var edge_cases: usize = 0;
    for (candidate.records, records) |proposal, *record| {
        const kind: spec.Kind = proposal.content;
        if (previous != null and @intFromEnum(kind) < @intFromEnum(previous.?)) return error.InvalidSpecification;
        previous = kind;
        const index = @intFromEnum(kind);
        const ordinal = next.next[index];
        next.next[index] = std.math.add(u32, ordinal, 1) catch return error.InvalidSpecification;
        const id: spec.Id = .{ .kind = kind, .ordinal = ordinal };
        var outcome_of: ?spec.Id = null;
        if (kind.showsOutcome()) {
            edge_cases += 1;
            outcome_of = for (outcomes) |outcome| {
                if (std.meta.eql(outcome.edge_case, id)) break outcome.criterion;
            } else return error.InvalidSpecification;
        }
        record.* = .{ .id = id, .proposal = proposal, .outcome_of = outcome_of };
    }
    if (outcomes.len != edge_cases) return error.InvalidSpecification;
    return .{
        .content = .{ .display_name = candidate.display_name, .primary_user_story = candidate.primary_user_story, .records = records, .entities = candidate.entities },
        .ledger = next,
    };
}
