//! Shared contextual delimiters for exact-value occurrence recognition.
//! A delimiter witness proves lexical separation, never semantic fulfillment.
const std = @import("std");

pub const policy_name = "delimited_complete_value_v1";

/// Closed Unicode 17 White_Space syntax. Offline boundary tests exhaustively
/// compare this set with the pinned Unicode categories and control cases.
pub fn isWhitespace(scalar: u21) bool {
    return switch (scalar) {
        0x09...0x0d, 0x20, 0x85, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000 => true,
        else => false,
    };
}

pub const Delimiter = enum { field_edge, whitespace };
/// A literal run adjacent to a reference does not expose its rendered context.
/// That opaque edge cannot stand in for the beginning/end of the whole field.
pub const Edge = enum { field_edge, reference_boundary };
pub const Edges = struct { left: Edge, right: Edge };
pub const DelimitedSpan = struct {
    outer_start_byte: usize,
    outer_end_byte: usize,
    left: Delimiter,
    right: Delimiter,
    enclosing_wrappers: usize,
    terminal_punctuation: usize,
};
pub const Rejection = enum {
    invalid_utf8,
    invalid_span,
    invalid_scalar_boundary,
    left_continuation,
    right_continuation,
    unbalanced_wrapper,
    terminal_punctuation_continuation,
    left_reference_boundary,
    right_reference_boundary,
};
pub const Evidence = union(enum) { accepted: DelimitedSpan, rejected: Rejection };

/// Borrowed raw UTF-8, validated once for evaluating every candidate span in one
/// field. This type conveys no normalization, composition or occurrence proof.
pub const Utf8Prose = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) ?Utf8Prose {
        if (!std.unicode.utf8ValidateSlice(bytes)) return null;
        return .{ .bytes = bytes };
    }

    pub fn evaluate(self: Utf8Prose, start: usize, end: usize, edges: Edges) Evidence {
        return evaluateSpan(self.bytes, start, end, edges);
    }
};

/// Evaluate an already exact byte span, without finding a value or changing any
/// bytes. Both sides must reach whitespace/field edge after removing directly
/// enclosing balanced wrappers and conventional terminal prose punctuation.
/// Punctuation attached to more text stays part of the value's lexical unit.
///
/// Wrappers must enclose this complete span directly; a quote/group surrounding
/// a longer phrase cannot lend its closing boundary to the phrase's final word.
/// Whitespace inside the exact span is untouched. The v1 wrapper/terminal tables
/// below are the closed policy, independent of token kind or domain.
///
/// Terminal punctuation before whitespace/end remains lexically ambiguous: a
/// final dot might belong to a technical value, and a match can be negated. This
/// deliberately reports its punctuation evidence instead of claiming meaning.
pub fn evaluate(prose: []const u8, start: usize, end: usize, edges: Edges) Evidence {
    const parsed = Utf8Prose.parse(prose) orelse return .{ .rejected = .invalid_utf8 };
    return parsed.evaluate(start, end, edges);
}

fn evaluateSpan(prose: []const u8, start: usize, end: usize, edges: Edges) Evidence {
    if (start >= end or end > prose.len) return .{ .rejected = .invalid_span };
    if (!scalarBoundary(prose, start) or !scalarBoundary(prose, end)) return .{ .rejected = .invalid_scalar_boundary };
    var left = start;
    var right = end;
    var wrappers: usize = 0;
    var terminals: usize = 0;
    while (left != 0 and right != prose.len) {
        const before = previous(prose, left);
        const closing = closingWrapper(before.scalar) orelse break;
        var cursor = right;
        var inner_terminals: usize = 0;
        while (cursor < prose.len) {
            const item = next(prose, cursor);
            if (!terminal(item.scalar)) break;
            inner_terminals += 1;
            cursor = item.end;
        }
        if (cursor == prose.len) break;
        const after = next(prose, cursor);
        if (after.scalar != closing) break;
        left = before.start;
        right = after.end;
        wrappers += 1;
        terminals += inner_terminals;
    }
    const left_delimiter: Delimiter = if (left == 0) blk: {
        if (edges.left == .reference_boundary) return .{ .rejected = .left_reference_boundary };
        break :blk .field_edge;
    } else blk: {
        const item = previous(prose, left);
        if (wrapper(item.scalar)) return .{ .rejected = .unbalanced_wrapper };
        if (!isWhitespace(item.scalar)) return .{ .rejected = .left_continuation };
        break :blk .whitespace;
    };
    while (right < prose.len) {
        const item = next(prose, right);
        if (!terminal(item.scalar)) break;
        terminals += 1;
        right = item.end;
    }
    const right_delimiter: Delimiter = if (right == prose.len) blk: {
        if (edges.right == .reference_boundary) return .{ .rejected = .right_reference_boundary };
        break :blk .field_edge;
    } else blk: {
        const item = next(prose, right);
        if (wrapper(item.scalar)) return .{ .rejected = .unbalanced_wrapper };
        if (!isWhitespace(item.scalar)) return .{ .rejected = if (terminals != 0) .terminal_punctuation_continuation else .right_continuation };
        break :blk .whitespace;
    };
    return .{ .accepted = .{
        .outer_start_byte = left,
        .outer_end_byte = right,
        .left = left_delimiter,
        .right = right_delimiter,
        .enclosing_wrappers = wrappers,
        .terminal_punctuation = terminals,
    } };
}

fn scalarBoundary(prose: []const u8, index: usize) bool {
    return index == prose.len or prose[index] & 0xc0 != 0x80;
}
const Scalar = struct { scalar: u21, start: usize, end: usize };
fn next(prose: []const u8, index: usize) Scalar {
    // evaluate established valid UTF-8 and every cursor is a scalar boundary.
    const size = std.unicode.utf8ByteSequenceLength(prose[index]) catch unreachable;
    return .{ .scalar = std.unicode.utf8Decode(prose[index .. index + size]) catch unreachable, .start = index, .end = index + size };
}
fn previous(prose: []const u8, index: usize) Scalar {
    var cursor = index - 1;
    while (prose[cursor] & 0xc0 == 0x80) cursor -= 1;
    return next(prose, cursor);
}
fn terminal(scalar: u21) bool {
    return switch (scalar) {
        '.', ',', ';', ':', '!', '?', 0x2026, 0x3001, 0x3002, 0xff0c, 0xff1b, 0xff1a, 0xff01, 0xff1f => true,
        else => false,
    };
}
fn closingWrapper(scalar: u21) ?u21 {
    return switch (scalar) {
        '(' => ')',
        '[' => ']',
        '{' => '}',
        '"', '\'', '`' => scalar,
        0x00ab => 0x00bb,
        0x2018 => 0x2019,
        0x201c => 0x201d,
        0x2039 => 0x203a,
        0x3008 => 0x3009,
        0x300a => 0x300b,
        0x300c => 0x300d,
        0x300e => 0x300f,
        0x3010 => 0x3011,
        0xff08 => 0xff09,
        0xff3b => 0xff3d,
        0xff5b => 0xff5d,
        else => null,
    };
}
fn wrapper(scalar: u21) bool {
    if (closingWrapper(scalar) != null) return true;
    return switch (scalar) {
        ')', ']', '}', 0x00bb, 0x2019, 0x201d, 0x203a, 0x3009, 0x300b, 0x300d, 0x300f, 0x3011, 0xff09, 0xff3d, 0xff5d => true,
        else => false,
    };
}
