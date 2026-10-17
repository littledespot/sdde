//! Equal-byte token identity is native. Every original claim and occurrence
//! remains in the corpus; a duplicate points directly to its earliest original.
const std = @import("std");
const r = @import("reference_reconciliation.zig");

pub const Expected = union(enum) { retained, duplicate: r.ClaimId };

pub fn expected(items: r.Items, id: r.ClaimId) r.Error!Expected {
    const first = try representative(items, id);
    return if (first.ordinal == id.ordinal) .retained else .{ .duplicate = first };
}

pub fn matches(items: r.Items, value: r.ClaimDisposition) r.Error!bool {
    return switch (try expected(items, value.claim_id)) {
        .retained => value.disposition == .retained and value.related_claim_ids.len == 0,
        .duplicate => |first| value.disposition == .duplicate and value.related_claim_ids.len == 1 and value.related_claim_ids[0].ordinal == first.ordinal,
    };
}

pub fn representative(items: r.Items, id: r.ClaimId) r.Error!r.ClaimId {
    const bytes = try tokenBytes(items, id);
    // Items are indexed by original claim ordinal, independently of the
    // current partition, model ordering, token kind or source boundary.
    for (items.entries, 0..) |entry, index| {
        if (entry.claim.id.ordinal != try r.ordinal(index)) return error.InvalidReferenceReconciliation;
        if (entry.claim.content == .preserved_token and std.mem.eql(u8, bytes, entry.claim.content.preserved_token.value.raw_value.bytes)) return entry.claim.id;
    }
    return error.InvalidReferenceReconciliation;
}

pub fn sameBytes(items: r.Items, left: r.ClaimId, right: r.ClaimId) r.Error!bool {
    return std.mem.eql(u8, try tokenBytes(items, left), try tokenBytes(items, right));
}

/// All equal-byte original claims, including the representative, in ordinal
/// order. The caller owns the returned slice; no provenance is synthesized.
pub fn originals(a: std.mem.Allocator, items: r.Items, id: r.ClaimId) r.Error![]const r.ClaimId {
    const bytes = try tokenBytes(items, id);
    var result: std.ArrayList(r.ClaimId) = .empty;
    errdefer result.deinit(a);
    for (items.entries, 0..) |entry, index| {
        if (entry.claim.id.ordinal != try r.ordinal(index)) return error.InvalidReferenceReconciliation;
        if (entry.claim.content == .preserved_token and std.mem.eql(u8, bytes, entry.claim.content.preserved_token.value.raw_value.bytes)) try result.append(a, entry.claim.id);
    }
    return result.toOwnedSlice(a);
}

pub fn proposal(items: r.Items, id: r.ClaimId) r.Error!r.ClaimDispositionProposal {
    return .{ .claim_id = id, .disposition = switch (try expected(items, id)) {
        .retained => .{ .retained = .{} },
        .duplicate => |first| .{ .duplicate = .{ .target_claim_id = first } },
    } };
}

/// Preserve model semantic order and append native entries in original order.
/// Supplied token subjects are deliberately retained as candidate defects: the
/// complete checker rejects the extra disposition rather than hiding forgery.
pub fn append(a: std.mem.Allocator, items: r.Items, semantic: []const r.ClaimDispositionProposal) r.Error![]const r.ClaimDispositionProposal {
    var result: std.ArrayList(r.ClaimDispositionProposal) = .empty;
    errdefer result.deinit(a);
    try result.appendSlice(a, semantic);
    for (items.entries) |entry| if (entry.claim.content == .preserved_token) try result.append(a, try proposal(items, entry.claim.id));
    return result.toOwnedSlice(a);
}

fn tokenBytes(items: r.Items, id: r.ClaimId) r.Error![]const u8 {
    const item = try r.item(items, id);
    if (item.claim.content != .preserved_token) return error.InvalidReferenceReconciliation;
    return item.claim.content.preserved_token.value.raw_value.bytes;
}
