//! Canonical identity syntax for explicit human development-review declarations.
const std = @import("std");
const c = @import("contracts.zig");

pub fn validReviewer(value: []const u8) bool {
    return c.text(value) and value.len <= 128;
}

pub fn validUtcTimestamp(value: []const u8) bool {
    if (value.len != 20 or value[4] != '-' or value[7] != '-' or value[10] != 'T' or value[13] != ':' or value[16] != ':' or value[19] != 'Z') return false;
    for (value, 0..) |byte, index| switch (index) {
        4, 7, 10, 13, 16, 19 => {},
        else => if (!std.ascii.isDigit(byte)) return false,
    };
    const year = std.fmt.parseInt(u16, value[0..4], 10) catch return false;
    const month = std.fmt.parseInt(u8, value[5..7], 10) catch return false;
    const day = std.fmt.parseInt(u8, value[8..10], 10) catch return false;
    const hour = std.fmt.parseInt(u8, value[11..13], 10) catch return false;
    const minute = std.fmt.parseInt(u8, value[14..16], 10) catch return false;
    const second = std.fmt.parseInt(u8, value[17..19], 10) catch return false;
    if (year == 0 or month == 0 or month > 12 or day == 0 or hour > 23 or minute > 59 or second > 59) return false;
    const leap: u8 = if (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)) 1 else 0;
    const month_days = [_]u8{ 31, 28 + leap, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    return day <= month_days[month - 1];
}
