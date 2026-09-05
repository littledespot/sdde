const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const reference = @import("../../domain/reference_ingestion.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-reference-accounting@1",
        .kind = .action,
        .requires = &.{.decoded_reference_corpus},
        .produces = &.{.reference_inputs},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, candidate: reference.DecodedCorpus) reference.Error!reference.Inputs {
        const inventory = candidate.captured.inventory;
        if (inventory.entries.len > reference.limits.entries or candidate.entries.len != inventory.entries.len or
            candidate.captured.entries.len != inventory.entries.len) return error.InvalidReferenceAccounting;
        var documents: std.ArrayList(reference.Document) = .empty;
        var source_total: usize = 0;
        var decoded_total: usize = 0;
        var revisions: u32 = 0;
        for (inventory.entries, candidate.captured.entries, candidate.entries, 0..) |entry, captured, decoded, index| {
            if (entry.id.ordinal != index + 1 or !sameEntry(entry, captured.entry) or
                !sameEntry(entry, decoded.captured.entry)) return error.InvalidReferenceAccounting;
            switch (entry.observation) {
                .directory => {
                    if (captured.source != .directory or captured.debit != null or decoded.result != .directory or decoded.debit != null) return error.InvalidReferenceAccounting;
                    continue;
                },
                .file => {},
                .symlink, .special, .unreadable => return error.InvalidReferenceAccounting,
            }
            if (captured.source != .bytes or decoded.captured.source != .bytes) return error.InvalidReferenceAccounting;
            const bytes = captured.source.bytes;
            if (!std.mem.eql(u8, bytes, decoded.captured.source.bytes) or bytes.len != entry.observation.file.size or
                bytes.len > reference.limits.source_file_bytes or bytes.len > reference.limits.source_corpus_bytes - source_total or
                bytes.len > reference.limits.decoded_corpus_bytes - decoded_total) return error.InvalidReferenceAccounting;
            try debit(captured.debit, bytes.len);
            try debit(decoded.captured.debit, bytes.len);
            try debit(decoded.debit, bytes.len);
            revisions += 1;
            source_total += bytes.len;
            const result = switch (decoded.result) {
                .decoded => |value| if (bytes.len != 0) value else return error.InvalidReferenceAccounting,
                .empty => |value| if (bytes.len == 0) value else return error.InvalidReferenceAccounting,
                .directory, .blocked => return error.InvalidReferenceAccounting,
            };
            if (result.blocks.len > reference.limits.blocks_per_file) return error.InvalidReferenceAccounting;
            const blocks = try allocator.alloc(reference.Block, result.blocks.len);
            var position: reference.Position = .{ .byte = 0, .line = 1, .column = 1 };
            for (result.blocks, 0..) |block, block_index| {
                if (!std.meta.eql(block.span.start, position) or block.span.end.byte <= position.byte or
                    block.span.end.byte > bytes.len or block.span.end.byte - position.byte > reference.limits.block_bytes) return error.InvalidReferenceAccounting;
                while (position.byte < block.span.end.byte) position = try reference.advance(bytes, position);
                if (!std.meta.eql(block.span.end, position)) return error.InvalidReferenceAccounting;
                blocks[block_index] = .{ .id = .{ .source = entry.id, .ordinal = @intCast(block_index + 1) }, .span = block.span };
            }
            if (position.byte != bytes.len) return error.InvalidReferenceAccounting;
            decoded_total += bytes.len;
            try documents.append(allocator, .{ .source = entry.id, .path = entry.path, .reader = result.reader, .media = result.media, .bytes = bytes, .blocks = blocks });
        }
        if (source_total != candidate.captured.source_bytes or decoded_total != candidate.decoded_bytes or
            revisions != candidate.budget_revision or revisions != candidate.captured.budget_revision) return error.InvalidReferenceAccounting;
        return .{ .inventory = inventory, .documents = try documents.toOwnedSlice(allocator), .source_bytes = source_total, .decoded_bytes = decoded_total };
    }
};
fn sameEntry(a: reference.Entry, b: reference.Entry) bool {
    return a.id.ordinal == b.id.ordinal and std.mem.eql(u8, a.path.bytes, b.path.bytes) and
        std.mem.eql(u8, a.raw_path, b.raw_path) and std.meta.eql(a.observation, b.observation);
}
fn debit(value: ?reference.Debit, expected: usize) reference.Error!void {
    const record = value orelse return error.InvalidReferenceAccounting;
    if (record.reserved != expected or record.outcome != .committed or record.outcome.committed != expected) return error.InvalidReferenceAccounting;
}
