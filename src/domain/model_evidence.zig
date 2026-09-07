//! Model-facing projection of validated reference evidence. Canonical authority
//! stays in its existing owner; these borrowed views neither select nor validate it.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const tokens = @import("structured_tokens.zig");
pub const Claim = struct {
    id: r.ClaimId,
    content: union(enum) {
        model: r.extraction.Content,
        preserved_token: struct { id: tokens.Id, kind: tokens.Kind, value: []const u8, citation_id: r.CitationId },
    },
    citation_ids: []const r.CitationId,
};
pub const Projection = struct { claims: []const Claim, citations: []const r.extraction.Citation };
pub const ExactCandidate = struct {
    id: tokens.CandidateId,
    location: @import("reference_ingestion.zig").Span,
    verbatim: ?[]const u8,
};

pub fn exactCandidate(candidate: tokens.Candidate) ExactCandidate {
    return .{ .id = candidate.id, .location = candidate.fact.citation.location, .verbatim = candidate.fact.citation.verbatim };
}

/// Retains the entire supplied set and exact citation bytes, with one citation
/// record per canonical ID in first-use order. The caller owns the arrays only.
pub fn project(allocator: std.mem.Allocator, items: []const r.Item) std.mem.Allocator.Error!Projection {
    const claims = try allocator.alloc(Claim, items.len);
    errdefer allocator.free(claims);
    var citations: std.ArrayList(r.extraction.Citation) = .empty;
    errdefer citations.deinit(allocator);
    for (items, claims) |item, *claim| {
        claim.* = .{
            .id = item.claim.id,
            .citation_ids = item.claim.citation_ids,
            .content = switch (item.claim.content) {
                .model => |value| .{ .model = value },
                .preserved_token => |token| .{ .preserved_token = .{ .id = token.value.id, .kind = token.value.kind, .value = token.value.raw_value.bytes, .citation_id = token.citation_id } },
            },
        };
        for (item.citations) |citation| {
            for (citations.items) |prior| {
                if (prior.id.ordinal == citation.id.ordinal) break;
            } else try citations.append(allocator, citation);
        }
    }
    return .{ .claims = claims, .citations = try citations.toOwnedSlice(allocator) };
}
