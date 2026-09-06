const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const extraction = @import("../../domain/reference_extraction.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "build-reference-extraction-ledger",
        .kind = .action,
        .requires = &.{.reference_claim_identities},
        .produces = &.{.reference_extraction_ledger},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, assigned: extraction.Assignments) extraction.Error!extraction.Ledger {
        var claims: std.ArrayList(extraction.Claim) = .empty;
        var citations: std.ArrayList(extraction.Citation) = .empty;
        const chunks = try allocator.alloc(extraction.ChunkResult, assigned.validated.entries.len);
        var index: usize = 0;
        for (assigned.validated.entries, chunks) |entry, *chunk| {
            chunk.scope = entry.scope;
            chunk.outcome = switch (entry.outcome) {
                .blocked => |reason| .{ .blocked = reason },
                .no_feature_claim => |reason| .{ .no_feature_claim = reason },
                .claims => |values| result: {
                    const ids = try allocator.alloc(extraction.ClaimId, values.len);
                    for (values, ids) |value, *id| {
                        if (index >= assigned.claims.len) return error.InvalidReferenceExtraction;
                        const assignment = assigned.claims[index];
                        index += 1;
                        if (assignment.citation_ids.len != value.citations.len) return error.InvalidReferenceExtraction;
                        id.* = assignment.claim_id;
                        try claims.append(allocator, .{ .id = id.*, .chunk_id = entry.scope.chunk_id, .content = value.content, .citation_ids = assignment.citation_ids });
                        for (value.citations, assignment.citation_ids) |citation, citation_id| try citations.append(allocator, .{ .id = citation_id, .value = citation });
                    }
                    break :result .{ .claims = ids };
                },
            };
        }
        if (index != assigned.claims.len) return error.InvalidReferenceExtraction;
        return .{ .state_id = assigned.validated.state_id, .chunks = chunks, .claims = try claims.toOwnedSlice(allocator), .citations = try citations.toOwnedSlice(allocator), .next_claim_ordinal = assigned.next_claim_ordinal, .next_citation_ordinal = assigned.next_citation_ordinal };
    }
};
