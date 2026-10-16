//! Experimental whole-value boundary policy, never production admission policy.
//! Reuse the engine's pinned Unicode classifier, but keep connector punctuation
//! and formatting characters inside words. No normalization or case folding.
const unicode = @import("unicode_normalization");
const c = @cImport({
    @cDefine("UTF8PROC_STATIC", "1");
    @cInclude("utf8proc.h");
});

pub fn wholeWordBoundary(scalar: u21) bool {
    if (!unicode.lexicalBoundary(scalar)) return false;
    return switch (c.utf8proc_category(@intCast(scalar))) {
        c.UTF8PROC_CATEGORY_PC, c.UTF8PROC_CATEGORY_CF => false,
        else => true,
    };
}

test "prototype boundaries retain Unicode connectors marks and format characters" {
    const std = @import("std");
    for ([_]u21{ '_', 0x203f, 0x2040, 0xff3f, 0x200d, 0x200b, 0x301, 0x4e2d, 'a', '9' }) |scalar|
        try std.testing.expect(!wholeWordBoundary(scalar));
    for ([_]u21{ ' ', '.', '!', '"', '-', '(', ')', 0x2014, 0x3002, 0xa0 }) |scalar|
        try std.testing.expect(wholeWordBoundary(scalar));
}
