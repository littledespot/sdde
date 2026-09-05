const std = @import("std");

pub const Error = error{InvalidJsonDocument} || std.mem.Allocator.Error;
pub const Limits = struct { maximum_bytes: usize, maximum_depth: usize };

/// Syntax only. Callers retain their own schema/root-shape and number policy.
/// The result owns all strings, keys and collections; it never borrows bytes.
pub fn parse(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits, parse_numbers: bool) Error!std.json.Parsed(std.json.Value) {
    try validateTransport(allocator, bytes, limits);
    return std.json.parseFromSlice(std.json.Value, allocator, bytes, .{
        .duplicate_field_behavior = .@"error",
        .allocate = .alloc_always,
        .max_value_len = limits.maximum_bytes,
        .parse_numbers = parse_numbers,
    }) catch |err| return mapError(err);
}

/// Shared transport guard for dynamic-tree and closed typed JSON decoders.
pub fn validateTransport(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits) Error!void {
    if (bytes.len == 0 or bytes.len > limits.maximum_bytes or
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
