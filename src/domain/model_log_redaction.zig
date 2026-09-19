//! Exact credential redaction for complete model-exchange bodies. Call before
//! dividing content into log rows so a credential cannot straddle fragments.
const std = @import("std");

pub const marker = "[REDACTED_CREDENTIAL]";
pub const Encoding = enum { utf8, base64 };

pub const Sanitized = struct {
    bytes: []u8,
    encoding: Encoding,
    redacted: bool,

    pub fn deinit(self: *Sanitized, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
        self.* = undefined;
    }
};

/// The caller supplies credential values from its existing authorization owner;
/// this helper neither discovers credentials nor guesses from business content.
/// Empty values have no secret bytes and are ignored. JSON escaping uses the
/// same standard serializer as model transport, without its surrounding quotes.
/// Nested spellings stop when escaping changes nothing or exceeds the body's
/// length, so encoded JSON inside model-visible strings needs no depth limit.
/// The result owns its allocation and preserves every non-secret byte. Invalid
/// UTF-8 is base64 encoded only after redaction, with explicit encoding metadata.
pub fn sanitize(allocator: std.mem.Allocator, bytes: []const u8, known_secrets: []const []const u8) std.mem.Allocator.Error!Sanitized {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    var patterns: std.ArrayList([]const u8) = .empty;
    for (known_secrets) |secret| {
        if (secret.len == 0) continue;
        var spelling = secret;
        while (spelling.len <= bytes.len) {
            try patterns.append(scratch, spelling);
            const quoted = try std.json.Stringify.valueAlloc(scratch, spelling, .{});
            const escaped = quoted[1 .. quoted.len - 1];
            if (std.mem.eql(u8, spelling, escaped)) break;
            spelling = escaped;
        }
    }

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);
    var cursor: usize = 0;
    var retained_start: usize = 0;
    var redacted = false;
    while (cursor < bytes.len) {
        var matched_length: usize = 0;
        for (patterns.items) |pattern| {
            if (pattern.len > matched_length and std.mem.startsWith(u8, bytes[cursor..], pattern)) matched_length = pattern.len;
        }
        if (matched_length == 0) {
            cursor += 1;
            continue;
        }
        try output.appendSlice(allocator, bytes[retained_start..cursor]);
        try output.appendSlice(allocator, marker);
        cursor += matched_length;
        retained_start = cursor;
        redacted = true;
    }
    try output.appendSlice(allocator, bytes[retained_start..]);

    if (std.unicode.utf8ValidateSlice(output.items)) {
        return .{ .bytes = try output.toOwnedSlice(allocator), .encoding = .utf8, .redacted = redacted };
    }
    const groups = (std.math.add(usize, output.items.len, 2) catch return error.OutOfMemory) / 3;
    const encoded_size = std.math.mul(usize, groups, 4) catch return error.OutOfMemory;
    const encoded = try allocator.alloc(u8, encoded_size);
    _ = std.base64.standard.Encoder.encode(encoded, output.items);
    return .{ .bytes = encoded, .encoding = .base64, .redacted = redacted };
}
