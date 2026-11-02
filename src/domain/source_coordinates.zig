const std = @import("std");
pub const Position = struct { byte: usize, line: u32, column: u32 };
pub const Span = struct { start: Position, end: Position };
/// One-based, inclusive.
pub const Lines = struct { first: u32, last: u32 };

/// The lines a span covers. The end is exclusive and a line's span includes its
/// ending, so an end at column 1 of a later line closes the line before it.
pub fn lines(span: Span) error{InvalidSourcePosition}!Lines {
    const last = if (span.end.column == 1 and span.end.line > span.start.line) span.end.line - 1 else span.end.line;
    if (span.start.line == 0 or last < span.start.line) return error.InvalidSourcePosition;
    return .{ .first = span.start.line, .last = last };
}

test "a span's lines close before an end at column 1 and include a line ended mid-way" {
    const at = struct {
        fn position(line: u32, column: u32) Position {
            return .{ .byte = 0, .line = line, .column = column };
        }
    };
    // A whole line, a line run, a token ending mid-line, a last line without its
    // ending, and an empty span at the start of a line.
    try std.testing.expectEqual(Lines{ .first = 5, .last = 5 }, try lines(.{ .start = at.position(5, 1), .end = at.position(6, 1) }));
    try std.testing.expectEqual(Lines{ .first = 5, .last = 7 }, try lines(.{ .start = at.position(5, 1), .end = at.position(8, 1) }));
    try std.testing.expectEqual(Lines{ .first = 6, .last = 6 }, try lines(.{ .start = at.position(6, 9), .end = at.position(6, 23) }));
    try std.testing.expectEqual(Lines{ .first = 3, .last = 4 }, try lines(.{ .start = at.position(3, 1), .end = at.position(4, 12) }));
    try std.testing.expectEqual(Lines{ .first = 2, .last = 2 }, try lines(.{ .start = at.position(2, 1), .end = at.position(2, 1) }));
    try std.testing.expectError(error.InvalidSourcePosition, lines(.{ .start = at.position(0, 1), .end = at.position(1, 1) }));
    try std.testing.expectError(error.InvalidSourcePosition, lines(.{ .start = at.position(4, 1), .end = at.position(3, 5) }));
}

/// Shared byte-coordinate advancement; this does not interpret Markdown.
pub fn advance(bytes: []const u8, position: Position) error{InvalidSourcePosition}!Position {
    if (position.byte >= bytes.len) return error.InvalidSourcePosition;
    var result = position;
    const byte = bytes[position.byte];
    const length = std.unicode.utf8ByteSequenceLength(byte) catch return error.InvalidSourcePosition;
    if (length > bytes.len - position.byte) return error.InvalidSourcePosition;
    _ = std.unicode.utf8Decode(bytes[position.byte..][0..length]) catch return error.InvalidSourcePosition;
    result.byte += length;
    if (byte == '\r') {
        if (result.byte < bytes.len and bytes[result.byte] == '\n') result.byte += 1;
        result.line += 1;
        result.column = 1;
    } else if (byte == '\n') {
        result.line += 1;
        result.column = 1;
    } else result.column += 1;
    return result;
}
