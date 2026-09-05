//! Pinned Unicode transforms; all allocations remain caller-owned and bounded.
const std = @import("std");
const c = @cImport({
    @cDefine("UTF8PROC_STATIC", "1");
    @cInclude("utf8proc.h");
});

pub const Error = std.mem.Allocator.Error || error{ InvalidUtf8, NormalizationLimitExceeded, NormalizationFailed };

pub fn nfc(allocator: std.mem.Allocator, input: []const u8, maximum_bytes: usize) Error![]u8 {
    return transform(allocator, input, maximum_bytes, c.UTF8PROC_STABLE | c.UTF8PROC_COMPOSE);
}

pub fn fold(allocator: std.mem.Allocator, input: []const u8, maximum_bytes: usize) Error![]u8 {
    return transform(allocator, input, maximum_bytes, c.UTF8PROC_STABLE | c.UTF8PROC_DECOMPOSE | c.UTF8PROC_COMPAT | c.UTF8PROC_CASEFOLD | c.UTF8PROC_STRIPMARK);
}

fn transform(allocator: std.mem.Allocator, input: []const u8, maximum_bytes: usize, options: c.utf8proc_option_t) Error![]u8 {
    if (input.len > maximum_bytes or maximum_bytes > std.math.maxInt(isize) / 4) return error.NormalizationLimitExceeded;
    const required = c.utf8proc_decompose(input.ptr, @intCast(input.len), null, 0, options);
    if (required == c.UTF8PROC_ERROR_INVALIDUTF8) return error.InvalidUtf8;
    if (required < 0) return error.NormalizationFailed;
    // Bound workspace independently of Unicode expansion before allocation.
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
        const result = try nfc(std.testing.allocator, case[0], 128);
        defer std.testing.allocator.free(result);
        try std.testing.expectEqualStrings(case[1], result);
    }
    try std.testing.expectError(error.InvalidUtf8, nfc(std.testing.allocator, "\xc0\xaf", 128));
    try std.testing.expectError(error.NormalizationLimitExceeded, nfc(std.testing.allocator, "abc", 2));
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    const result = try nfc(allocator, "Cafe\u{301}", 128);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Café", result);
}

test "NFC releases every allocation on failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}

test "folding is pinned and explicit without linguistic transliteration" {
    try std.testing.expectEqualStrings("2.11.3", std.mem.span(c.utf8proc_version()));
    try std.testing.expectEqualStrings("17.0.0", std.mem.span(c.utf8proc_unicode_version()));
    const cases = .{
        .{ "Cafe\u{301}/Straße/①Ａ/ﬃ", "cafe/strasse/1a/ffi" },
        .{ "日本語", "日本語" },
        .{ "a\x00b", "a\x00b" },
    };
    inline for (cases) |case| {
        const result = try fold(std.testing.allocator, case[0], 128);
        defer std.testing.allocator.free(result);
        try std.testing.expectEqualStrings(case[1], result);
    }
    try std.testing.expectError(error.InvalidUtf8, fold(std.testing.allocator, "\xff", 128));
    try std.testing.expectError(error.NormalizationLimitExceeded, fold(std.testing.allocator, "abc", 2));
    // Compatibility expansion is bounded after folding, not silently truncated.
    try std.testing.expectError(error.NormalizationLimitExceeded, fold(std.testing.allocator, "\u{fdfa}", 3));
}
