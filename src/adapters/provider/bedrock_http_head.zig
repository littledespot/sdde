const std = @import("std");

// Stream into caller-owned storage rather than making the client's read-buffer
// size a response-header ceiling. Framing and parsing remain Zig HTTP's rules.
pub fn receive(allocator: std.mem.Allocator, input: *std.Io.Reader) ![]const u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    var parser: std.http.HeadParser = .{};
    while (parser.state != .finished) {
        _ = try input.peek(1);
        const bytes = input.buffered();
        const used = parser.feed(bytes);
        output.writer.writeAll(bytes[0..used]) catch return error.OutOfMemory;
        input.toss(used);
    }
    return output.toOwnedSlice();
}
