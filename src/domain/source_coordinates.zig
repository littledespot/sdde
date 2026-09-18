const std = @import("std");
pub const Position = struct { byte: usize, line: u32, column: u32 };
pub const Span = struct { start: Position, end: Position };

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
