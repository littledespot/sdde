const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const reference = @import("../../domain/reference_ingestion.zig");
const port = @import("../../ports/reference_decoder.zig");
pub const Action = struct {
    decoder: port.Decoder,
    pub const contract: pipeline.NodeContract = .{
        .id = "decode-reference-markdown@1",
        .kind = .action,
        .requires = &.{.captured_reference_corpus},
        .produces = &.{.decoded_reference_corpus},
        .side_effect = .none,
    };
    pub fn execute(self: Action, allocator: std.mem.Allocator, captured: reference.CapturedCorpus) std.mem.Allocator.Error!reference.DecodedCorpus {
        const entries = try allocator.alloc(reference.DecodedEntry, captured.entries.len);
        var total: usize = 0;
        var revision: u32 = 0;
        for (captured.entries, 0..) |item, index| {
            var entry: reference.DecodedEntry = .{ .captured = item, .result = .{ .blocked = .decoder_failure }, .debit = null };
            switch (item.source) {
                .directory => entry.result = .{ .directory = {} },
                .blocked => |failure| entry.result = .{ .blocked = failure },
                .bytes => |bytes| decode: {
                    if (bytes.len > reference.limits.decoded_corpus_bytes - total) {
                        entry.result = .{ .blocked = .decoded_budget };
                        break :decode;
                    }
                    revision += 1;
                    entry.debit = .{ .reserved = bytes.len, .outcome = .{ .released = {} } };
                    const decoded = self.decoder.decode(allocator, item.entry.path, bytes, bytes.len) catch |err| {
                        entry.result = .{ .blocked = switch (err) {
                            error.OutOfMemory => return error.OutOfMemory,
                            error.UnsupportedMedia => .unsupported_media,
                            error.MalformedText => .malformed_text,
                            error.DecodeLimitExceeded => .decoded_budget,
                        } };
                        break :decode;
                    };
                    entry.result = if (bytes.len == 0) .{ .empty = decoded } else .{ .decoded = decoded };
                    entry.debit = .{ .reserved = bytes.len, .outcome = .{ .committed = bytes.len } };
                    total += bytes.len;
                },
            }
            entries[index] = entry;
        }
        return .{ .captured = captured, .entries = entries, .decoded_bytes = total, .budget_revision = revision };
    }
};
