//! Immutable execution candidates. No claims, persisted snapshot or completion.
const std = @import("std");
const input = @import("reference_ingestion.zig");
pub const identity = @import("reference_identity.zig");
pub const Error = std.mem.Allocator.Error || error{ InvalidReferenceChunks, InvalidSourceCitation };

pub const Block = struct {
    id: identity.BlockId,
    ordinal: u32,
    span: input.Span,
};
pub const Source = struct {
    id: identity.SourceId,
    path: input.RelativePath,
    reader: input.ReaderId,
    bytes: []const u8,
    blocks: []const Block,
};
pub const SourceMapping = struct { provisional: input.SourceId, canonical: identity.SourceId };
pub const BlockMapping = struct { provisional: input.BlockId, canonical: identity.BlockId };
pub const Corpus = struct {
    state_id: identity.StateId,
    feature_id: @import("feature_identity.zig").FeatureId,
    sources: []const Source,
    source_mappings: []const SourceMapping,
    block_mappings: []const BlockMapping,
};
pub const Chunk = struct {
    id: identity.ChunkId,
    source_id: identity.SourceId,
    block_id: identity.BlockId,
    ordinal: u32,
    /// Identity source map for the current lossless reader; bytes are never copied
    /// into a competing chunk body or reread from a source path.
    span: input.Span,
};
pub const Chunks = struct {
    state_id: identity.StateId,
    partition: enum { source_blocks_v1 },
    entries: []const Chunk,
};
pub const Inputs = struct { corpus: Corpus, chunks: Chunks };

/// Engine-supplied call scope, never a field selected by the model proposal.
pub const Scope = struct { state_id: identity.StateId, chunk_id: identity.ChunkId };
pub const CitationProposal = struct {
    source_id: identity.SourceId,
    block_id: identity.BlockId,
    location: input.Span,
    verbatim: ?[]const u8,
};
pub const CitationProposals = struct { scope: Scope, entries: []const CitationProposal };
pub const ValidatedCitation = struct {
    source_id: identity.SourceId,
    block_id: identity.BlockId,
    location: input.Span,
    /// Always borrowed from the captured source, never retained model text.
    verbatim: ?[]const u8,
};
pub const ValidatedCitations = struct { scope: Scope, entries: []const ValidatedCitation };

pub const ChunkView = struct { chunk: Chunk, source: Source, bytes: []const u8 };

/// Resolve only against the validated current inputs, not a global ID lookup.
pub fn resolve(inputs: Inputs, scope: Scope) Error!ChunkView {
    if (!inputs.corpus.state_id.eql(scope.state_id) or !inputs.chunks.state_id.eql(scope.state_id)) return error.InvalidSourceCitation;
    var selected: ?Chunk = null;
    for (inputs.chunks.entries) |chunk| {
        if (!chunk.id.eql(scope.chunk_id)) continue;
        if (selected != null) return error.InvalidSourceCitation;
        selected = chunk;
    }
    const chunk = selected orelse return error.InvalidSourceCitation;
    const ordinal = chunk.source_id.ordinal;
    if (ordinal == 0 or ordinal > inputs.corpus.sources.len) return error.InvalidSourceCitation;
    const source = inputs.corpus.sources[ordinal - 1];
    if (source.id.ordinal != ordinal or chunk.span.start.byte >= chunk.span.end.byte or chunk.span.end.byte > source.bytes.len) return error.InvalidSourceCitation;
    return .{ .chunk = chunk, .source = source, .bytes = source.bytes[chunk.span.start.byte..chunk.span.end.byte] };
}
