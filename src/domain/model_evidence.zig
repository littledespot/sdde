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
pub const Token = struct { claim_id: r.ClaimId, source_form: tokens.ExtractorId, id: tokens.Id, kind: tokens.Kind, value: []const u8, citation_id: r.CitationId };
pub const Projection = struct { claims: []const Claim, citations: []const r.extraction.Citation, exact_texts: []const Token };
pub const Source = struct { id: r.extraction.identity.SourceId, text: []const u8 };

/// Resolved source meaning for authoring. Native citations, token identity and
/// dependency state remain in their existing owners, not in the prose task.
pub const Requirement = struct { claim_id: r.ClaimId, kind: []const u8, meaning: []const u8, source_id: r.extraction.identity.SourceId };
pub const ExactLiteral = struct { claim_id: r.ClaimId, value: []const u8, source_id: r.extraction.identity.SourceId };
pub const Meaning = struct { kind: []const u8, meaning: []const u8 };
pub const ResolvedClaim = struct { id: r.ClaimId, kind: []const u8, meaning: []const u8, citation_ids: []const r.CitationId, source_id: r.extraction.identity.SourceId };
pub const ResolvedProjection = struct { claims: []const ResolvedClaim, citations: []const r.extraction.Citation, exact_texts: []const Token };
pub const Text = union(enum) { business: r.text.BusinessText, reference: r.text.ReferenceSemanticText };
/// The model-visible kind of an exact source value (ADR 0043), matching the
/// content codec's declared tag.
pub const exact_text_kind = r.ContentProposal.model_tags.preserved_token;

/// Caller owns an arena; projected text may borrow validated source bytes.
pub fn requirement(a: std.mem.Allocator, item: r.Item, inputs: r.evidence.Inputs, registry: @import("passive_literals.zig").Registry) r.Error!Requirement {
    const scope: r.evidence.Scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = item.claim.chunk_id };
    _ = try r.evidence.resolve(inputs, scope);
    if (item.claim.content == .preserved_token) return .{ .claim_id = item.claim.id, .kind = exact_text_kind, .meaning = item.claim.content.preserved_token.value.raw_value.bytes, .source_id = item.source_id };
    const resolved = try modelMeaning(a, inputs, registry, &.{scope}, item.claim.content.model);
    return .{ .claim_id = item.claim.id, .kind = resolved.kind, .meaning = resolved.meaning, .source_id = item.source_id };
}

/// Resolve only display handles authorized by the caller's existing claim scope.
/// The same projection serves authoring requirements and producer comparisons.
pub fn modelMeaning(a: std.mem.Allocator, inputs: r.evidence.Inputs, registry: @import("passive_literals.zig").Registry, scopes: []const r.evidence.Scope, value: r.extraction.Content) r.Error!Meaning {
    return switch (value) {
        inline else => |content_value, kind| .{ .kind = @tagName(kind), .meaning = try resolveText(a, inputs, registry, scopes, if (comptime kind == .business or kind == .scope_guard) .{ .business = content_value.value } else .{ .reference = content_value.value }) },
    };
}

pub fn resolveText(a: std.mem.Allocator, inputs: r.evidence.Inputs, registry: @import("passive_literals.zig").Registry, scopes: []const r.evidence.Scope, value: Text) r.Error![]const u8 {
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(a);
    for (scopes) |scope| _ = try r.evidence.resolve(inputs, scope);
    switch (value) {
        inline else => |text, kind| {
            const nodes = if (comptime kind == .business) text.segments else text.nodes;
            for (nodes) |node| switch (node) {
                .literal => |literal| try bytes.appendSlice(a, literal.value),
                .passive => |reference| try bytes.appendSlice(a, (try @import("passive_literals.zig").resolveIn(registry, inputs, scopes, reference.passive_literal_id)).value),
                inline else => |reference, tag| if (comptime std.mem.eql(u8, @tagName(tag), "source")) {
                    for (scopes) |scope| {
                        const source = try r.evidence.resolve(inputs, scope);
                        if (!std.meta.eql(source.source.id, reference.source_id)) continue;
                        try bytes.appendSlice(a, source.source.path.bytes);
                        break;
                    } else return error.InvalidReferenceReconciliation;
                } else return error.InvalidReferenceReconciliation,
            };
        },
    }
    return bytes.toOwnedSlice(a);
}

pub fn resolvedProject(a: std.mem.Allocator, items: []const r.Item, inputs: r.evidence.Inputs, registry: @import("passive_literals.zig").Registry) r.Error!ResolvedProjection {
    const projected = try project(a, items);
    defer a.free(projected.claims);
    const resolved = try a.alloc(ResolvedClaim, items.len);
    for (items, resolved) |item, *claim| {
        const text = try requirement(a, item, inputs, registry);
        claim.* = .{ .id = item.claim.id, .kind = text.kind, .meaning = text.meaning, .citation_ids = item.claim.citation_ids, .source_id = text.source_id };
    }
    return .{ .claims = resolved, .citations = projected.citations, .exact_texts = projected.exact_texts };
}

pub fn sources(a: std.mem.Allocator, inputs: r.evidence.Inputs) std.mem.Allocator.Error![]const Source {
    const result = try a.alloc(Source, inputs.corpus.sources.len);
    for (inputs.corpus.sources, result) |source, *copy| copy.* = .{ .id = source.id, .text = source.bytes };
    return result;
}

/// Every source's text for authoring after the user's answers. A line is left out when every claim that cites it was
/// superseded by an applied answer, so the text no longer states what the user decided against (ADR 0025, amended
/// 27 November 2026). A line another claim also cites stays, and a supersession the model proposed changes nothing:
/// with no answered supersession this is `sources`, byte for byte.
pub fn answeredSources(a: std.mem.Allocator, inputs: r.evidence.Inputs, items: r.Items, superseded: []const r.ClaimId) r.Error![]const Source {
    if (superseded.len == 0) return sources(a, inputs);
    const result = try a.alloc(Source, inputs.corpus.sources.len);
    for (inputs.corpus.sources, result) |source, *copy| {
        var dropped: std.ArrayList(u32) = .empty;
        var kept: std.ArrayList(u32) = .empty;
        for (items.entries) |item| {
            if (item.source_id.ordinal != source.id.ordinal) continue;
            const lines = if (r.contains(r.ClaimId, superseded, item.claim.id)) &dropped else &kept;
            for (item.citations) |citation| {
                const covered = @import("source_coordinates.zig").lines(citation.value.location) catch return error.InvalidReferenceReconciliation;
                var line = covered.first;
                while (line <= covered.last) : (line += 1) try lines.append(a, line);
            }
        }
        copy.* = .{ .id = source.id, .text = try withoutLines(a, source.bytes, dropped.items, kept.items) };
    }
    return result;
}

/// `bytes` without each line in `dropped` that is not also in `kept`. Lines are one-based and end as
/// `source_coordinates.advance` ends them, each keeping its ending.
fn withoutLines(a: std.mem.Allocator, bytes: []const u8, dropped: []const u32, kept: []const u32) std.mem.Allocator.Error![]const u8 {
    if (dropped.len == 0) return bytes;
    var text: std.ArrayList(u8) = .empty;
    var line: u32 = 1;
    var start: usize = 0;
    while (start < bytes.len) : (line += 1) {
        var at = start;
        while (at < bytes.len and bytes[at] != '\n' and bytes[at] != '\r') at += 1;
        const end = if (at == bytes.len) at else if (bytes[at] == '\r' and at + 1 < bytes.len and bytes[at + 1] == '\n') at + 2 else at + 1;
        const omitted = std.mem.indexOfScalar(u32, dropped, line) != null and std.mem.indexOfScalar(u32, kept, line) == null;
        if (!omitted) try text.appendSlice(a, bytes[start..end]);
        start = end;
    }
    return text.toOwnedSlice(a);
}

test "a line leaves the authoring text only when every claim citing it was superseded by an answer" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = "# Title\n- once\n- twice\r\n- both\rlast";
    // Line 3 is cited only by a superseded claim; line 4 by a superseded and a kept claim.
    try std.testing.expectEqualStrings("# Title\n- once\n- both\rlast", try withoutLines(a, bytes, &.{ 3, 4 }, &.{ 2, 4 }));
    try std.testing.expectEqualStrings("# Title\n- once\n- twice\r\n- both\r", try withoutLines(a, bytes, &.{5}, &.{}));
    try std.testing.expectEqualStrings(bytes, try withoutLines(a, bytes, &.{}, &.{}));
    try std.testing.expectEqualStrings(bytes, try withoutLines(a, bytes, &.{2}, &.{2}));
}
pub const Statement = struct { id: r.StatementId, claim_ids: []const r.ClaimId, content: r.ContentProposal };
pub const Summary = struct { id: r.SummaryId, partition_id: r.PartitionId, member_claim_ids: []const r.ClaimId, member_summary_ids: []const r.SummaryId, statements: []const Statement };
pub const Signal = struct { id: r.SignalId, value: struct { claim_ids: []const r.ClaimId, citation_ids: []const r.CitationId, content: r.ContentProposal } };
pub const Conflict = struct { id: r.ConflictId, value: struct { claim_ids: []const r.ClaimId, citation_ids: []const r.CitationId, kind: r.ConflictKind, summary: r.text.ReferenceSemanticText, resolution: @FieldType(r.ValidatedConflict, "resolution") } };

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
            try preserved.append(allocator, .{ .claim_id = item.claim.id, .source_form = token.value.candidate_id.extractor_id, .id = token.value.id, .kind = token.value.kind, .value = token.value.raw_value.bytes, .citation_id = token.citation_id });
        }
        for (item.citations) |citation| {
            for (citations.items) |prior| {
                if (prior.id.ordinal == citation.id.ordinal) break;
            } else try citations.append(allocator, citation);
        }
    }
    const citation_slice = try citations.toOwnedSlice(allocator);
    errdefer allocator.free(citation_slice);
    return .{ .claims = claims, .citations = citation_slice, .exact_texts = try preserved.toOwnedSlice(allocator) };
}

pub const ExtractionReview = struct {
    chunk_id: r.extraction.identity.ChunkId,
    source_id: r.extraction.identity.SourceId,
    location: @import("reference_ingestion.zig").Span,
    outcome: union(enum) { claims: []const r.ClaimId, no_feature_claim: r.text.ReferenceSemanticText, blocked: r.extraction.BlockReason },
    token_classifications: []const struct { candidate: ExactCandidate, decision: union(enum) { preserve: tokens.Kind, irrelevant } },
};

/// Source coordinates and choices suffice for review; execution state IDs,
/// native validation wrappers and duplicate claim bodies stay out of the packet.
pub fn extractionReview(a: std.mem.Allocator, inputs: r.evidence.Inputs, chunks: []const r.extraction.ChunkResult) r.Error![]const ExtractionReview {
    const facts = try tokens.extract(a, inputs);
    const candidates = try tokens.assign(a, inputs, facts);
    const result = try a.alloc(ExtractionReview, chunks.len);
    for (chunks, result) |chunk, *copy| {
        const source = try r.evidence.resolve(inputs, chunk.scope);
        const decisions = try a.alloc(std.meta.Child(@FieldType(ExtractionReview, "token_classifications")), chunk.token_classifications.len);
        for (chunk.token_classifications, decisions) |classification, *decision| {
            const candidate = for (candidates.entries) |candidate| {
                if (std.meta.eql(candidate.id, classification.id()) and candidate.fact.scope.chunk_id.eql(chunk.scope.chunk_id)) break candidate;
            } else return error.InvalidReferenceReconciliation;
            decision.* = .{ .candidate = exactCandidate(candidate), .decision = switch (classification) {
                .preserve => |value| .{ .preserve = value.kind },
                .irrelevant => .irrelevant,
            } };
        }
        copy.* = .{ .chunk_id = source.chunk.id, .source_id = source.source.id, .location = source.chunk.span, .token_classifications = decisions, .outcome = switch (chunk.outcome) {
            .claims => |ids| .{ .claims = ids },
            .no_feature_claim => |reason| .{ .no_feature_claim = reason.value },
            .blocked => |reason| .{ .blocked = reason },
        } };
    }
    return result;
}
