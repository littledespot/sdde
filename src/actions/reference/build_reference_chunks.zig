const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const evidence = @import("../../domain/reference_evidence.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "build-reference-chunks",
        .kind = .action,
        .requires = &.{.identified_reference_corpus},
        .produces = &.{.reference_chunks},
        .side_effect = .none,
    };

    pub fn execute(_: Action, allocator: std.mem.Allocator, corpus: evidence.Corpus) evidence.Error!evidence.Chunks {
        var chunks: std.ArrayList(evidence.Chunk) = .empty;
        for (corpus.sources) |source| for (source.blocks) |block| {
            const ordinal: u32 = @intCast(chunks.items.len + 1);
            try chunks.append(allocator, .{
                .id = try evidence.identity.chunkId(allocator, ordinal),
                .source_id = source.id,
                .block_id = block.id,
                .ordinal = 1,
                .span = block.span,
            });
        };
        return .{ .state_id = corpus.state_id, .partition = .source_blocks_v1, .entries = try chunks.toOwnedSlice(allocator) };
    }
};
