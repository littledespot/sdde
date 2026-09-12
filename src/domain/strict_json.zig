const std = @import("std");

pub const Error = error{InvalidJsonDocument} || std.mem.Allocator.Error;
pub const Limits = struct { maximum_bytes: ?usize = null, maximum_depth: usize };

/// Parser diagnostics own context strings; callers release or copy them explicitly.
pub const Diagnostic = struct {
    reason: Reason,
    location: ?Location = null,
    context: ?@import("json_context.zig").Context = null,

    pub fn deinit(self: Diagnostic, allocator: std.mem.Allocator) void {
        if (self.context) |context| context.deinit(allocator);
    }

    pub fn copy(self: Diagnostic, allocator: std.mem.Allocator) std.mem.Allocator.Error!Diagnostic {
        var result = self;
        if (self.context) |context| result.context = try context.copy(allocator);
        return result;
    }

    pub const Location = @import("json_context.zig").Location;
    pub const Reason = enum {
        EmptyDocument,
        ByteLimitExceeded,
        InvalidUtf8,
        ByteOrderMark,
        NestingLimitExceeded,
        ExpectedObject,
        SyntaxError,
        UnexpectedEndOfInput,
        DuplicateField,
        UnexpectedToken,
        InvalidNumber,
        Overflow,
        InvalidCharacter,
        InvalidEnumTag,
        UnknownField,
        MissingField,
        LengthMismatch,
        BufferUnderrun,
        ValueTooLong,
    };
};

/// Closed native data decoding. The caller's arena owns the returned value.
/// Required fields and wire kinds come from T; no coercion or unknown fields.
pub fn decode(comptime T: type, allocator: std.mem.Allocator, bytes: []const u8, limits: Limits) Error!T {
    var parsed = try parse(allocator, bytes, limits, false, null);
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
/// On rejection, a requested diagnostic also owns its context. Release it before
/// reusing the output slot; allocation failure leaves that slot empty.
pub fn parse(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits, parse_numbers: bool, diagnostic: ?*?Diagnostic) Error!std.json.Parsed(std.json.Value) {
    if (diagnostic) |out| out.* = null;
    return parseDocument(allocator, bytes, limits, parse_numbers, diagnostic) catch |err| {
        if (diagnostic) |out| if (out.*) |*failure| {
            if (failure.location) |position| {
                failure.context = @import("json_context.zig").describe(allocator, bytes, position.byte_offset, failure.reason == .DuplicateField) catch |context_error| {
                    out.* = null;
                    return context_error;
                };
            }
        };
        return err;
    };
}

fn parseDocument(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits, parse_numbers: bool, diagnostic: ?*?Diagnostic) Error!std.json.Parsed(std.json.Value) {
    try validateTransport(allocator, bytes, limits, diagnostic);
    var scanner = std.json.Scanner.initCompleteInput(allocator, bytes);
    defer scanner.deinit();
    var position: std.json.Diagnostics = .{};
    scanner.enableDiagnostics(&position);
    return std.json.parseFromTokenSource(std.json.Value, allocator, &scanner, .{
        .duplicate_field_behavior = .@"error",
        .allocate = .alloc_always,
        .max_value_len = limits.maximum_bytes orelse bytes.len,
        .parse_numbers = parse_numbers,
    }) catch |err| return parserFailure(err, &position, diagnostic);
}

/// Shared transport guard for dynamic-tree and closed typed JSON decoders.
fn validateTransport(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits, diagnostic: ?*?Diagnostic) Error!void {
    if (bytes.len == 0) return reject(diagnostic, .{ .reason = .EmptyDocument, .location = .{ .byte_offset = 0, .line = 1, .column = 1 } });
    if (limits.maximum_bytes != null and bytes.len > limits.maximum_bytes.?) return reject(diagnostic, .{ .reason = .ByteLimitExceeded });
    if (!std.unicode.utf8ValidateSlice(bytes)) return reject(diagnostic, .{ .reason = .InvalidUtf8 });
    if (std.mem.startsWith(u8, bytes, "\xef\xbb\xbf")) return reject(diagnostic, .{ .reason = .ByteOrderMark, .location = .{ .byte_offset = 0, .line = 1, .column = 1 } });
    try validateNesting(allocator, bytes, limits.maximum_depth, diagnostic);
}

fn validateNesting(allocator: std.mem.Allocator, bytes: []const u8, maximum_depth: usize, diagnostic: ?*?Diagnostic) Error!void {
    var scanner = std.json.Scanner.initCompleteInput(allocator, bytes);
    defer scanner.deinit();
    var position: std.json.Diagnostics = .{};
    scanner.enableDiagnostics(&position);
    var depth: usize = 0;
    while (true) {
        const token = scanner.next() catch |err| return parserFailure(err, &position, diagnostic);
        switch (token) {
            .object_begin, .array_begin => {
                if (depth == maximum_depth) return reject(diagnostic, .{ .reason = .NestingLimitExceeded, .location = location(&position) });
                depth += 1;
            },
            .object_end, .array_end => {
                if (depth == 0) return reject(diagnostic, .{ .reason = .SyntaxError, .location = location(&position) });
                depth -= 1;
            },
            .end_of_document => {
                if (depth != 0) return reject(diagnostic, .{ .reason = .UnexpectedEndOfInput, .location = location(&position) });
                return;
            },
            else => {},
        }
    }
}

fn location(position: *const std.json.Diagnostics) Diagnostic.Location {
    return .{ .byte_offset = position.getByteOffset(), .line = position.getLine(), .column = position.getColumn() };
}

fn reject(out: ?*?Diagnostic, diagnostic: Diagnostic) Error {
    if (out) |value| value.* = diagnostic;
    return error.InvalidJsonDocument;
}

fn parserFailure(err: std.json.ParseError(std.json.Scanner), position: *const std.json.Diagnostics, out: ?*?Diagnostic) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        inline else => |failure| reject(out, .{ .reason = @field(Diagnostic.Reason, @errorName(failure)), .location = location(position) }),
    };
}

fn mapError(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidJsonDocument;
}

test "JSON syntax validation preserves explicit resource caps without requiring model-call caps" {
    var parsed = try parse(std.testing.allocator, "{\"a\":true}", .{ .maximum_depth = 2 }, false, null);
    defer parsed.deinit();
    try std.testing.expect(parsed.value.object.get("a").?.bool);
    try std.testing.expectError(error.InvalidJsonDocument, parse(std.testing.allocator, "{\"a\":true}", .{ .maximum_bytes = 2, .maximum_depth = 2 }, false, null));
    try std.testing.expectError(error.InvalidJsonDocument, parse(std.testing.allocator, "{\"a\":{}}", .{ .maximum_depth = 1 }, false, null));
    try std.testing.expectError(error.InvalidJsonDocument, parse(std.testing.allocator, "{\"a\":true,\"a\":false}", .{ .maximum_depth = 2 }, false, null));
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

test "strict JSON retains native reasons and byte locations with owned context" {
    const Case = struct { bytes: []const u8, reason: Diagnostic.Reason, location: ?Diagnostic.Location = null };
    for ([_]Case{
        .{ .bytes = "```json\n{}\n```", .reason = .SyntaxError, .location = .{ .byte_offset = 0, .line = 1, .column = 1 } },
        .{ .bytes = "{\n  \"a\": }\n", .reason = .SyntaxError, .location = .{ .byte_offset = 9, .line = 2, .column = 8 } },
        .{ .bytes = "{\"a\":", .reason = .UnexpectedEndOfInput, .location = .{ .byte_offset = 5, .line = 1, .column = 6 } },
        .{ .bytes = "{\"x\":1,\"\\u0078\":2}", .reason = .DuplicateField },
        .{ .bytes = "{\"nested\":[[]]}", .reason = .NestingLimitExceeded },
        .{ .bytes = "\xff", .reason = .InvalidUtf8 },
        .{ .bytes = "", .reason = .EmptyDocument },
        .{ .bytes = "\xef\xbb\xbf{}", .reason = .ByteOrderMark },
    }) |case| {
        var diagnostic: ?Diagnostic = null;
        try std.testing.expectError(error.InvalidJsonDocument, parse(std.testing.allocator, case.bytes, .{ .maximum_depth = 2 }, false, &diagnostic));
        try std.testing.expectEqual(case.reason, diagnostic.?.reason);
        if (case.location) |expected| try std.testing.expectEqualDeep(expected, diagnostic.?.location.?);
        diagnostic.?.deinit(std.testing.allocator);
        diagnostic = null;
        var accepted = try parse(std.testing.allocator, "{\"valid\":true}", .{ .maximum_depth = 2 }, false, &diagnostic);
        defer accepted.deinit();
        try std.testing.expect(diagnostic == null);
    }
}

test "duplicate diagnostics identify object scope decoded key and both occurrences" {
    for ([_]struct { bytes: []const u8, path: []const u8, key: []const u8 }{
        .{ .bytes = "{\"statements\":[{\"local_key\":\"a\",\"content\":{},\"local_key\":\"b\"}]}", .path = "/statements/0", .key = "local_key" },
        .{ .bytes = "{\"a~/b\":[{}, {\"x\":1,\"\\u0078\":2}]}", .path = "/a~0~1b/1", .key = "x" },
        .{ .bytes = "{\n \"outer\":{\"flag\":true,\"child\":{\"flag\":false},\"flag\":false}}", .path = "/outer", .key = "flag" },
    }) |case| {
        var diagnostic: ?Diagnostic = null;
        defer if (diagnostic) |value| value.deinit(std.testing.allocator);
        try std.testing.expectError(error.InvalidJsonDocument, parse(std.testing.allocator, case.bytes, .{ .maximum_depth = 8 }, false, &diagnostic));
        const context = diagnostic.?.context.?;
        try std.testing.expectEqual(.DuplicateField, diagnostic.?.reason);
        try std.testing.expectEqualStrings(case.path, context.path);
        try std.testing.expectEqualStrings(case.key, context.key.?);
        try std.testing.expect(context.first_occurrence.?.byte_offset < context.repeated_occurrence.?.byte_offset);
        try std.testing.expectEqual(@as(u8, '"'), case.bytes[@intCast(context.first_occurrence.?.byte_offset)]);
        try std.testing.expectEqual(@as(u8, '"'), case.bytes[@intCast(context.repeated_occurrence.?.byte_offset)]);
    }
    try std.testing.checkAllAllocationFailures(std.testing.allocator, diagnosticAllocation, .{});
}

fn diagnosticAllocation(allocator: std.mem.Allocator) !void {
    var diagnostic: ?Diagnostic = null;
    defer if (diagnostic) |value| value.deinit(allocator);
    const parsed = parse(allocator, "{\"items\":[{\"name\":1,\"name\":2}]}", .{ .maximum_depth = 8 }, false, &diagnostic) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidJsonDocument => {
            const copied = try diagnostic.?.copy(allocator);
            defer copied.deinit(allocator);
            try std.testing.expectEqualStrings("/items/0", copied.context.?.path);
            return;
        },
    };
    parsed.deinit();
    return error.TestUnexpectedResult;
}

test "syntax diagnostics retain active field and container without inventing a correction" {
    var diagnostic: ?Diagnostic = null;
    defer if (diagnostic) |value| value.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidJsonDocument, parse(std.testing.allocator, "{\"items\":[{\"enabled\": }]}", .{ .maximum_depth = 8 }, false, &diagnostic));
    try std.testing.expectEqualStrings("/items/0", diagnostic.?.context.?.path);
    try std.testing.expectEqualStrings("enabled", diagnostic.?.context.?.key.?);
    try std.testing.expect(diagnostic.?.context.?.first_occurrence == null);
}
