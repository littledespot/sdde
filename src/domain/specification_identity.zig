//! Engine-owned monotonic record allocation. Persistence belongs to publication.
const std = @import("std");
const spec = @import("specification.zig");
pub const Error = std.mem.Allocator.Error || spec.Error;
pub const Ledger = struct {
    next: [std.meta.tags(spec.Kind).len]u32 = @splat(1),
};
pub const Assigned = struct { content: spec.IdentifiedContent, ledger: Ledger };
pub fn assign(allocator: std.mem.Allocator, candidate: spec.ContentProposal, prior: Ledger) Error!Assigned {
    for (prior.next) |ordinal| if (ordinal == 0) return error.InvalidSpecification;
    var next = prior;
    const records = try allocator.alloc(spec.IdentifiedRecord, candidate.records.len);
    var previous: ?spec.Kind = null;
    for (candidate.records, records) |proposal, *record| {
        const kind: spec.Kind = proposal.content;
        if (previous != null and @intFromEnum(kind) < @intFromEnum(previous.?)) return error.InvalidSpecification;
        previous = kind;
        const index = @intFromEnum(kind);
        const ordinal = next.next[index];
        next.next[index] = std.math.add(u32, ordinal, 1) catch return error.InvalidSpecification;
        record.* = .{ .id = .{ .kind = kind, .ordinal = ordinal }, .proposal = proposal };
    }
    return .{
        .content = .{ .display_name = candidate.display_name, .primary_user_story = candidate.primary_user_story, .records = records, .entities = candidate.entities },
        .ledger = next,
    };
}
