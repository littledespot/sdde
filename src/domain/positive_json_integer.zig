//! The one rule for an engine limit read from JSON: a positive value in the u32
//! range, written as an integer. No limit is zero, every value fits the u32
//! fields that carry it, and no quoted, fractional or exponent form names one,
//! whichever JSON decoder runs.
const std = @import("std");

pub fn positiveU32(value: i64) ?u32 {
    const narrowed = std.math.cast(u32, value) orelse return null;
    return if (narrowed == 0) null else narrowed;
}

pub fn jsonPositiveU32(a: std.mem.Allocator, source: *std.json.Scanner, options: std.json.ParseOptions) std.json.ParseError(std.json.Scanner)!u32 {
    const token = try source.nextAllocMax(a, .alloc_if_needed, options.max_value_len orelse std.json.default_max_value_len);
    const written = switch (token) {
        .number => |bytes| bytes,
        .allocated_number => |bytes| bytes,
        else => return error.UnexpectedToken,
    };
    if (!std.json.isNumberFormattedLikeAnInteger(written)) return error.InvalidNumber;
    return positiveU32(try std.fmt.parseInt(i64, written, 10)) orelse error.InvalidNumber;
}

test "a limit is a positive integer-written number within the u32 range" {
    const Limit = struct {
        value: u32,
        pub fn jsonParse(a: std.mem.Allocator, source: *std.json.Scanner, options: std.json.ParseOptions) std.json.ParseError(std.json.Scanner)!@This() {
            return .{ .value = try jsonPositiveU32(a, source, options) };
        }
    };
    for ([_]struct { bytes: []const u8, value: u32 }{ .{ .bytes = "1", .value = 1 }, .{ .bytes = "4294967295", .value = std.math.maxInt(u32) } }) |case| {
        try std.testing.expectEqual(case.value, (try std.json.parseFromSliceLeaky(Limit, std.testing.allocator, case.bytes, .{})).value);
    }
    for ([_][]const u8{ "0", "-1", "4294967296", "1.5", "1e3", "125000.0", "\"1\"", "null", "[]" }) |bytes| {
        try std.testing.expect(std.meta.isError(std.json.parseFromSliceLeaky(Limit, std.testing.allocator, bytes, .{})));
    }
}
