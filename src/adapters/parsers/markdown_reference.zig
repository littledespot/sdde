//! Lossless UTF-8 Markdown source reader, not a Markdown renderer or semantic AST.
const std = @import("std");
const reference = @import("../../domain/reference_ingestion.zig");
const decoder = @import("../../ports/reference_decoder.zig");
pub const reader_id: reference.ReaderId = .markdown_source_v1;

pub const Adapter = struct {
    io: std.Io,
    pub fn decoderPort(self: *Adapter) decoder.Decoder {
        return .{ .context = self, .decode_fn = decode };
    }
    fn decode(context: *anyopaque, allocator: std.mem.Allocator, path: reference.RelativePath, bytes: []const u8, maximum: usize) decoder.Error!reference.Decoded {
        const self: *Adapter = @ptrCast(@alignCast(context));
        if (bytes.len > maximum or bytes.len > reference.limits.source_file_bytes) return error.DecodeLimitExceeded;
        // Markdown has no reliable magic number. Require both its registered
        // extension and valid text; reject recognized foreign binary signatures.
        if (!std.ascii.endsWithIgnoreCase(path.bytes, ".md") and !std.ascii.endsWithIgnoreCase(path.bytes, ".markdown")) return error.UnsupportedMedia;
        for ([_][]const u8{ "%PDF-", "\x89PNG\r\n", "PK\x03\x04", "\xff\xd8\xff", "GIF87a", "GIF89a" }) |magic| {
            if (std.mem.startsWith(u8, bytes, magic)) return error.UnsupportedMedia;
        }
        if (!std.unicode.utf8ValidateSlice(bytes)) return error.MalformedText;
        for (bytes) |byte| if ((byte < 32 and byte != '\t' and byte != '\r' and byte != '\n') or byte == 127) return error.MalformedText;
        const started: std.Io.Clock.Timestamp = .now(self.io, .boot);
        const exact_spans = try @import("../../domain/markdown_code_spans.zig").scan(allocator, bytes);
        defer allocator.free(exact_spans);
        var exact_index: usize = 0;
        var blocks: std.ArrayList(reference.BlockProposal) = .empty;
        errdefer blocks.deinit(allocator);
        var position: reference.Position = .{ .byte = 0, .line = 1, .column = 1 };
        var start = position;
        var check_at: usize = 0;
        while (position.byte < bytes.len) {
            if (position.byte >= check_at) {
                if (self.elapsed(started)) return error.DecodeLimitExceeded;
                check_at = position.byte + 4096;
            }
            const next = reference.advance(bytes, position) catch return error.MalformedText;
            while (exact_index < exact_spans.len and position.byte >= exact_spans[exact_index].end) exact_index += 1;
            if (exact_index < exact_spans.len and position.byte == exact_spans[exact_index].start and exact_spans[exact_index].end - start.byte > reference.limits.block_bytes) {
                if (exact_spans[exact_index].end - position.byte > reference.limits.block_bytes) return error.DecodeLimitExceeded;
                if (position.byte > start.byte) {
                    if (blocks.items.len == reference.limits.blocks_per_file) return error.DecodeLimitExceeded;
                    try blocks.append(allocator, .{ .span = .{ .start = start, .end = position } });
                    start = position;
                }
            }
            const inside_exact = exact_index < exact_spans.len and position.byte > exact_spans[exact_index].start and position.byte < exact_spans[exact_index].end;
            if (next.byte - start.byte > reference.limits.block_bytes) {
                if (inside_exact) return error.DecodeLimitExceeded;
                if (blocks.items.len == reference.limits.blocks_per_file) return error.DecodeLimitExceeded;
                try blocks.append(allocator, .{ .span = .{ .start = start, .end = position } });
                start = position;
            }
            position = next;
            const splits_exact = exact_index < exact_spans.len and position.byte > exact_spans[exact_index].start and position.byte < exact_spans[exact_index].end;
            if ((!splits_exact and position.line - start.line >= 64) or position.byte == bytes.len) {
                if (blocks.items.len == reference.limits.blocks_per_file) return error.DecodeLimitExceeded;
                try blocks.append(allocator, .{ .span = .{ .start = start, .end = position } });
                start = position;
            }
        }
        return .{ .reader = reader_id, .media = .markdown, .blocks = try blocks.toOwnedSlice(allocator) };
    }
    fn elapsed(self: *Adapter, started: std.Io.Clock.Timestamp) bool {
        return started.durationTo(.now(self.io, .boot)).raw.toMilliseconds() > reference.limits.duration_ms;
    }
};
