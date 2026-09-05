//! Lossless UTF-8 Markdown source reader, not a Markdown renderer or semantic AST.
const std = @import("std");
const reference = @import("../../domain/reference_ingestion.zig");
const decoder = @import("../../ports/reference_decoder.zig");
pub const reader_id = "markdown-source@1";

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
        var blocks: std.ArrayList(reference.BlockProposal) = .empty;
        errdefer blocks.deinit(allocator);
        var position: reference.Position = .{ .byte = 0, .line = 1, .column = 1 };
        var start = position;
        while (position.byte < bytes.len) {
            if (self.elapsed(started)) return error.DecodeLimitExceeded;
            const next = reference.advance(bytes, position) catch return error.MalformedText;
            if (next.byte - start.byte > reference.limits.block_bytes) {
                if (blocks.items.len == reference.limits.blocks_per_file) return error.DecodeLimitExceeded;
                try blocks.append(allocator, .{ .span = .{ .start = start, .end = position } });
                start = position;
            }
            position = next;
            if (position.line - start.line >= 64 or position.byte == bytes.len) {
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
