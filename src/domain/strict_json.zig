const std = @import("std");

pub const Error = error{InvalidJsonDocument} || std.mem.Allocator.Error;
pub const Limits = struct { maximum_bytes: ?usize = null, maximum_depth: usize };

/// Closed native data decoding. The caller's arena owns the returned value.
/// Required fields and wire kinds come from T; no coercion or unknown fields.
pub fn decode(comptime T: type, allocator: std.mem.Allocator, bytes: []const u8, limits: Limits) Error!T {
    var parsed = try parse(allocator, bytes, limits, false);
    defer parsed.deinit();
    if (T != std.json.Value) try wireTypes(T, parsed.value);
    return std.json.parseFromSliceLeaky(T, allocator, bytes, .{
        .allocate = .alloc_always,
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = false,
        .max_value_len = bytes.len,
    }) catch |err| return mapError(err);
}

// Zig also accepts quoted numbers, numeric enum tags and byte arrays as
// strings. Closed wire contracts must reject those conversions consistently.
fn wireTypes(comptime T: type, value: std.json.Value) Error!void {
    switch (@typeInfo(T)) {
        .@"struct" => |s| {
            if (value != .object or value.object.count() != s.fields.len) return error.InvalidJsonDocument;
            inline for (s.fields) |field| try wireTypes(field.type, value.object.get(field.name) orelse return error.InvalidJsonDocument);
        },
        .@"union" => |u| {
            if (u.tag_type == null) @compileError("Closed JSON requires tagged unions");
            if (value != .object or value.object.count() != 1) return error.InvalidJsonDocument;
            inline for (u.fields) |field| {
                if (value.object.get(field.name)) |child| return wireTypes(field.type, child);
            }
            return error.InvalidJsonDocument;
        },
        .pointer => |p| {
            if (p.size != .slice) @compileError("Closed JSON accepts only slices");
            if (p.child == u8) {
                if (value != .string) return error.InvalidJsonDocument;
            } else {
                if (value != .array) return error.InvalidJsonDocument;
                for (value.array.items) |item| try wireTypes(p.child, item);
            }
        },
        .optional => |o| if (value != .null) try wireTypes(o.child, value),
        .array => |a| {
            if (value != .array or value.array.items.len != a.len) return error.InvalidJsonDocument;
            for (value.array.items) |item| try wireTypes(a.child, item);
        },
        .void => if (value != .object or value.object.count() != 0) return error.InvalidJsonDocument,
        .@"enum" => {
            if (value != .string or std.meta.stringToEnum(T, value.string) == null) return error.InvalidJsonDocument;
        },
        .int, .float => if (value != .number_string) return error.InvalidJsonDocument,
        .bool => if (value != .bool) return error.InvalidJsonDocument,
        else => @compileError("Unsupported closed JSON wire field"),
    }
}

/// Syntax only. Callers retain their own schema/root-shape and number policy.
/// The result owns all strings, keys and collections; it never borrows bytes.
pub fn parse(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits, parse_numbers: bool) Error!std.json.Parsed(std.json.Value) {
    try validateTransport(allocator, bytes, limits);
    return std.json.parseFromSlice(std.json.Value, allocator, bytes, .{
        .duplicate_field_behavior = .@"error",
        .allocate = .alloc_always,
        .max_value_len = limits.maximum_bytes orelse bytes.len,
        .parse_numbers = parse_numbers,
    }) catch |err| return mapError(err);
}

/// Shared transport guard for dynamic-tree and closed typed JSON decoders.
pub fn validateTransport(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits) Error!void {
    if (bytes.len == 0 or (limits.maximum_bytes != null and bytes.len > limits.maximum_bytes.?) or
        !std.unicode.utf8ValidateSlice(bytes) or std.mem.startsWith(u8, bytes, "\xef\xbb\xbf")) return error.InvalidJsonDocument;
    try validateNesting(allocator, bytes, limits.maximum_depth);
}

fn validateNesting(allocator: std.mem.Allocator, bytes: []const u8, maximum_depth: usize) Error!void {
    var scanner = std.json.Scanner.initCompleteInput(allocator, bytes);
    defer scanner.deinit();
    var depth: usize = 0;
    while (true) {
        const token = scanner.next() catch |err| return mapError(err);
        switch (token) {
            .object_begin, .array_begin => {
                if (depth == maximum_depth) return error.InvalidJsonDocument;
                depth += 1;
            },
            .object_end, .array_end => {
                if (depth == 0) return error.InvalidJsonDocument;
                depth -= 1;
            },
            .end_of_document => {
                if (depth != 0) return error.InvalidJsonDocument;
                return;
            },
            else => {},
        }
    }
}

fn mapError(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidJsonDocument;
}

test "JSON syntax validation preserves explicit resource caps without requiring model-call caps" {
    var parsed = try parse(std.testing.allocator, "{\"a\":true}", .{ .maximum_depth = 2 }, false);
    defer parsed.deinit();
    try std.testing.expect(parsed.value.object.get("a").?.bool);
    try std.testing.expectError(error.InvalidJsonDocument, parse(std.testing.allocator, "{\"a\":true}", .{ .maximum_bytes = 2, .maximum_depth = 2 }, false));
    try std.testing.expectError(error.InvalidJsonDocument, parse(std.testing.allocator, "{\"a\":{}}", .{ .maximum_depth = 1 }, false));
    try std.testing.expectError(error.InvalidJsonDocument, parse(std.testing.allocator, "{\"a\":true,\"a\":false}", .{ .maximum_depth = 2 }, false));
}

test "closed fixed arrays and empty tagged variants reject length wire-kind and unknown-member changes" {
    const Value = struct { counters: [2]u32, unit: union(enum) { feature: void } };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    _ = try decode(Value, a, "{\"counters\":[1,2],\"unit\":{\"feature\":{}}}", .{ .maximum_depth = 8 });
    for ([_][]const u8{
        "{\"counters\":[1],\"unit\":{\"feature\":{}}}",
        "{\"counters\":[1,2,3],\"unit\":{\"feature\":{}}}",
        "{\"counters\":[1,\"2\"],\"unit\":{\"feature\":{}}}",
        "{\"counters\":[1,2],\"unit\":{\"feature\":null}}",
        "{\"counters\":[1,2],\"unit\":{\"feature\":{\"approved\":true}}}",
    }) |bytes| try std.testing.expectError(error.InvalidJsonDocument, decode(Value, a, bytes, .{ .maximum_depth = 8 }));
}
