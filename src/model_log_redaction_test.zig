const std = @import("std");
const redaction = @import("domain/model_log_redaction.zig");

test "model log redaction preserves business exact strings and malformed model text" {
    const input = "{not JSON: Hello, World! | 2044-03-12T01:02:03Z \\n\n雪";
    var actual = try redaction.sanitize(std.testing.allocator, input, &.{ "", "a-real-credential" });
    defer actual.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(input, actual.bytes);
    try std.testing.expectEqual(.utf8, actual.encoding);
    try std.testing.expect(!actual.redacted);
}

test "model log redaction removes raw and JSON escaped credentials before chunking" {
    const allocator = std.testing.allocator;
    const secret = "key-\"slash\\newline\n-end";
    const quoted = try std.json.Stringify.valueAlloc(allocator, secret, .{});
    defer allocator.free(quoted);
    const prefix = try allocator.alloc(u8, 4995);
    defer allocator.free(prefix);
    @memset(prefix, 'x');
    const input = try std.fmt.allocPrint(allocator, "{s}{s}|{s}|tail 雪", .{ prefix, secret, quoted[1 .. quoted.len - 1] });
    defer allocator.free(input);
    var actual = try redaction.sanitize(allocator, input, &.{secret});
    defer actual.deinit(allocator);
    const expected = try std.fmt.allocPrint(allocator, "{s}{s}|{s}|tail 雪", .{ prefix, redaction.marker, redaction.marker });
    defer allocator.free(expected);
    try std.testing.expectEqualStrings(expected, actual.bytes);
    try std.testing.expectEqual(.utf8, actual.encoding);
    try std.testing.expect(actual.redacted);
    try std.testing.expect(std.mem.indexOf(u8, actual.bytes, secret) == null);
    try std.testing.expect(std.mem.indexOf(u8, actual.bytes, quoted[1 .. quoted.len - 1]) == null);
}

test "model log redaction prefers a complete credential over its supplied prefix" {
    for ([_][]const []const u8{ &.{ "alpha", "alpha-beta", "omega" }, &.{ "omega", "alpha-beta", "alpha" } }) |secrets| {
        var actual = try redaction.sanitize(std.testing.allocator, "alpha-beta|omega|alpha-beta", secrets);
        defer actual.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings(redaction.marker ++ "|" ++ redaction.marker ++ "|" ++ redaction.marker, actual.bytes);
        try std.testing.expect(actual.redacted);
    }
}

test "model log redaction removes credentials nested in serialized JSON input packets" {
    const allocator = std.testing.allocator;
    const secret = "credential\"with\\escapes";
    const packet = try std.json.Stringify.valueAlloc(allocator, .{ .source = secret, .behavior = "Print \\\"Hello, World!\\\"" }, .{});
    defer allocator.free(packet);
    const wire = try std.json.Stringify.valueAlloc(allocator, .{ .user = packet }, .{});
    defer allocator.free(wire);
    const expected_packet = try std.json.Stringify.valueAlloc(allocator, .{ .source = redaction.marker, .behavior = "Print \\\"Hello, World!\\\"" }, .{});
    defer allocator.free(expected_packet);
    const expected_wire = try std.json.Stringify.valueAlloc(allocator, .{ .user = expected_packet }, .{});
    defer allocator.free(expected_wire);
    var actual = try redaction.sanitize(allocator, wire, &.{secret});
    defer actual.deinit(allocator);
    try std.testing.expect(actual.redacted);
    try std.testing.expectEqual(.utf8, actual.encoding);
    try std.testing.expectEqualStrings(expected_wire, actual.bytes);
}

test "model log redaction preserves malformed business text around deeply escaped credentials" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const secret = "private\"key\\value";
    const business = "malformed JSON: \\\"Hello, World!\\\" 雪";
    var spelling: []const u8 = secret;
    for (0..14) |_| {
        const input = try std.mem.concat(a, u8, &.{ business, "|", spelling, "|complete tail" });
        var actual = try redaction.sanitize(std.testing.allocator, input, &.{secret});
        defer actual.deinit(std.testing.allocator);
        const expected = business ++ "|" ++ redaction.marker ++ "|complete tail";
        try std.testing.expectEqualStrings(expected, actual.bytes);
        try std.testing.expect(actual.redacted);
        const quoted = try std.json.Stringify.valueAlloc(a, spelling, .{});
        spelling = quoted[1 .. quoted.len - 1];
    }
    try std.testing.expect(spelling.len > 5000);
}

test "model log redaction base64 preserves invalid UTF8 after removing credentials" {
    const allocator = std.testing.allocator;
    for ([_]bool{ false, true }) |has_secret| {
        const input = if (has_secret) "\xffcredential\xc0tail" else "\xffbusiness\xc0tail";
        var actual = try redaction.sanitize(allocator, input, &.{"credential"});
        defer actual.deinit(allocator);
        try std.testing.expectEqual(.base64, actual.encoding);
        try std.testing.expectEqual(has_secret, actual.redacted);
        try std.testing.expect(std.unicode.utf8ValidateSlice(actual.bytes));
        const decoded = try allocator.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(actual.bytes));
        defer allocator.free(decoded);
        try std.base64.standard.Decoder.decode(decoded, actual.bytes);
        try std.testing.expectEqualStrings(if (has_secret) "\xff" ++ redaction.marker ++ "\xc0tail" else input, decoded);
    }
}

test "model log redaction retains empty responses without fabricating content" {
    var actual = try redaction.sanitize(std.testing.allocator, "", &.{ "", "credential" });
    defer actual.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("", actual.bytes);
    try std.testing.expectEqual(.utf8, actual.encoding);
    try std.testing.expect(!actual.redacted);
}

test "model log redaction releases allocations at every failure point" {
    for ([_][]const u8{ "credential|\"a\\\"b\"|tail", "\xffcredential|\"a\\\"b\"|tail" }) |input| {
        try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{input});
    }
    const nested = try std.json.Stringify.valueAlloc(std.testing.allocator, "a\\\"b", .{});
    defer std.testing.allocator.free(nested);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{nested});
}

fn allocationCase(allocator: std.mem.Allocator, input: []const u8) !void {
    var actual = try redaction.sanitize(allocator, input, &.{ "credential", "a\"b" });
    defer actual.deinit(allocator);
    try std.testing.expect(actual.redacted);
}
