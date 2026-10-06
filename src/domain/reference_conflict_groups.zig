//! Group membership is semantic; reciprocal expansion is native, never transitive.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
pub const Group = struct { claim_ids: []const r.ClaimId };
pub const SemanticDisposition = union(r.Disposition) { retained: struct {}, superseded: struct { related_claim_ids: []const r.ClaimId }, duplicate: struct { target_claim_id: r.ClaimId }, conflicting: struct {} };
pub const Choice = struct { claim_id: r.ClaimId, disposition: SemanticDisposition };
pub const Selection = struct { claim_dispositions: []const Choice, conflict_groups: []const Group };
pub const Id = struct {
    ordinal: u32,
    pub const model_scalar = "ordinal";
};
pub const CatalogueEntry = struct { group_id: Id, claim_ids: []const r.ClaimId };
pub fn catalogue(a: std.mem.Allocator, groups: []const Group) r.Error![]const CatalogueEntry {
    const entries = try a.alloc(CatalogueEntry, groups.len);
    for (groups, entries, 0..) |group, *entry, index| entry.* = .{ .group_id = .{ .ordinal = try r.ordinal(index) }, .claim_ids = group.claim_ids };
    return entries;
}
pub fn members(groups: []const Group, id: Id) []const r.ClaimId {
    return if (id.ordinal == 0 or id.ordinal > groups.len) &.{} else groups[id.ordinal - 1].claim_ids;
}
pub const Explanation = struct { group_id: Id, kind: r.ConflictKind, summary: r.text.ReferenceSemanticText };
pub fn expand(a: std.mem.Allocator, selection: Selection) r.Error![]const r.ClaimDispositionProposal {
    const values = try a.alloc(r.ClaimDispositionProposal, selection.claim_dispositions.len);
    for (selection.claim_dispositions, values) |choice, *value| {
        value.* = .{ .claim_id = choice.claim_id, .disposition = switch (choice.disposition) {
            .retained => .{ .retained = .{} },
            .duplicate => |v| .{ .duplicate = .{ .target_claim_id = v.target_claim_id } },
            .superseded => |v| .{ .superseded = .{ .related_claim_ids = v.related_claim_ids } },
            .conflicting => conflicting: {
                var related: std.ArrayList(r.ClaimId) = .empty;
                for (selection.conflict_groups) |group| if (r.contains(r.ClaimId, group.claim_ids, choice.claim_id)) {
                    for (group.claim_ids) |id| if (id.ordinal != choice.claim_id.ordinal and !r.contains(r.ClaimId, related.items, id)) try related.append(a, id);
                };
                break :conflicting .{ .conflicting = .{ .related_claim_ids = try related.toOwnedSlice(a) } };
            },
        } };
    }
    return values;
}
pub fn issue(items: r.Items, proposal: r.Proposal) ?r.diagnostic.Issue {
    for (proposal.conflict_groups, 0..) |group, index| {
        const failure: r.diagnostic.Issue = .{ .rule = .relationship, .observed = .{ .claims = group.claim_ids }, .expected = .{ .constraint = .conflicting_related_claims } };
        if (group.claim_ids.len < 2) return failure;
        r.unique(r.ClaimId, group.claim_ids) catch return failure;
        for (group.claim_ids) |id| {
            _ = r.item(items, id) catch return failure;
            const conflicting = for (proposal.claim_dispositions) |d| {
                if (d.claim_id.ordinal == id.ordinal) break d.disposition == .conflicting;
            } else false;
            if (!conflicting) return failure;
        }
        for (proposal.conflict_groups[0..index]) |prior| if (@import("reference_reconciliation_validation.zig").sameMembers(prior.claim_ids, group.claim_ids)) return failure;
    }
    return null;
}
pub fn explain(a: std.mem.Allocator, groups: []const Group, supplied: []const Explanation) r.Error![]const r.ConflictProposal {
    const result = try a.alloc(r.ConflictProposal, supplied.len);
    for (supplied, result) |value, *out| {
        // Unknown handles remain typed candidate defects for the native checker.
        out.* = .{ .claim_ids = members(groups, value.group_id), .kind = value.kind, .summary = value.summary };
    }
    return result;
}

pub const Repair = struct { claim_dispositions: []const Choice, conflict_groups: []const Group, conflicts: []const Explanation };
pub fn disposition(a: std.mem.Allocator, value: SemanticDisposition, choices: ?@import("reference_disposition_validation.zig").RepairChoices) r.Error!@FieldType(r.ClaimDispositionProposal, "disposition") {
    return switch (value) {
        .retained => .{ .retained = .{} },
        .duplicate => |v| .{ .duplicate = .{ .target_claim_id = v.target_claim_id } },
        .superseded => |v| .{ .superseded = .{ .related_claim_ids = v.related_claim_ids } },
        .conflicting => .{ .conflicting = .{ .related_claim_ids = try a.dupe(r.ClaimId, if (choices) |v| v.conflicting_with_all else &.{}) } },
    };
}
