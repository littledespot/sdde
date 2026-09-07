//! Canonical JSON projection of native typed state: sorted keys, preserved
//! array order, integer-only numbers, and one final LF. No input normalization.
const std = @import("std");
pub const Error = std.mem.Allocator.Error || error{InvalidCanonicalJson};
pub fn encode(comptime T: type, allocator: std.mem.Allocator, value: T) Error![]const u8 {
    const bytes = try std.json.Stringify.valueAlloc(allocator, value, .{});
    defer allocator.free(bytes);
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{ .parse_numbers = false, .max_value_len = bytes.len }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidCanonicalJson;
    defer parsed.deinit();
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try write(allocator, &out.writer, parsed.value);
    out.writer.writeByte('\n') catch return error.OutOfMemory;
    return out.toOwnedSlice();
}
fn write(allocator: std.mem.Allocator, writer: *std.Io.Writer, value: std.json.Value) Error!void {
    switch (value) {
        .object => |object| {
            const keys = try allocator.dupe([]const u8, object.keys());
            defer allocator.free(keys);
            std.mem.sort([]const u8, keys, {}, less);
            writer.writeByte('{') catch return error.OutOfMemory;
            for (keys, 0..) |key, index| {
                if (index != 0) writer.writeByte(',') catch return error.OutOfMemory;
                std.json.Stringify.value(key, .{}, writer) catch return error.OutOfMemory;
                writer.writeByte(':') catch return error.OutOfMemory;
                try write(allocator, writer, object.get(key).?);
            }
            writer.writeByte('}') catch return error.OutOfMemory;
        },
        .array => |array| {
            writer.writeByte('[') catch return error.OutOfMemory;
            for (array.items, 0..) |item, index| {
                if (index != 0) writer.writeByte(',') catch return error.OutOfMemory;
                try write(allocator, writer, item);
            }
            writer.writeByte(']') catch return error.OutOfMemory;
        },
        .number_string => |number| {
            const digits = if (std.mem.startsWith(u8, number, "-")) number[1..] else number;
            if (digits.len == 0 or (digits.len > 1 and digits[0] == '0')) return error.InvalidCanonicalJson;
            for (digits) |digit| if (!std.ascii.isDigit(digit)) return error.InvalidCanonicalJson;
            writer.writeAll(number) catch return error.OutOfMemory;
        },
        .string, .bool, .null => std.json.Stringify.value(value, .{}, writer) catch return error.OutOfMemory,
        .integer, .float => return error.InvalidCanonicalJson,
    }
}
fn less(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

test "canonical state JSON sorts nested keys preserves raw Unicode and forbids fractional numbers" {
    const State = struct { z: []const u8, a: struct { y: u64, b: []const bool } };
    const bytes = try encode(State, std.testing.allocator, .{ .z = "Cafe\u{301}", .a = .{ .y = 17, .b = &.{ true, false } } });
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("{\"a\":{\"b\":[true,false],\"y\":17},\"z\":\"Cafe\u{301}\"}\n", bytes);
    try std.testing.expectError(error.InvalidCanonicalJson, encode(f64, std.testing.allocator, 1.25));
}
