const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const reference = @import("../../domain/reference_ingestion.zig");
const evidence = @import("../../domain/reference_evidence.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-source-citations@1",
        .kind = .action,
        .requires = &.{ .citable_reference_inputs, .reference_citation_proposals },
        .produces = &.{.validated_source_citations},
        .side_effect = .none,
    };

    /// Structural citation proof only; this does not prove semantic support.
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: evidence.Inputs, proposals: evidence.CitationProposals) evidence.Error!evidence.ValidatedCitations {
        const selected = try evidence.resolve(inputs, proposals.scope);
        if (proposals.entries.len == 0) return error.InvalidSourceCitation;
        const citations = try allocator.alloc(evidence.ValidatedCitation, proposals.entries.len);
        errdefer allocator.free(citations);
        for (proposals.entries, citations) |proposal, *citation| {
            const span = proposal.location;
            if (proposal.source_id.ordinal != selected.source.id.ordinal or proposal.block_id.ordinal != selected.chunk.block_id.ordinal or
                span.start.byte < selected.chunk.span.start.byte or span.start.byte >= span.end.byte or
                span.end.byte > selected.chunk.span.end.byte) return error.InvalidSourceCitation;
            var position = selected.chunk.span.start;
            while (position.byte < span.start.byte) position = reference.advance(selected.source.bytes, position) catch return error.InvalidSourceCitation;
            if (!std.meta.eql(position, span.start)) return error.InvalidSourceCitation;
            while (position.byte < span.end.byte) position = reference.advance(selected.source.bytes, position) catch return error.InvalidSourceCitation;
            if (!std.meta.eql(position, span.end)) return error.InvalidSourceCitation;
            const exact = selected.source.bytes[span.start.byte..span.end.byte];
            if (proposal.verbatim) |text| if (!std.mem.eql(u8, text, exact)) return error.InvalidSourceCitation;
            citation.* = .{ .source_id = proposal.source_id, .block_id = proposal.block_id, .location = span, .verbatim = if (proposal.verbatim != null) exact else null };
        }
        return .{ .scope = proposals.scope, .entries = citations };
    }
};
