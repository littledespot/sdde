//! Native lexical occurrence scope for model-text admission. This is never
//! model-visible selection data or semantic source-group authority.
const std = @import("std");
const recognition = @import("exact_value_recognition.zig");

pub const Scope = struct {
    reference_state: @import("reference_identity.zig").StateId,
    occurrences: []const recognition.Occurrence,
};

pub fn valid(scope: Scope) bool {
    if (scope.reference_state.bytes.len == 0 or !std.unicode.utf8ValidateSlice(scope.reference_state.bytes)) return false;
    for (scope.occurrences, 0..) |entry, index| {
        if (entry.claim_id.ordinal == 0 or entry.bytes.len == 0 or !std.unicode.utf8ValidateSlice(entry.bytes)) return false;
        for (scope.occurrences[0..index]) |prior| if (prior.claim_id.ordinal == entry.claim_id.ordinal) return false;
    }
    return true;
}

/// The returned scope is owned by the caller's retained arena.
pub fn clone(a: std.mem.Allocator, scope: Scope) std.mem.Allocator.Error!Scope {
    const occurrences = try a.alloc(recognition.Occurrence, scope.occurrences.len);
    var count: usize = 0;
    errdefer {
        for (occurrences[0..count]) |entry| a.free(entry.bytes);
        a.free(occurrences);
    }
    for (scope.occurrences, occurrences) |entry, *copy| {
        copy.* = .{ .claim_id = entry.claim_id, .bytes = try a.dupe(u8, entry.bytes) };
        count += 1;
    }
    return .{ .reference_state = .{ .bytes = try a.dupe(u8, scope.reference_state.bytes) }, .occurrences = occurrences };
}

pub fn same(left: ?Scope, right: ?Scope) bool {
    if (left == null or right == null) return left == null and right == null;
    if (!left.?.reference_state.eql(right.?.reference_state) or left.?.occurrences.len != right.?.occurrences.len) return false;
    for (left.?.occurrences, right.?.occurrences) |l, r| {
        if (l.claim_id.ordinal != r.claim_id.ordinal or !std.mem.eql(u8, l.bytes, r.bytes)) return false;
    }
    return true;
}

/// A projection can narrow existing occurrence eligibility, never rebind its
/// snapshot or change the bytes associated with an existing occurrence.
pub fn narrows(original: Scope, selected: Scope) bool {
    if (!valid(original) or !valid(selected) or !original.reference_state.eql(selected.reference_state)) return false;
    for (selected.occurrences) |entry| {
        for (original.occurrences) |prior| {
            if (entry.claim_id.ordinal == prior.claim_id.ordinal and std.mem.eql(u8, entry.bytes, prior.bytes)) break;
        } else return false;
    }
    return true;
}

test "native exact scope rejects aliases foreign snapshots and changed occurrence bytes" {
    const original: Scope = .{ .reference_state = .{ .bytes = "REF-1" }, .occurrences = &.{.{ .claim_id = .{ .ordinal = 2 }, .bytes = "ACTIVE" }} };
    try std.testing.expect(valid(original));
    try std.testing.expect(narrows(original, original));
    try std.testing.expect(narrows(original, .{ .reference_state = original.reference_state, .occurrences = &.{} }));
    try std.testing.expect(!valid(.{ .reference_state = original.reference_state, .occurrences = &.{ original.occurrences[0], original.occurrences[0] } }));
    try std.testing.expect(!narrows(original, .{ .reference_state = .{ .bytes = "REF-2" }, .occurrences = original.occurrences }));
    try std.testing.expect(!narrows(original, .{ .reference_state = original.reference_state, .occurrences = &.{.{ .claim_id = .{ .ordinal = 2 }, .bytes = "CHANGED" }} }));
    try std.testing.expect(!same(original, null));
}
