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
        return @import("../../domain/reference_chunk_partition.zig").partition(allocator, corpus);
    }
};
