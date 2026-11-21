//! Claim-bound scenarios, the planning half (ADR 0038 Decisions 2 and 3). Every claim that a
//! requirement or behaviour statement of an admitted records batch names needs an acceptance
//! criterion, and native code fixes which claim each criterion serves before the model writes
//! anything: one numbered slot per distinct claim, in the batch's record and claim order. The model
//! writes the content of each slot (`scenario_request.zig`), never the claim, the kind or the group.
//!
//! A scope record names claims it does not need covered, and a scenario covers nothing by naming a
//! claim, so neither makes a slot. The batch is the admitted one, after the owner's native deletes
//! (`statement_ownership.zig`): a statement the owner deleted names nothing here. A batch without a
//! slot has no plan and needs no request.
const std = @import("std");
const spec = @import("specification.zig");
const g = @import("specification_generation.zig");
const r = @import("reference_reconciliation.zig");

pub const Error = error{InvalidSpecificationUnit} || std.mem.Allocator.Error;

/// A slot's number within its request, from one. It is neither a claim nor a record ID.
pub const SlotNumber = struct {
    pub const model_scalar = "ordinal";
    ordinal: u32,
};

/// Whether the batch has a slot, without planning it: a statement (`spec.Kind.isStatement`, the
/// requirement and behaviour families, which make a slot of each claim they name) names a claim.
pub fn hasSlots(records: []const spec.RecordProposal) bool {
    for (records) |record| if (std.meta.activeTag(record.content).isStatement() and record.provenance.claim_ids.len != 0) return true;
    return false;
}

/// One slot: its number and the claim it serves.
pub const Slot = struct { number: SlotNumber, claim: r.ClaimId };

/// The slots of one records batch: slot `n` serves the `n`-th claim, in the batch's one source
/// group. A plan has at least one slot.
pub const Plan = struct {
    group: r.SignalId,
    claims: []const r.ClaimId,

    pub fn count(self: Plan) usize {
        return self.claims.len;
    }

    /// The slot at `index`, from zero, in slot order.
    pub fn slot(self: Plan, index: usize) Slot {
        return .{ .number = .{ .ordinal = @intCast(index + 1) }, .claim = self.claims[index] };
    }

    /// The position of the slot `number` names, or null when no slot has that number.
    pub fn indexOf(self: Plan, number: SlotNumber) ?usize {
        if (number.ordinal == 0 or number.ordinal > self.claims.len) return null;
        return number.ordinal - 1;
    }

    /// Every slot's number, in slot order.
    pub fn numbers(self: Plan, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const i64 {
        const result = try allocator.alloc(i64, self.claims.len);
        for (result, 0..) |*number, index| number.* = self.slot(index).number.ordinal;
        return result;
    }
};

/// The slots of the admitted records batch of `group`, or null when it has none. The caller owns an
/// arena: the result, the slice in it and the working list live until it is released.
pub fn plan(allocator: std.mem.Allocator, group: r.SignalId, records: []const spec.RecordProposal) Error!?Plan {
    var claims: std.ArrayList(r.ClaimId) = .empty;
    errdefer claims.deinit(allocator);
    for (records) |record| {
        if (!g.inBatch(record, group)) return error.InvalidSpecificationUnit;
        if (!std.meta.activeTag(record.content).isStatement()) continue;
        for (record.provenance.claim_ids) |claim| {
            if (!r.contains(r.ClaimId, claims.items, claim)) try claims.append(allocator, claim);
        }
    }
    if (claims.items.len == 0) return null;
    if (claims.items.len > std.math.maxInt(u32)) return error.InvalidSpecificationUnit;
    return .{ .group = group, .claims = try claims.toOwnedSlice(allocator) };
}

const testing = std.testing;
const text_value: spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = "Business content" } }} };
const Content = spec.Content(spec.BusinessValue);
const requirement: Content = .{ .functional_requirement = .{ .text = text_value } };
const rule: Content = .{ .business_rule = .{ .text = text_value } };
const outcome: Content = .{ .user_visible_outcome = .{ .text = text_value } };
const prohibition: Content = .{ .prohibited_behavior = .{ .text = text_value } };
const assumption: Content = .{ .assumption = .{ .text = text_value } };
const non_goal: Content = .{ .non_goal = .{ .text = text_value } };
const edge_case: Content = .{ .edge_case = .{ .given = text_value } };
const criterion: Content = .{ .acceptance_criterion = .{ .given = text_value, .when = text_value, .then = text_value } };
const entity: Content = .{ .entity = .{ .name = text_value } };

fn testRecord(a: std.mem.Allocator, content: Content, group: u32, claims: []const u32) !spec.RecordProposal {
    const claim_ids = try a.alloc(r.ClaimId, claims.len);
    for (claims, claim_ids) |claim, *id| id.* = .{ .ordinal = claim };
    return .{ .content = content, .source_group_ids = try a.dupe(r.SignalId, &.{.{ .ordinal = group }}), .provenance = .{ .claim_ids = claim_ids, .citation_ids = &.{}, .clarification_response_ids = &.{} } };
}

fn expectClaims(expected: []const u32, actual: ?Plan) !void {
    const found = actual orelse return error.TestUnexpectedResult;
    try testing.expectEqual(expected.len, found.claims.len);
    for (expected, found.claims) |ordinal, claim| try testing.expectEqual(ordinal, claim.ordinal);
}

test "a slot is one distinct claim a requirement or behaviour statement names, in record and claim order" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Two requirements share claim 1 (requirements are exempt from the repeated-statement rule), so
    // it has one slot; a statement naming two claims makes two, in the order it lists them.
    const records = [_]spec.RecordProposal{
        try testRecord(a, requirement, 4, &.{ 3, 1 }),
        try testRecord(a, requirement, 4, &.{ 1, 5 }),
        try testRecord(a, outcome, 4, &.{2}),
        try testRecord(a, prohibition, 4, &.{4}),
    };
    const result = (try plan(a, .{ .ordinal = 4 }, &records)) orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(u32, 4), result.group.ordinal);
    try expectClaims(&.{ 3, 1, 5, 2, 4 }, result);
}

test "a slot's number is its place among the claims, and no other number has one" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // One requirement naming six claims makes six slots.
    const records = [_]spec.RecordProposal{try testRecord(a, requirement, 1, &.{ 1, 2, 3, 4, 5, 6 })};
    const result = (try plan(a, .{ .ordinal = 1 }, &records)) orelse return error.TestUnexpectedResult;
    try expectClaims(&.{ 1, 2, 3, 4, 5, 6 }, result);
    try testing.expectEqualSlices(i64, &.{ 1, 2, 3, 4, 5, 6 }, try result.numbers(a));
    for (0..6) |index| {
        const slot = result.slot(index);
        try testing.expectEqual(@as(u32, @intCast(index + 1)), slot.number.ordinal);
        try testing.expectEqual(result.claims[index].ordinal, slot.claim.ordinal);
        try testing.expectEqual(@as(?usize, index), result.indexOf(slot.number));
    }
    try testing.expectEqual(@as(?usize, null), result.indexOf(.{ .ordinal = 0 }));
    try testing.expectEqual(@as(?usize, null), result.indexOf(.{ .ordinal = 7 }));
}

test "scope records and scenarios make no slot, and a scenario never covers the claim it names" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Claim 1 only scope records name, 2 only an edge case and 3 only a criterion: none makes a
    // slot. A requirement's claim 6 keeps its slot though an edge case and a criterion name it too.
    const records = [_]spec.RecordProposal{
        try testRecord(a, assumption, 1, &.{1}),
        try testRecord(a, non_goal, 1, &.{1}),
        try testRecord(a, edge_case, 1, &.{2}),
        try testRecord(a, criterion, 1, &.{3}),
        try testRecord(a, requirement, 1, &.{6}),
        try testRecord(a, edge_case, 1, &.{6}),
        try testRecord(a, criterion, 1, &.{6}),
    };
    try expectClaims(&.{6}, try plan(a, .{ .ordinal = 1 }, &records));
    try testing.expect(hasSlots(&records));
}

test "a batch with no behaviour statement has no plan, so its group makes no request" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqual(@as(?Plan, null), try plan(a, .{ .ordinal = 2 }, &.{}));
    const scope_only = [_]spec.RecordProposal{
        try testRecord(a, assumption, 2, &.{4}),
        try testRecord(a, edge_case, 2, &.{4}),
    };
    try testing.expectEqual(@as(?Plan, null), try plan(a, .{ .ordinal = 2 }, &scope_only));
    try testing.expect(!hasSlots(&scope_only));
    try testing.expect(!hasSlots(&.{}));
}

test "a statement the owner deleted names nothing, so a claim only a scope record then names has no slot" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The rule's claim 1 is taken by the earlier non-goal, so the owner deletes the rule (ADR 0038
    // Decision 5); the requirement keeps claim 2 and the later outcome keeps its own claim 3.
    const batch = [_]spec.RecordProposal{
        try testRecord(a, non_goal, 1, &.{1}),
        try testRecord(a, rule, 1, &.{1}),
        try testRecord(a, requirement, 1, &.{2}),
        try testRecord(a, outcome, 1, &.{3}),
    };
    const prepared = try a.alloc(@import("statement_ownership.zig").Record, batch.len);
    for (batch, prepared) |record, *entry| entry.* = try g.statementRecord(a, record.content, record.provenance.claim_ids);
    const removed = try a.alloc(bool, batch.len);
    @memset(removed, false);
    g.StatementRule.sequence(.{ .records = prepared }, removed);
    try testing.expectEqualSlices(bool, &.{ false, true, false, false }, removed);
    var surviving: std.ArrayList(spec.RecordProposal) = .empty;
    for (batch, removed) |record, deleted| if (!deleted) try surviving.append(a, record);
    try expectClaims(&.{ 2, 3 }, try plan(a, .{ .ordinal = 1 }, surviving.items));
    // The deleted statement would have made claim 1 a slot, which is why the batch must be the surviving one.
    try expectClaims(&.{ 1, 2, 3 }, try plan(a, .{ .ordinal = 1 }, &batch));
}

test "a record of another group, of two groups, of none or an entity is not a batch of the group" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const elsewhere = [_]spec.RecordProposal{ try testRecord(a, requirement, 1, &.{1}), try testRecord(a, rule, 2, &.{2}) };
    try testing.expectError(error.InvalidSpecificationUnit, plan(a, .{ .ordinal = 1 }, &elsewhere));
    const unassigned = [_]spec.RecordProposal{.{ .content = requirement, .source_group_ids = &.{}, .provenance = .{ .claim_ids = &.{.{ .ordinal = 1 }}, .citation_ids = &.{}, .clarification_response_ids = &.{} } }};
    try testing.expectError(error.InvalidSpecificationUnit, plan(a, .{ .ordinal = 1 }, &unassigned));
    // A record naming the group and another is not the group's alone.
    const shared_groups = [_]spec.RecordProposal{.{ .content = requirement, .source_group_ids = &.{ .{ .ordinal = 1 }, .{ .ordinal = 2 } }, .provenance = .{ .claim_ids = &.{.{ .ordinal = 1 }}, .citation_ids = &.{}, .clarification_response_ids = &.{} } }};
    try testing.expectError(error.InvalidSpecificationUnit, plan(a, .{ .ordinal = 1 }, &shared_groups));
    const named = [_]spec.RecordProposal{try testRecord(a, entity, 1, &.{1})};
    try testing.expectError(error.InvalidSpecificationUnit, plan(a, .{ .ordinal = 1 }, &named));
}
