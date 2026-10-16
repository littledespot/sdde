//! Independently fixed outcomes for the canonical delimiter policy. Historical
//! whole-word recognizer controls remain separate diagnostic evidence.
const std = @import("std");
const boundary = @import("../../../src/domain/exact_value_boundary.zig");
const unicode = @import("exact_value_unicode");
const full_field_edges: boundary.Edges = .{ .left = .field_edge, .right = .field_edge };

test "closed Unicode whitespace syntax equals the pinned property for every scalar" {
    var whitespace_count: usize = 0;
    for (0..0x110000) |value| {
        if (value >= 0xd800 and value <= 0xdfff) continue;
        const scalar: u21 = @intCast(value);
        const expected = unicode.whiteSpaceProperty(scalar);
        try std.testing.expectEqual(expected, boundary.isWhitespace(scalar));
        if (expected) whitespace_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 25), whitespace_count);
}
const Expected = std.meta.Tag(boundary.Evidence);
const Control = struct { id: []const u8, prefix: []const u8 = "", value: []const u8, suffix: []const u8 = "", expected: Expected };

// Expectations are specified here, separately from the implementation. Values
// span unrelated domains; no control's value kind is supplied to the evaluator.
const controls = [_]Control{
    .{ .id = "whole-field", .value = "ACTIVE", .expected = .accepted },
    .{ .id = "whitespace", .prefix = "Display ", .value = "ACTIVE", .suffix = " now", .expected = .accepted },
    .{ .id = "terminal-period", .prefix = "Use ", .value = "1.2", .suffix = ".", .expected = .accepted },
    .{ .id = "terminal-list", .value = "READY", .suffix = ", then continue.", .expected = .accepted },
    .{ .id = "terminal-run", .value = "READY", .suffix = "!? ", .expected = .accepted },
    .{ .id = "greeting-with-exact-punctuation", .prefix = "Display ", .value = "Hello, World!", .suffix = ".", .expected = .accepted },
    .{ .id = "path-complete", .prefix = "Call ", .value = "/v1/renewals", .suffix = ".", .expected = .accepted },
    .{ .id = "whole-extended-version", .prefix = "Use ", .value = "1.2.3", .suffix = ".", .expected = .accepted },
    .{ .id = "whole-extended-path", .prefix = "Call ", .value = "/v1/renewals/archive", .suffix = ".", .expected = .accepted },
    .{ .id = "currency-whole-value", .prefix = "Charge ", .value = "$10.50", .suffix = ".", .expected = .accepted },
    .{ .id = "exact-multiline", .prefix = "Say [", .value = "A\tB\r\nC", .suffix = "] exactly.", .expected = .accepted },
    .{ .id = "ascii-double-quotes", .prefix = "Display \"", .value = "ACTIVE", .suffix = "\".", .expected = .accepted },
    .{ .id = "ascii-single-quotes", .prefix = "Display '", .value = "ACTIVE", .suffix = "'.", .expected = .accepted },
    .{ .id = "backtick-pair", .prefix = "Display `", .value = "ACTIVE", .suffix = "`.", .expected = .accepted },
    .{ .id = "parentheses", .prefix = "Display (", .value = "ACTIVE", .suffix = ").", .expected = .accepted },
    .{ .id = "square-brackets", .prefix = "Display [", .value = "ACTIVE", .suffix = "].", .expected = .accepted },
    .{ .id = "braces", .prefix = "Display {", .value = "ACTIVE", .suffix = "}.", .expected = .accepted },
    .{ .id = "nested-wrappers", .prefix = "Display ([\"", .value = "ACTIVE", .suffix = "\"]).", .expected = .accepted },
    .{ .id = "punctuation-inside-quotes", .prefix = "Display \"", .value = "ACTIVE", .suffix = ".\"", .expected = .accepted },
    .{ .id = "punctuation-among-wrappers", .prefix = "Display (\"", .value = "ACTIVE", .suffix = ".\").", .expected = .accepted },
    .{ .id = "unicode-curly-quotes", .prefix = "Display “", .value = "ACTIVE", .suffix = "”.", .expected = .accepted },
    .{ .id = "unicode-single-quotes", .prefix = "Display ‘", .value = "ACTIVE", .suffix = "’.", .expected = .accepted },
    .{ .id = "unicode-guillemets", .prefix = "Display «", .value = "ACTIVE", .suffix = "».", .expected = .accepted },
    .{ .id = "unicode-single-guillemets", .prefix = "Display ‹", .value = "ACTIVE", .suffix = "›.", .expected = .accepted },
    .{ .id = "unicode-cjk-wrappers", .prefix = "Display 「", .value = "ACTIVE", .suffix = "」。", .expected = .accepted },
    .{ .id = "unicode-fullwidth-wrappers", .prefix = "Display （", .value = "ACTIVE", .suffix = "）。", .expected = .accepted },
    .{ .id = "unicode-cjk-terminal", .value = "ACTIVE", .suffix = "。", .expected = .accepted },
    .{ .id = "unicode-ellipsis", .value = "ACTIVE", .suffix = "… ", .expected = .accepted },
    .{ .id = "unicode-no-break-space", .prefix = "\u{a0}", .value = "ACTIVE", .suffix = "\u{a0}", .expected = .accepted },
    .{ .id = "unicode-ideographic-space", .prefix = "\u{3000}", .value = "ACTIVE", .suffix = "\u{3000}", .expected = .accepted },
    .{ .id = "unicode-line-separator", .prefix = "\u{2028}", .value = "ACTIVE", .suffix = "\u{2029}", .expected = .accepted },
    .{ .id = "version-extension", .prefix = "Use ", .value = "1.2", .suffix = ".3.", .expected = .rejected },
    .{ .id = "path-extension", .prefix = "Call ", .value = "/v1/renewals", .suffix = "/archive.", .expected = .rejected },
    .{ .id = "file-extension", .prefix = "Read ", .value = "report", .suffix = ".txt.", .expected = .rejected },
    .{ .id = "status-hyphen-extension", .value = "ACTIVE", .suffix = "-PENDING", .expected = .rejected },
    .{ .id = "status-underscore-extension", .value = "ACTIVE", .suffix = "_PENDING", .expected = .rejected },
    .{ .id = "email-extension", .value = "ACTIVE", .suffix = "@example.invalid", .expected = .rejected },
    .{ .id = "attached-percent", .value = "10", .suffix = "%", .expected = .rejected },
    .{ .id = "attached-plus", .value = "10", .suffix = "+", .expected = .rejected },
    .{ .id = "terminal-followed-by-text", .value = "ACTIVE", .suffix = "!suffix", .expected = .rejected },
    .{ .id = "terminal-followed-by-path", .value = "ACTIVE", .suffix = "./suffix", .expected = .rejected },
    .{ .id = "left-word-continuation", .prefix = "NOT", .value = "ACTIVE", .expected = .rejected },
    .{ .id = "right-word-continuation", .value = "ACTIVE", .suffix = "NESS", .expected = .rejected },
    .{ .id = "left-punctuation-continuation", .prefix = "prefix/", .value = "ACTIVE", .expected = .rejected },
    .{ .id = "left-list-without-space", .prefix = "READY,", .value = "ACTIVE", .expected = .rejected },
    .{ .id = "left-cjk-continuation", .prefix = "中", .value = "ACTIVE", .expected = .rejected },
    .{ .id = "right-cjk-continuation", .value = "ACTIVE", .suffix = "中", .expected = .rejected },
    .{ .id = "left-mark-continuation", .prefix = "\u{301}", .value = "ACTIVE", .expected = .rejected },
    .{ .id = "right-mark-continuation", .value = "ACTIVE", .suffix = "\u{301}", .expected = .rejected },
    .{ .id = "zero-width-format-is-not-space", .value = "ACTIVE", .suffix = "\u{200b}", .expected = .rejected },
    .{ .id = "word-joiner-is-not-space", .value = "ACTIVE", .suffix = "\u{2060}", .expected = .rejected },
    .{ .id = "mismatched-wrapper", .prefix = "[", .value = "ACTIVE", .suffix = ")", .expected = .rejected },
    .{ .id = "unclosed-wrapper", .prefix = "[", .value = "ACTIVE", .expected = .rejected },
    .{ .id = "unopened-wrapper", .value = "ACTIVE", .suffix = "]", .expected = .rejected },
    .{ .id = "surplus-closing-wrapper", .prefix = "(", .value = "ACTIVE", .suffix = "))", .expected = .rejected },
    .{ .id = "wrapped-unit-left-continuation", .prefix = "prefix[", .value = "ACTIVE", .suffix = "]", .expected = .rejected },
    .{ .id = "wrapped-unit-right-continuation", .prefix = "[", .value = "ACTIVE", .suffix = "]/suffix", .expected = .rejected },
    .{ .id = "quoted-unit-right-continuation", .prefix = "\"", .value = "ACTIVE", .suffix = "\"suffix", .expected = .rejected },
    .{ .id = "quoted-extended-version", .prefix = "\"", .value = "1.2", .suffix = ".3\"", .expected = .rejected },
    .{ .id = "quote-encloses-longer-phrase", .prefix = "Say \"the ", .value = "ACTIVE", .suffix = "\".", .expected = .rejected },
};

pub const Summary = struct { policy: []const u8 = boundary.policy_name, controls: usize = 0, accepted: usize = 0, rejected: usize = 0 };

/// Execute immutable controls without allocation, file access or test-only
/// assertions, so diagnostic reporting can retain the actual observed result.
pub fn runControls() error{BoundaryControlMismatch}!Summary {
    var summary: Summary = .{};
    inline for (controls) |control| {
        const prose = control.prefix ++ control.value ++ control.suffix;
        const result = boundary.evaluate(prose, control.prefix.len, control.prefix.len + control.value.len, full_field_edges);
        if (std.meta.activeTag(result) != control.expected) return error.BoundaryControlMismatch;
        summary.controls += 1;
        switch (result) {
            .accepted => summary.accepted += 1,
            .rejected => summary.rejected += 1,
        }
    }
    return summary;
}

test "contextual boundary experiment satisfies independently specified cross-domain controls" {
    const summary = try runControls();
    try std.testing.expectEqual(@as(usize, controls.len), summary.controls);
    try std.testing.expectEqual(@as(usize, 31), summary.accepted);
    try std.testing.expectEqual(@as(usize, 29), summary.rejected);
}

test "contextual evidence retains exact scalar offsets wrappers and terminal suffixes" {
    const prose = "Display (\"ACTIVE.\").";
    const result = boundary.evaluate(prose, 10, 16, full_field_edges);
    try std.testing.expectEqualDeep(boundary.Evidence{ .accepted = .{
        .outer_start_byte = 8,
        .outer_end_byte = prose.len,
        .left = .whitespace,
        .right = .field_edge,
        .enclosing_wrappers = 2,
        .terminal_punctuation = 2,
    } }, result);
    try std.testing.expectEqualStrings("ACTIVE", prose[10..16]);
    const multibyte = boundary.evaluate("「中」。", 3, 6, full_field_edges);
    try std.testing.expectEqual(@as(usize, 0), multibyte.accepted.outer_start_byte);
    try std.testing.expectEqual(@as(usize, 12), multibyte.accepted.outer_end_byte);
}

test "contextual experiment rejects invalid spans and UTF8 without operational errors" {
    const cases = [_]struct { prose: []const u8, start: usize, end: usize, rejection: boundary.Rejection }{
        .{ .prose = "ACTIVE\xff", .start = 0, .end = 6, .rejection = .invalid_utf8 },
        .{ .prose = "", .start = 0, .end = 0, .rejection = .invalid_span },
        .{ .prose = "ACTIVE", .start = 1, .end = 1, .rejection = .invalid_span },
        .{ .prose = "ACTIVE", .start = 3, .end = 2, .rejection = .invalid_span },
        .{ .prose = "ACTIVE", .start = 0, .end = 7, .rejection = .invalid_span },
        .{ .prose = "中", .start = 1, .end = 3, .rejection = .invalid_scalar_boundary },
        .{ .prose = "中", .start = 0, .end = 2, .rejection = .invalid_scalar_boundary },
    };
    for (cases) |case| try std.testing.expectEqualDeep(boundary.Evidence{ .rejected = case.rejection }, boundary.evaluate(case.prose, case.start, case.end, full_field_edges));
}

test "canonical boundary evidence distinguishes actual field ends from opaque reference run edges" {
    const reference_edges: boundary.Edges = .{ .left = .reference_boundary, .right = .reference_boundary };
    try std.testing.expectEqualDeep(boundary.Evidence{ .rejected = .left_reference_boundary }, boundary.evaluate("ACTIVE", 0, 6, reference_edges));
    try std.testing.expectEqualDeep(boundary.Evidence{ .rejected = .right_reference_boundary }, boundary.evaluate(" ACTIVE", 1, 7, reference_edges));
    try std.testing.expectEqualDeep(boundary.Evidence{ .rejected = .right_reference_boundary }, boundary.evaluate(" ACTIVE.", 1, 7, reference_edges));
    const interior = boundary.evaluate(" ACTIVE ", 1, 7, reference_edges);
    try std.testing.expect(interior == .accepted);
    try std.testing.expectEqual(.whitespace, interior.accepted.left);
    try std.testing.expectEqual(.whitespace, interior.accepted.right);
}

test "contextual experiment preserves baseline punctuation results as separate evidence" {
    const recognition = @import("recognition.zig");
    for ([_]struct { prose: []const u8, value: []const u8, start: usize, end: usize }{
        .{ .prose = "Use version 1.2.3.", .value = "1.2", .start = 12, .end = 15 },
        .{ .prose = "Call /v1/renewals/archive.", .value = "/v1/renewals", .start = 5, .end = 17 },
    }) |case| {
        const baseline = try recognition.recognize(std.testing.allocator, .{ .prose = case.prose, .bound_requirements = &.{.{ .value = 1 }}, .occurrences = &.{.{ .id = .{ .value = 1 }, .requirements = &.{.{ .value = 1 }}, .bytes = case.value }} }, .{ .boundary_fn = unicode.wholeWordBoundary });
        defer baseline.deinit(std.testing.allocator);
        try std.testing.expectEqual(.matched, baseline.evaluated.state);
        try std.testing.expect(boundary.evaluate(case.prose, case.start, case.end, full_field_edges) == .rejected);
    }
}

test "contextual acceptance cannot establish semantic fulfillment or complete technical meaning" {
    // A conventional terminal dot cannot reveal whether it is prose punctuation
    // or part of a longer intended technical value. Denials also keep the bytes.
    for ([_]struct { prose: []const u8, start: usize, end: usize }{
        .{ .prose = "Display ACTIVE.", .start = 8, .end = 14 },
        .{ .prose = "Do not display ACTIVE.", .start = 15, .end = 21 },
        .{ .prose = "Use 1.2.", .start = 4, .end = 7 },
    }) |case| try std.testing.expect(boundary.evaluate(case.prose, case.start, case.end, full_field_edges) == .accepted);
    try std.testing.expect(!@hasField(boundary.DelimitedSpan, "coverage"));
    try std.testing.expect(!@hasField(boundary.DelimitedSpan, "fulfilled"));
    try std.testing.expect(!@hasField(boundary.DelimitedSpan, "occurrence"));
}
