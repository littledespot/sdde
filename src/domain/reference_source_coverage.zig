//! Contiguous, position-correct block coverage of one complete source.
const std = @import("std");
const r = @import("reference_ingestion.zig");

pub const Cursor = struct {
    bytes: []const u8,
    position: r.Position = .{ .byte = 0, .line = 1, .column = 1 },

    pub fn accept(self: *Cursor, span: r.Span) r.Error!void {
        if (!std.meta.eql(span.start, self.position) or span.end.byte <= self.position.byte or
            span.end.byte > self.bytes.len or span.end.byte - self.position.byte > r.limits.block_bytes) return error.InvalidReferenceAccounting;
        while (self.position.byte < span.end.byte) self.position = try r.advance(self.bytes, self.position);
        if (!std.meta.eql(span.end, self.position)) return error.InvalidReferenceAccounting;
    }

    pub fn finish(self: Cursor) r.Error!void {
        if (self.position.byte != self.bytes.len) return error.InvalidReferenceAccounting;
    }
};
