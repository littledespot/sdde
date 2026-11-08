//! Edge-case outcome links (ADR 0038 Decision 7). An edge case prints the Then of an acceptance
//! criterion of its own records batch that names at least one of the same claims. Native code
//! computes the candidates: a sole candidate is the link, and a choice among two or more comes
//! from one closed model request per edge case. Positions index the records of the completed
//! records unit in authoring order; the model never picks a record by position.
const std = @import("std");
const spec = @import("specification.zig");
const r = @import("reference_reconciliation.zig");

pub const Error = error{InvalidScenarioLink} || std.mem.Allocator.Error;

pub const Link = struct { edge_case: u32, criterion: u32 };
pub const Pending = struct { edge_case: u32, candidates: []const u32 };
/// What one records unit needs: the links native code makes, the edge cases that need a model
/// choice, and the first edge case no criterion can serve (the unit cannot publish).
pub const Plan = struct {
    native: []const Link,
    pending: []const Pending,
    unlinkable: ?u32 = null,
};

/// Whether `criterion` can be the link of `edge`: an acceptance criterion of the same records
/// batch (one source group) naming at least one claim the edge case names. Sharing a claim is a
/// link, not a judgement that the criterion tests the condition (ADR 0038, Limits).
pub fn candidate(edge: spec.RecordProposal, criterion: spec.RecordProposal) bool {
    if (edge.content != .edge_case or criterion.content != .acceptance_criterion) return false;
    if (edge.source_group_ids.len != 1 or criterion.source_group_ids.len != 1 or edge.source_group_ids[0].ordinal != criterion.source_group_ids[0].ordinal) return false;
    for (edge.provenance.claim_ids) |claim| if (r.contains(r.ClaimId, criterion.provenance.claim_ids, claim)) return true;
    return false;
}

/// The candidates of every edge case in `records`. The caller owns an arena: the result and every
/// slice in it, and the working lists, live until it is released.
pub fn plan(allocator: std.mem.Allocator, records: []const spec.RecordProposal) Error!Plan {
    var native: std.ArrayList(Link) = .empty;
    var pending: std.ArrayList(Pending) = .empty;
    var unlinkable: ?u32 = null;
    for (records, 0..) |edge, edge_index| {
        if (edge.content != .edge_case) continue;
        const edge_position = std.math.cast(u32, edge_index) orelse return error.InvalidScenarioLink;
        var candidates: std.ArrayList(u32) = .empty;
        for (records, 0..) |other, criterion_index| if (candidate(edge, other)) {
            try candidates.append(allocator, std.math.cast(u32, criterion_index) orelse return error.InvalidScenarioLink);
        };
        switch (candidates.items.len) {
            0 => if (unlinkable == null) {
                unlinkable = edge_position;
            },
            1 => try native.append(allocator, .{ .edge_case = edge_position, .criterion = candidates.items[0] }),
            else => try pending.append(allocator, .{ .edge_case = edge_position, .candidates = try candidates.toOwnedSlice(allocator) }),
        }
    }
    return .{ .native = try native.toOwnedSlice(allocator), .pending = try pending.toOwnedSlice(allocator), .unlinkable = unlinkable };
}

/// Whether `choice` answers the pending edge case `pending`: a link of that edge case to one of its
/// candidates.
pub fn admits(pending: Pending, choice: Link) bool {
    if (choice.edge_case != pending.edge_case) return false;
    return std.mem.indexOfScalar(u32, pending.candidates, choice.criterion) != null;
}

/// Every edge case's link, in authoring order, once each pending edge case has its choice.
/// `chosen` holds one admitted choice per pending edge case, in the plan's order.
pub fn resolve(allocator: std.mem.Allocator, current: Plan, chosen: []const Link) Error![]const Link {
    if (current.unlinkable != null or chosen.len != current.pending.len) return error.InvalidScenarioLink;
    for (current.pending, chosen) |pending, choice| if (!admits(pending, choice)) return error.InvalidScenarioLink;
    const links = try allocator.alloc(Link, current.native.len + chosen.len);
    @memcpy(links[0..current.native.len], current.native);
    @memcpy(links[current.native.len..], chosen);
    std.mem.sort(Link, links, {}, struct {
        fn before(_: void, left: Link, right: Link) bool {
            return left.edge_case < right.edge_case;
        }
    }.before);
    return links;
}

/// Whether stored content links the edge case at `edge_index` to an acceptance criterion it may
/// link to. Content that fails this is not a published specification.
pub fn validStored(records: []const spec.IdentifiedRecord, edge_index: usize) bool {
    const edge = records[edge_index];
    if (edge.proposal.content != .edge_case) return edge.outcome_of == null;
    const target = edge.outcome_of orelse return false;
    for (records) |other| {
        if (!std.meta.eql(other.id, target)) continue;
        return candidate(edge.proposal, other.proposal);
    }
    return false;
}

const testing = std.testing;
const text_value: spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = "Business content" } }} };

fn testRecord(content: spec.Content(spec.BusinessValue), group: u32, claims: []const u32) !spec.RecordProposal {
    const claim_ids = try testing.allocator.alloc(r.ClaimId, claims.len);
    for (claims, claim_ids) |claim, *id| id.* = .{ .ordinal = claim };
    const groups = try testing.allocator.alloc(r.SignalId, 1);
    groups[0] = .{ .ordinal = group };
    return .{ .content = content, .source_group_ids = groups, .provenance = .{ .claim_ids = claim_ids, .citation_ids = &.{}, .clarification_response_ids = &.{} } };
}

fn freeRecords(records: []const spec.RecordProposal) void {
    for (records) |record| {
        testing.allocator.free(record.provenance.claim_ids);
        testing.allocator.free(record.source_group_ids);
    }
}

test "an edge case links natively to its only candidate and asks a choice among several" {
    const ac: spec.Content(spec.BusinessValue) = .{ .acceptance_criterion = .{ .given = text_value, .when = text_value, .then = text_value } };
    const ec: spec.Content(spec.BusinessValue) = .{ .edge_case = .{ .condition = text_value } };
    const records = [_]spec.RecordProposal{
        try testRecord(ac, 1, &.{ 1, 2 }),
        try testRecord(ac, 1, &.{2}),
        try testRecord(ec, 1, &.{1}),
        try testRecord(ec, 1, &.{2}),
    };
    defer freeRecords(&records);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const result = try plan(arena.allocator(), &records);
    try testing.expectEqual(@as(?u32, null), result.unlinkable);
    // Claim 1 is named by the first criterion only: a native link.
    try testing.expectEqualDeep(&[_]Link{.{ .edge_case = 2, .criterion = 0 }}, result.native);
    // Claim 2 is named by both: one closed choice, never a guess.
    try testing.expectEqual(@as(usize, 1), result.pending.len);
    try testing.expectEqual(@as(u32, 3), result.pending[0].edge_case);
    try testing.expectEqualDeep(&[_]u32{ 0, 1 }, result.pending[0].candidates);
    const chosen = [_]Link{.{ .edge_case = 3, .criterion = 1 }};
    const links = try resolve(arena.allocator(), result, &chosen);
    try testing.expectEqualDeep(&[_]Link{ .{ .edge_case = 2, .criterion = 0 }, .{ .edge_case = 3, .criterion = 1 } }, links);
    // A choice outside the candidates, for another edge case, or missing is rejected.
    try testing.expect(!admits(result.pending[0], .{ .edge_case = 3, .criterion = 2 }));
    try testing.expect(!admits(result.pending[0], .{ .edge_case = 2, .criterion = 0 }));
    try testing.expectError(error.InvalidScenarioLink, resolve(arena.allocator(), result, &.{.{ .edge_case = 3, .criterion = 2 }}));
    try testing.expectError(error.InvalidScenarioLink, resolve(arena.allocator(), result, &.{}));
}

test "an edge case with no criterion in its batch sharing a claim cannot be linked" {
    const ac: spec.Content(spec.BusinessValue) = .{ .acceptance_criterion = .{ .given = text_value, .when = text_value, .then = text_value } };
    const ec: spec.Content(spec.BusinessValue) = .{ .edge_case = .{ .condition = text_value } };
    // The criterion of another batch names the claim, which a batch's edge case cannot use.
    const records = [_]spec.RecordProposal{
        try testRecord(ac, 2, &.{1}),
        try testRecord(ec, 1, &.{1}),
        try testRecord(ac, 1, &.{2}),
    };
    defer freeRecords(&records);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const result = try plan(arena.allocator(), &records);
    try testing.expectEqual(@as(?u32, 1), result.unlinkable);
    try testing.expectError(error.InvalidScenarioLink, resolve(arena.allocator(), result, &.{}));
}

test "records without an edge case need no link" {
    const ac: spec.Content(spec.BusinessValue) = .{ .acceptance_criterion = .{ .given = text_value, .when = text_value, .then = text_value } };
    const records = [_]spec.RecordProposal{try testRecord(ac, 1, &.{1})};
    defer freeRecords(&records);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const result = try plan(arena.allocator(), &records);
    try testing.expectEqual(@as(usize, 0), result.native.len + result.pending.len);
    try testing.expectEqual(@as(usize, 0), (try resolve(arena.allocator(), result, &.{})).len);
}

test "stored content must link an edge case to a criterion it may link to and no other record to anything" {
    const ac: spec.Content(spec.BusinessValue) = .{ .acceptance_criterion = .{ .given = text_value, .when = text_value, .then = text_value } };
    const ec: spec.Content(spec.BusinessValue) = .{ .edge_case = .{ .condition = text_value } };
    const criterion = try testRecord(ac, 1, &.{1});
    const other = try testRecord(ac, 1, &.{2});
    const edge = try testRecord(ec, 1, &.{1});
    defer freeRecords(&.{ criterion, other, edge });
    const first: spec.Id = .{ .kind = .acceptance_criterion, .ordinal = 1 };
    const second: spec.Id = .{ .kind = .acceptance_criterion, .ordinal = 2 };
    const good = [_]spec.IdentifiedRecord{
        .{ .id = first, .proposal = criterion },
        .{ .id = second, .proposal = other },
        .{ .id = .{ .kind = .edge_case, .ordinal = 1 }, .proposal = edge, .outcome_of = first },
    };
    try testing.expect(validStored(&good, 2));
    try testing.expect(validStored(&good, 0));
    // A criterion that shares no claim, a missing link, a dangling link and a link on a criterion.
    var wrong = good;
    wrong[2].outcome_of = second;
    try testing.expect(!validStored(&wrong, 2));
    wrong[2].outcome_of = null;
    try testing.expect(!validStored(&wrong, 2));
    wrong[2].outcome_of = .{ .kind = .acceptance_criterion, .ordinal = 9 };
    try testing.expect(!validStored(&wrong, 2));
    wrong = good;
    wrong[0].outcome_of = first;
    try testing.expect(!validStored(&wrong, 0));
}
