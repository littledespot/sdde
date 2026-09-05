const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const reference = @import("../../domain/reference_ingestion.zig");
const evidence = @import("../../domain/reference_evidence.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-reference-chunks@1",
        .kind = .action,
        .requires = &.{ .reference_inputs, .feature_directory, .identified_reference_corpus, .reference_chunks },
        .produces = &.{.citable_reference_inputs},
        .side_effect = .none,
    };

    pub fn execute(_: Action, inputs: reference.Inputs, feature: @import("../../domain/feature_identity.zig").FeatureId, corpus: evidence.Corpus, chunks: evidence.Chunks) evidence.Error!evidence.Inputs {
        if (!std.mem.eql(u8, feature.bytes, corpus.feature_id.bytes) or !corpus.state_id.eql(chunks.state_id) or
            corpus.sources.len != inputs.documents.len or corpus.source_mappings.len != inputs.documents.len or
            corpus.block_mappings.len != chunks.entries.len) return error.InvalidReferenceChunks;
        var index: usize = 0;
        for (inputs.documents, corpus.sources, corpus.source_mappings, 0..) |document, source, mapping, source_index| {
            if (source.id.ordinal != source_index + 1 or mapping.canonical.ordinal != source.id.ordinal or
                mapping.provisional.ordinal != document.source.ordinal or source.reader != document.reader or
                !std.mem.eql(u8, source.path.bytes, document.path.bytes) or !std.mem.eql(u8, source.bytes, document.bytes) or
                source.blocks.len != document.blocks.len) return error.InvalidReferenceChunks;
            for (document.blocks, source.blocks, 0..) |original, block, ordinal| {
                if (index >= chunks.entries.len) return error.InvalidReferenceChunks;
                const chunk = chunks.entries[index];
                const block_mapping = corpus.block_mappings[index];
                var id_buffer: [32]u8 = undefined;
                const expected_id = evidence.identity.formatChunkId(&id_buffer, @intCast(index + 1));
                if (block.id.ordinal != index + 1 or block.ordinal != ordinal + 1 or
                    !std.meta.eql(original.id, block_mapping.provisional) or block_mapping.canonical.ordinal != block.id.ordinal or
                    !std.meta.eql(original.span, block.span) or !std.meta.eql(block.span, chunk.span) or
                    !chunk.id.eql(expected_id) or chunk.ordinal != 1 or
                    chunk.block_id.ordinal != block.id.ordinal or chunk.source_id.ordinal != source.id.ordinal) return error.InvalidReferenceChunks;
                index += 1;
            }
        }
        if (index != chunks.entries.len) return error.InvalidReferenceChunks;
        return .{ .corpus = corpus, .chunks = chunks };
    }
};
