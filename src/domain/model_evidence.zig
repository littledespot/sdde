//! Model-facing projection of validated reference evidence. Canonical authority
//! stays in its existing owner; these borrowed views neither select nor validate it.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const tokens = @import("structured_tokens.zig");
pub const Claim = struct {
    id: r.ClaimId,
    content: r.ContentProposal,
    citation_ids: []const r.CitationId,
};
pub const Token = struct { id: tokens.Id, kind: tokens.Kind, value: []const u8, citation_id: r.CitationId };
pub const Projection = struct { claims: []const Claim, citations: []const r.extraction.Citation, preserved_tokens: []const Token };
pub const Statement = struct { id: r.StatementId, claim_ids: []const r.ClaimId, content: r.ContentProposal };
pub const Summary = struct { id: r.SummaryId, partition_id: r.PartitionId, member_claim_ids: []const r.ClaimId, member_summary_ids: []const r.SummaryId, statements: []const Statement };
pub const Signal = struct { id: r.SignalId, value: r.SignalProposal };
pub const Conflict = struct { id: r.ConflictId, value: r.ConflictProposal };

pub fn modelContent(value: r.extraction.Content) r.extraction.ProposalContent {
    return switch (value) {
        inline else => |text, tag| @unionInit(r.extraction.ProposalContent, @tagName(tag), text.value),
    };
}

pub fn content(value: r.Content) r.ContentProposal {
    return switch (value) {
        .model => |model| .{ .model = modelContent(model) },
        .preserved_token => |token| .{ .preserved_token = token },
    };
}

// Caller-owned arena arrays; underlying text and identities remain borrowed.
pub fn summaries(a: std.mem.Allocator, values: []const r.Summary) std.mem.Allocator.Error![]const Summary {
    const result = try a.alloc(Summary, values.len);
    for (values, result) |value, *copy| {
        const statements = try a.alloc(Statement, value.statements.len);
        for (value.statements, statements) |statement, *item| item.* = .{ .id = statement.id, .claim_ids = statement.claim_ids, .content = content(statement.content) };
        copy.* = .{ .id = value.id, .partition_id = value.partition_id, .member_claim_ids = value.member_claim_ids, .member_summary_ids = value.member_summary_ids, .statements = statements };
    }
    return result;
}

pub fn signals(a: std.mem.Allocator, values: []const r.Signal) std.mem.Allocator.Error![]const Signal {
    const result = try a.alloc(Signal, values.len);
    for (values, result) |value, *copy| copy.* = .{ .id = value.id, .value = .{ .claim_ids = value.value.claim_ids, .citation_ids = value.value.citation_ids, .content = content(value.value.content) } };
    return result;
}

pub fn conflicts(a: std.mem.Allocator, values: []const r.Conflict) std.mem.Allocator.Error![]const Conflict {
    const result = try a.alloc(Conflict, values.len);
    for (values, result) |value, *copy| copy.* = .{ .id = value.id, .value = .{ .claim_ids = value.value.claim_ids, .citation_ids = value.value.citation_ids, .kind = value.value.kind, .summary = value.value.summary.value, .resolution = switch (value.value.resolution) {
        .unresolved => .unresolved,
    } } };
    return result;
}
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
    var preserved: std.ArrayList(Token) = .empty;
    errdefer preserved.deinit(allocator);
    for (items, claims) |item, *claim| {
        claim.* = .{
            .id = item.claim.id,
            .citation_ids = item.claim.citation_ids,
            .content = switch (item.claim.content) {
                .model => |value| .{ .model = modelContent(value) },
                .preserved_token => |token| .{ .preserved_token = .{ .token_id = token.value.id } },
            },
        };
        if (item.claim.content == .preserved_token) {
            const token = item.claim.content.preserved_token;
            for (preserved.items) |prior| {
                if (prior.id.ordinal == token.value.id.ordinal) break;
            } else try preserved.append(allocator, .{ .id = token.value.id, .kind = token.value.kind, .value = token.value.raw_value.bytes, .citation_id = token.citation_id });
        }
        for (item.citations) |citation| {
            for (citations.items) |prior| {
                if (prior.id.ordinal == citation.id.ordinal) break;
            } else try citations.append(allocator, citation);
        }
    }
    const citation_slice = try citations.toOwnedSlice(allocator);
    errdefer allocator.free(citation_slice);
    return .{ .claims = claims, .citations = citation_slice, .preserved_tokens = try preserved.toOwnedSlice(allocator) };
}
