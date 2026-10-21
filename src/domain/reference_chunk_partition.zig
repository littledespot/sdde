//! The native chunk partition of identified reference sources (ADR 0027).
//! Markdown list structure decides chunk boundaries, so a model extracts one
//! top-level list item at a time instead of deciding how to split a list. Each
//! top-level item, with its nested items and continuation lines, is one chunk;
//! the lines between lists form text chunks. An item chunk carries the nearest
//! heading and the paragraph that introduces its list as non-citable lead-in
//! context. Chunks tile their reader block exactly, never cross one and never
//! start inside an exact-value span. Syntax identifies form, not meaning.
const std = @import("std");
const evidence = @import("reference_evidence.zig");
const input = @import("reference_ingestion.zig");
const code = @import("markdown_code_spans.zig");

pub const Error = evidence.Error;
pub const id: @FieldType(evidence.Chunks, "partition") = .source_list_items_v1;

const Line = struct { start: usize, next: usize, number: u32 };
const Segment = struct { line: Line, lead_in: []const input.Span };

/// Build the canonical partition. Every result slice is allocated from
/// `allocator`; pass an arena.
pub fn partition(allocator: std.mem.Allocator, corpus: evidence.Corpus) Error!evidence.Chunks {
    var chunks: std.ArrayList(evidence.Chunk) = .empty;
    for (corpus.sources) |source| {
        const found = switch (source.reader) {
            .markdown_source_v1 => try markdownSegments(allocator, source.bytes),
        };
        var segment_index: usize = 0;
        for (source.blocks) |block| {
            var ordinal: u32 = 0;
            while (segment_index < found.len) {
                const segment = found[segment_index];
                const segment_end: Line = if (segment_index + 1 < found.len) found[segment_index + 1].line else .{ .start = source.bytes.len, .next = source.bytes.len, .number = 0 };
                if (segment.line.start >= block.span.end.byte) break;
                const start = if (segment.line.start > block.span.start.byte) lineStart(segment.line) else block.span.start;
                const ends_inside = segment_end.start < block.span.end.byte;
                const end = if (ends_inside) lineStart(segment_end) else block.span.end;
                if (end.byte > start.byte) {
                    ordinal += 1;
                    try chunks.append(allocator, .{
                        .id = try evidence.identity.chunkId(allocator, @intCast(chunks.items.len + 1)),
                        .source_id = source.id,
                        .block_id = block.id,
                        .ordinal = ordinal,
                        .span = .{ .start = start, .end = end },
                        .lead_in = segment.lead_in,
                    });
                }
                if (!ends_inside) break;
                segment_index += 1;
            }
        }
    }
    return .{ .state_id = corpus.state_id, .partition = id, .entries = try chunks.toOwnedSlice(allocator) };
}

/// Chunks are valid only when they equal the canonical partition of the corpus.
pub fn validate(allocator: std.mem.Allocator, corpus: evidence.Corpus, chunks: evidence.Chunks) Error!void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const expected = try partition(arena.allocator(), corpus);
    if (!chunks.state_id.eql(corpus.state_id) or chunks.partition != expected.partition or chunks.entries.len != expected.entries.len) return error.InvalidReferenceChunks;
    for (chunks.entries, expected.entries) |actual, wanted| {
        if (!actual.id.eql(wanted.id) or actual.source_id.ordinal != wanted.source_id.ordinal or actual.block_id.ordinal != wanted.block_id.ordinal or
            actual.ordinal != wanted.ordinal or !std.meta.eql(actual.span, wanted.span) or actual.lead_in.len != wanted.lead_in.len) return error.InvalidReferenceChunks;
        for (actual.lead_in, wanted.lead_in) |a, b| if (!std.meta.eql(a, b)) return error.InvalidReferenceChunks;
    }
}

fn lineStart(line: Line) input.Position {
    return .{ .byte = line.start, .line = line.number, .column = 1 };
}

fn lineSpan(first: Line, last: Line) input.Span {
    return .{ .start = lineStart(first), .end = .{ .byte = last.next, .line = last.number + 1, .column = 1 } };
}

/// Fenced code content, a fence's closing line, and lines that start inside a
/// multi-line inline span are hidden: they are never classified and never start
/// a chunk. A fence's opening line is classified like any other line, so a
/// fence after a list ends it. Lines are visited in order.
const Opacity = struct {
    ranges: []const code.Range,
    index: usize = 0,

    const Hidden = enum { visible, fence_opening, code, inline_span };

    fn hidden(self: *Opacity, line: Line) Hidden {
        while (self.index < self.ranges.len and self.ranges[self.index].end < line.start) self.index += 1;
        for (self.ranges[self.index..]) |range| {
            if (range.form == .code_block and range.start == line.next) return .fence_opening;
            if (range.start > line.start) break;
            if (range.form == .code_block) {
                if (line.start < range.end or line.start == range.end) return .code;
            } else if (line.start > range.start and line.start < range.end) return .inline_span;
        }
        return .visible;
    }

    /// Whether any exact-value span overlaps the bytes. Lead-in text with an
    /// exact value would let item claims copy a value whose native duty is
    /// scoped to another chunk (ADR 0024), so such a list is not split.
    fn exact(self: Opacity, from: usize, to: usize) bool {
        // Ranges are sorted and disjoint: find the first that ends after `from`.
        var low: usize = 0;
        var high = self.ranges.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.ranges[middle].end <= from) low = middle + 1 else high = middle;
        }
        return low < self.ranges.len and self.ranges[low].start < to;
    }
};

fn markdownSegments(allocator: std.mem.Allocator, bytes: []const u8) Error![]const Segment {
    const exact = try code.scanAll(allocator, bytes);
    var opacity: Opacity = .{ .ranges = exact };
    var segments: std.ArrayList(Segment) = .empty;
    try segments.append(allocator, .{ .line = .{ .start = 0, .next = 0, .number = 1 }, .lead_in = &.{} });
    // The open list: its content column, which nested items reach, its
    // context, and whether its items are chunks of their own.
    var list: ?struct { content: usize, lead_in: []const input.Span, split: bool } = null;
    var heading: ?struct { first: Line, last: Line } = null;
    var paragraph: ?struct { first: Line, last: Line } = null;
    var paragraph_open = false;
    var blank_before = false;
    // A list ended by a separator keeps that line; text after it starts a chunk.
    var text_pending = false;
    var offset: usize = 0;
    var number: u32 = 1;
    while (offset < bytes.len) : (number += 1) {
        const end, const next = code.lineAt(bytes, offset);
        const line: Line = .{ .start = offset, .next = next, .number = number };
        defer offset = next;
        const visibility = opacity.hidden(line);
        switch (visibility) {
            .visible, .fence_opening => {},
            .code => {
                if (list == null) paragraph = null;
                paragraph_open = false;
                blank_before = false;
                continue;
            },
            .inline_span => {
                if (list == null and paragraph_open) paragraph.?.last = line;
                blank_before = false;
                continue;
            },
        }
        const form = code.lineForm(bytes[offset..end]);
        if (form == .blank) {
            blank_before = true;
            paragraph_open = false;
            continue;
        }
        defer blank_before = false;
        if (list) |*current| {
            // A block line ends the list only when it is outdented from the
            // item; indented, it is item content. A fence ends it even without
            // a blank line before it.
            const ends = switch (form) {
                .heading => |heading_line| heading_line.indent < current.content,
                .separator => |separator| separator.indent < current.content,
                .other => |other| (blank_before or visibility == .fence_opening) and other.indent < current.content,
                .list_item, .blank => false,
            };
            if (!ends) {
                // A sibling starts its own chunk; a nested item stays with its parent.
                if (form == .list_item and form.list_item.indent < current.content) {
                    current.content = form.list_item.content;
                    if (current.split) try begin(allocator, &segments, line, current.lead_in);
                }
                continue;
            }
            const split = current.split;
            list = null;
            if (form == .separator) {
                text_pending = split;
                continue;
            }
            if (split) try begin(allocator, &segments, line, &.{});
        } else if (text_pending and form != .list_item) {
            text_pending = false;
            try begin(allocator, &segments, line, &.{});
        }
        switch (form) {
            .heading => {
                heading = .{ .first = line, .last = line };
                paragraph = null;
                paragraph_open = false;
            },
            .separator => |separator| {
                // A setext underline turns its paragraph into the nearest heading.
                if (separator.underline and paragraph_open) heading = .{ .first = paragraph.?.first, .last = line };
                paragraph = null;
                paragraph_open = false;
            },
            .other => {
                if (paragraph_open) paragraph.?.last = line else paragraph = .{ .first = line, .last = line };
                paragraph_open = true;
            },
            .list_item => |item| {
                // Only a bullet, or a list starting at 1, can interrupt a paragraph.
                if (paragraph_open and !item.interrupts) {
                    paragraph.?.last = line;
                    continue;
                }
                var lead_in: std.ArrayList(input.Span) = .empty;
                var split = true;
                if (heading) |value| {
                    split = split and !opacity.exact(value.first.start, value.last.next);
                    try lead_in.append(allocator, lineSpan(value.first, value.last));
                }
                if (paragraph) |value| {
                    split = split and !opacity.exact(value.first.start, value.last.next);
                    try lead_in.append(allocator, lineSpan(value.first, value.last));
                }
                const context = if (split) try lead_in.toOwnedSlice(allocator) else &.{};
                text_pending = false;
                list = .{ .content = item.content, .lead_in = context, .split = split };
                paragraph = null;
                paragraph_open = false;
                if (split) try begin(allocator, &segments, line, context);
            },
            .blank => unreachable,
        }
    }
    return segments.toOwnedSlice(allocator);
}

fn begin(allocator: std.mem.Allocator, segments: *std.ArrayList(Segment), line: Line, lead_in: []const input.Span) Error!void {
    const last = &segments.items[segments.items.len - 1];
    if (last.line.start == line.start) {
        last.* = .{ .line = line, .lead_in = lead_in };
        return;
    }
    try segments.append(allocator, .{ .line = line, .lead_in = lead_in });
}
