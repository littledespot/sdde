//! Exact source candidates and preservation identities, never path capabilities.
const std = @import("std");
const evidence = @import("reference_evidence.zig");
const source = @import("reference_ingestion.zig");
const citation = @import("source_citations.zig");
pub const Error = evidence.Error || error{InvalidStructuredTokens};
pub const ExtractorId = enum { markdown_inline_code_v1 };
pub const Descriptor = struct { id: ExtractorId, eligibility: enum { exact_value } };
pub const markdown: Descriptor = .{ .id = .markdown_inline_code_v1, .eligibility = .exact_value };
pub const CandidateId = struct { source_id: evidence.identity.SourceId, extractor_id: ExtractorId, ordinal: u32 };
pub const Fact = struct { extractor_id: ExtractorId, scope: evidence.Scope, citation: evidence.ValidatedCitation };
pub const Facts = struct { state_id: evidence.identity.StateId, entries: []const Fact };
pub const Candidate = struct { id: CandidateId, fact: Fact };
pub const Candidates = struct { state_id: evidence.identity.StateId, entries: []const Candidate };
pub const Kind = enum { visual_color, visual_spacing, visual_dimension, visual_typography, visual_radius, visual_shadow, visual_motion, business_exact_string, numeric_constraint, exact_identifier };
pub const Classification = union(enum) {
    preserve: struct { token_candidate_id: CandidateId, kind: Kind },
    irrelevant: CandidateId,
    pub fn id(self: Classification) CandidateId {
        return switch (self) {
            .preserve => |value| value.token_candidate_id,
            .irrelevant => |value| value,
        };
    }
};
pub const Id = struct { ordinal: u32 };
pub const ObligationId = struct { token_id: Id };
pub const RawSourceScalar = struct { bytes: []const u8 };
/// Canonical citation IDs are bound by the ordinary claim/citation builder.
pub const Value = struct { id: Id, candidate_id: CandidateId, kind: Kind, raw_value: RawSourceScalar, downstream_obligation_id: ObligationId };
pub const Token = struct { value: Value, citation_id: evidence.identity.CitationId };
pub const Decision = union(enum) { preserve: Kind, irrelevant: void, blocked: void };
pub const Selected = struct { candidate: Candidate, decision: Decision };
pub const Assignment = struct { selection_index: usize, id: Id };

/// The registered extractor alone decides eligibility. Capture/reader selection
/// already happened; no filesystem access or model-authored scalar is accepted.
pub fn extract(allocator: std.mem.Allocator, inputs: evidence.Inputs) Error!Facts {
    if (!inputs.corpus.state_id.eql(inputs.chunks.state_id)) return error.InvalidStructuredTokens;
    var facts: std.ArrayList(Fact) = .empty;
    errdefer facts.deinit(allocator);
    for (inputs.corpus.sources) |document| {
        const ranges = switch (document.reader) {
            .markdown_source_v1 => try @import("markdown_code_spans.zig").scan(allocator, document.bytes),
        };
        defer allocator.free(ranges);
        var position: source.Position = .{ .byte = 0, .line = 1, .column = 1 };
        for (ranges) |range| {
            while (position.byte < range.start) position = source.advance(document.bytes, position) catch return error.InvalidStructuredTokens;
            const start = position;
            while (position.byte < range.end) position = source.advance(document.bytes, position) catch return error.InvalidStructuredTokens;
            if (start.byte != range.start or position.byte != range.end) return error.InvalidStructuredTokens;
            var selected: ?evidence.Chunk = null;
            for (inputs.chunks.entries) |chunk| {
                if (chunk.source_id.ordinal != document.id.ordinal or start.byte < chunk.span.start.byte or position.byte > chunk.span.end.byte) continue;
                if (selected != null) return error.InvalidStructuredTokens;
                selected = chunk;
            }
            const chunk = selected orelse return error.InvalidStructuredTokens;
            const scope: evidence.Scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = chunk.id };
            const checked = try citation.validate(allocator, inputs, .{ .scope = scope, .entries = &.{.{ .source_id = document.id, .block_id = chunk.block_id, .location = .{ .start = start, .end = position }, .verbatim = document.bytes[range.start..range.end] }} });
            defer allocator.free(checked.entries);
            try facts.append(allocator, .{ .extractor_id = markdown.id, .scope = scope, .citation = checked.entries[0] });
        }
    }
    return .{ .state_id = inputs.corpus.state_id, .entries = try facts.toOwnedSlice(allocator) };
}

pub fn assign(allocator: std.mem.Allocator, inputs: evidence.Inputs, facts: Facts) Error!Candidates {
    // Replay the same source extractor: fabricated or omitted facts never mint IDs.
    const expected = try extract(allocator, inputs);
    defer allocator.free(expected.entries);
    if (!facts.state_id.eql(expected.state_id) or facts.entries.len != expected.entries.len) return error.InvalidStructuredTokens;
    for (facts.entries, expected.entries) |fact, actual| if (!equalFact(fact, actual)) return error.InvalidStructuredTokens;
    return identify(allocator, facts);
}

pub fn validateCandidates(allocator: std.mem.Allocator, inputs: evidence.Inputs, candidates: Candidates) Error!void {
    const facts = try extract(allocator, inputs);
    defer allocator.free(facts.entries);
    const expected = try identify(allocator, facts);
    defer allocator.free(expected.entries);
    if (!candidates.state_id.eql(expected.state_id) or candidates.entries.len != expected.entries.len) return error.InvalidStructuredTokens;
    for (candidates.entries, expected.entries) |candidate, actual| {
        if (!std.meta.eql(candidate.id, actual.id) or !equalFact(candidate.fact, actual.fact)) return error.InvalidStructuredTokens;
    }
}

fn identify(allocator: std.mem.Allocator, facts: Facts) Error!Candidates {
    const entries = try allocator.alloc(Candidate, facts.entries.len);
    errdefer allocator.free(entries);
    var source_id: u32 = 0;
    var ordinals: std.EnumArray(ExtractorId, u32) = .initFill(0);
    for (entries, facts.entries) |*candidate, fact| {
        if (source_id != fact.citation.source_id.ordinal) {
            source_id = fact.citation.source_id.ordinal;
            ordinals = .initFill(0);
        }
        const ordinal = std.math.add(u32, ordinals.get(fact.extractor_id), 1) catch return error.InvalidStructuredTokens;
        ordinals.set(fact.extractor_id, ordinal);
        candidate.* = .{ .id = .{ .source_id = fact.citation.source_id, .extractor_id = fact.extractor_id, .ordinal = ordinal }, .fact = fact };
    }
    return .{ .state_id = facts.state_id, .entries = entries };
}

pub fn equalFact(a: Fact, b: Fact) bool {
    return a.extractor_id == b.extractor_id and a.scope.state_id.eql(b.scope.state_id) and a.scope.chunk_id.eql(b.scope.chunk_id) and
        a.citation.source_id.ordinal == b.citation.source_id.ordinal and a.citation.block_id.ordinal == b.citation.block_id.ordinal and
        std.meta.eql(a.citation.location, b.citation.location) and a.citation.verbatim != null and b.citation.verbatim != null and std.mem.eql(u8, a.citation.verbatim.?, b.citation.verbatim.?);
}

/// Caller-owned arena retains each copied candidate on all paths.
pub fn copy(allocator: std.mem.Allocator, candidate: Candidate) std.mem.Allocator.Error!Candidate {
    var result = candidate;
    result.fact.scope.state_id.bytes = try allocator.dupe(u8, candidate.fact.scope.state_id.bytes);
    result.fact.scope.chunk_id.bytes = try allocator.dupe(u8, candidate.fact.scope.chunk_id.bytes);
    result.fact.citation.verbatim = try allocator.dupe(u8, candidate.fact.citation.verbatim.?);
    return result;
}
