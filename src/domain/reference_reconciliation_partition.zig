//! One deterministic partition policy, shared by construction and validation.
const std = @import("std");
const r = @import("reference_reconciliation.zig");

pub fn layout(allocator: std.mem.Allocator, items: r.Items, group_size: u32) r.Error!r.Layout {
    if (group_size < 2) return error.InvalidReferenceReconciliation;
    var groups: std.ArrayList(r.Group) = .empty;
    var offset: usize = 0;
    var previous_source: u32 = 0;
    while (offset < items.entries.len) {
        const first = items.entries[offset];
        if (first.source_id.ordinal < previous_source or first.source_id.ordinal == 0) return error.InvalidReferenceReconciliation;
        previous_source = first.source_id.ordinal;
        var end = offset;
        while (end < items.entries.len and end - offset < group_size and items.entries[end].source_id.ordinal == previous_source) : (end += 1) {
            if (items.entries[end].claim.id.ordinal != end + 1) return error.InvalidReferenceReconciliation;
        }
        const claims = try allocator.alloc(r.ClaimId, end - offset);
        for (claims, items.entries[offset..end]) |*id, value| id.* = value.claim.id;
        try groups.append(allocator, .{ .level = .within_source, .round = 0, .claim_ids = claims, .children = &.{} });
        offset = end;
    }
    var start: usize = 0;
    var count = groups.items.len;
    if (count != 0) {
        try appendLevel(allocator, &groups, start, count, group_size, .cross_source, 0);
        start = count;
        count = groups.items.len - start;
    }
    var round: u32 = 0;
    while (true) {
        const next_start = groups.items.len;
        try appendLevel(allocator, &groups, start, count, group_size, .global, round);
        if (count <= group_size) break;
        start = next_start;
        count = groups.items.len - start;
        round = try r.next(round);
    }
    return .{ .items = items, .group_size = group_size, .groups = try groups.toOwnedSlice(allocator) };
}
fn appendLevel(allocator: std.mem.Allocator, groups: *std.ArrayList(r.Group), start: usize, count: usize, size: u32, level: r.Level, round: u32) r.Error!void {
    if (count == 0) {
        try groups.append(allocator, .{ .level = level, .round = round, .claim_ids = &.{}, .children = &.{} });
        return;
    }
    var offset: usize = 0;
    while (offset < count) {
        const end = offset + @min(count - offset, size);
        const children = try allocator.alloc(r.GroupIndex, end - offset);
        var claims: std.ArrayList(r.ClaimId) = .empty;
        for (children, start + offset..start + end) |*child, index| {
            child.* = .{ .value = index };
            try claims.appendSlice(allocator, groups.items[index].claim_ids);
        }
        try groups.append(allocator, .{ .level = level, .round = round, .children = children, .claim_ids = try claims.toOwnedSlice(allocator) });
        offset = end;
    }
}

pub fn validate(allocator: std.mem.Allocator, plan: r.Plan) r.Error!void {
    const expected = try layout(allocator, plan.layout.items, plan.layout.group_size);
    if (plan.layout.groups.len != expected.groups.len or plan.partitions.len != expected.groups.len) return error.InvalidReferenceReconciliation;
    for (expected.groups, plan.layout.groups, plan.partitions, 0..) |group, supplied, partition, index| {
        if (!equalGroup(group, supplied) or !equalGroup(group, partition.group) or partition.id.ordinal != index + 1) return error.InvalidReferenceReconciliation;
        for (group.children) |child| if (child.value >= index) return error.InvalidReferenceReconciliation;
    }
}
fn equalGroup(a: r.Group, b: r.Group) bool {
    if (a.level != b.level or a.round != b.round or a.claim_ids.len != b.claim_ids.len or a.children.len != b.children.len) return false;
    for (a.claim_ids, b.claim_ids) |left, right| if (left.ordinal != right.ordinal) return false;
    for (a.children, b.children) |left, right| if (left.value != right.value) return false;
    return true;
}
