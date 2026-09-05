//! Pinned NFC implementation; all allocations remain caller-owned and bounded.
const std = @import("std");
const c = @cImport({
    @cDefine("UTF8PROC_STATIC", "1");
    @cInclude("utf8proc.h");
});

pub const Error = std.mem.Allocator.Error || error{ InvalidUtf8, NormalizationLimitExceeded, NormalizationFailed };

pub fn normalize(allocator: std.mem.Allocator, input: []const u8, maximum_bytes: usize) Error![]u8 {
    if (input.len > maximum_bytes or maximum_bytes > std.math.maxInt(isize) / 4) return error.NormalizationLimitExceeded;
    const options = c.UTF8PROC_STABLE | c.UTF8PROC_COMPOSE;
    const required = c.utf8proc_decompose(input.ptr, @intCast(input.len), null, 0, options);
    if (required == c.UTF8PROC_ERROR_INVALIDUTF8) return error.InvalidUtf8;
    if (required < 0) return error.NormalizationFailed;
    // Four codepoints per input byte is a conservative bound for the pinned
    // canonical decomposition table, checked before allocating any workspace.
    const count: usize = @intCast(required);
    if (count > maximum_bytes * 4) return error.NormalizationLimitExceeded;
    const buffer = try allocator.alloc(i32, count + 1); // reencode writes a terminator
    defer allocator.free(buffer);
    if (c.utf8proc_decompose(input.ptr, @intCast(input.len), buffer.ptr, @intCast(count), options) != required) return error.NormalizationFailed;
    const encoded = c.utf8proc_reencode(buffer.ptr, required, options);
    if (encoded < 0) return error.NormalizationFailed;
    const length: usize = @intCast(encoded);
    if (length > maximum_bytes) return error.NormalizationLimitExceeded;
    return allocator.dupe(u8, std.mem.sliceAsBytes(buffer)[0..length]);
}

test "NFC composes Latin and Hangul without compatibility folding or case changes" {
    const cases = .{
        .{ "Cafe\u{301}", "Café" },
        .{ "\u{1100}\u{1161}", "가" },
        .{ "\u{212b}", "Å" },
        .{ "①Ａ", "①Ａ" },
        .{ "a\x00b", "a\x00b" },
    };
    inline for (cases) |case| {
        const result = try normalize(std.testing.allocator, case[0], 128);
        defer std.testing.allocator.free(result);
        try std.testing.expectEqualStrings(case[1], result);
    }
    try std.testing.expectError(error.InvalidUtf8, normalize(std.testing.allocator, "\xc0\xaf", 128));
    try std.testing.expectError(error.NormalizationLimitExceeded, normalize(std.testing.allocator, "abc", 2));
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    const result = try normalize(allocator, "Cafe\u{301}", 128);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Café", result);
}

test "NFC releases every allocation on failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
