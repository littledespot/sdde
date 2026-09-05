const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const reference = @import("../../domain/reference_ingestion.zig");
const evidence = @import("../../domain/reference_evidence.zig");
const state_source = @import("../../ports/reference_state_identity.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "assign-reference-identities@1",
        .kind = .action,
        .requires = &.{ .reference_inputs, .feature_directory },
        .produces = &.{.identified_reference_corpus},
        .side_effect = .none,
    };
    identities: state_source.Source,

    /// Slices borrow the validated inputs; new records belong to the caller's arena.
    pub fn execute(self: Action, allocator: std.mem.Allocator, inputs: reference.Inputs, feature: @import("../../domain/feature_identity.zig").FeatureId) (evidence.Error || state_source.Error)!evidence.Corpus {
        const sources = try allocator.alloc(evidence.Source, inputs.documents.len);
        const mappings = try allocator.alloc(evidence.SourceMapping, sources.len);
        var block_mappings: std.ArrayList(evidence.BlockMapping) = .empty;
        for (inputs.documents, 0..) |document, index| {
            const source_id: evidence.identity.SourceId = .{ .ordinal = @intCast(index + 1) };
            mappings[index] = .{ .provisional = document.source, .canonical = source_id };
            const blocks = try allocator.alloc(evidence.Block, document.blocks.len);
            for (document.blocks, 0..) |block, block_index| {
                const block_id: evidence.identity.BlockId = .{ .ordinal = @intCast(block_mappings.items.len + 1) };
                blocks[block_index] = .{ .id = block_id, .ordinal = @intCast(block_index + 1), .span = block.span };
                try block_mappings.append(allocator, .{ .provisional = block.id, .canonical = block_id });
            }
            sources[index] = .{ .id = source_id, .path = document.path, .reader = document.reader, .bytes = document.bytes, .blocks = blocks };
        }
        return .{
            .state_id = try evidence.identity.stateId(allocator, try self.identities.next()),
            .feature_id = feature,
            .sources = sources,
            .source_mappings = mappings,
            .block_mappings = try block_mappings.toOwnedSlice(allocator),
        };
    }
};
