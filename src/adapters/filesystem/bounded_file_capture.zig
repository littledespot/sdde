const std = @import("std");

pub const Error = error{InvalidFileCapture};

pub fn capture(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    observed_size: u64,
    max_bytes: usize,
) Error![]u8 {
    if (max_bytes == 0 or max_bytes == std.math.maxInt(usize) or
        observed_size > max_bytes)
    {
        return error.InvalidFileCapture;
    }

    const bytes = reader.allocRemaining(
        allocator,
        .limited(max_bytes + 1),
    ) catch return error.InvalidFileCapture;
    errdefer allocator.free(bytes);

    const expected_size: usize = @intCast(observed_size);
    if (bytes.len != expected_size) return error.InvalidFileCapture;
    return bytes;
}

test "accepts an exact bounded capture and rejects size drift" {
    const allocator = std.testing.allocator;
    var exact_reader: std.Io.Reader = .fixed("abc");
    const bytes = try capture(allocator, &exact_reader, 3, 3);
    defer allocator.free(bytes);
    try std.testing.expectEqualStrings("abc", bytes);

    var shrunk_reader: std.Io.Reader = .fixed("ab");
    try std.testing.expectError(
        error.InvalidFileCapture,
        capture(allocator, &shrunk_reader, 3, 4),
    );

    var grown_reader: std.Io.Reader = .fixed("abc");
    try std.testing.expectError(
        error.InvalidFileCapture,
        capture(allocator, &grown_reader, 2, 4),
    );
}
