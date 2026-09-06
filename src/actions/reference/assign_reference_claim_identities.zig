const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const extraction = @import("../../domain/reference_extraction.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "assign-reference-claim-identities",
        .kind = .action,
        .requires = &.{.validated_reference_claims},
        .produces = &.{.reference_claim_identities},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, validated: extraction.Validated) extraction.Error!extraction.Assignments {
        var claims: std.ArrayList(extraction.Assignment) = .empty;
        var next_claim: u32 = 1;
        var next_citation: u32 = 1;
        for (validated.entries) |entry| switch (entry.outcome) {
            .claims => |entries| for (entries) |claim| {
                const ids = try allocator.alloc(extraction.CitationId, claim.citations.len);
                for (ids) |*id| {
                    id.* = .{ .ordinal = next_citation };
                    next_citation = std.math.add(u32, next_citation, 1) catch return error.InvalidReferenceExtraction;
                }
                try claims.append(allocator, .{ .claim_id = .{ .ordinal = next_claim }, .citation_ids = ids });
                next_claim = std.math.add(u32, next_claim, 1) catch return error.InvalidReferenceExtraction;
            },
            .no_feature_claim, .blocked => {},
        };
        return .{ .validated = validated, .claims = try claims.toOwnedSlice(allocator), .next_claim_ordinal = next_claim, .next_citation_ordinal = next_citation };
    }
};
