//! ADR 0036 Decision 2: a claim's cited source lines read as one paragraph. The primary
//! story composes its text from this reading (ADR 0047) and the records, entities and
//! scenarios requests show each claim's wording in it. Native code removes Markdown
//! structure; it judges no meaning and writes no wording of its own.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const evidence = @import("reference_evidence.zig");
const markdown = @import("markdown_code_spans.zig");

pub const Error = std.mem.Allocator.Error || error{InvalidSpecificationUnit};

/// Each corpus source's line structure, read once through its source's reader. The caller
/// owns an arena; neither this nor `paragraph` frees what it allocates.
pub const Structure = struct {
    inputs: evidence.Inputs,
    sources: []?[]const markdown.ListLine,

    pub fn init(a: std.mem.Allocator, inputs: evidence.Inputs) std.mem.Allocator.Error!Structure {
        const sources = try a.alloc(?[]const markdown.ListLine, inputs.corpus.sources.len);
        @memset(sources, null);
        return .{ .inputs = inputs, .sources = sources };
    }

    /// The corpus position of the source an item cites.
    pub fn position(self: Structure, item: r.Item) error{InvalidSpecificationUnit}!usize {
        for (self.inputs.corpus.sources, 0..) |candidate, index| {
            if (candidate.id.ordinal == item.source_id.ordinal) return index;
        }
        return error.InvalidSpecificationUnit;
    }

    fn of(self: *Structure, a: std.mem.Allocator, index: usize) std.mem.Allocator.Error![]const markdown.ListLine {
        const source = self.inputs.corpus.sources[index];
        if (self.sources[index] == null) self.sources[index] = switch (source.reader) {
            .markdown_source_v1 => try markdown.listSegments(a, source.bytes),
        };
        return self.sources[index].?;
    }
};

/// A claim's quote as one paragraph, read from its cited source lines: blank and
/// heading lines dropped, each other line's indentation and list marker removed, and
/// the lines joined by one space. A code line keeps its words as text. Runs cited
/// apart keep the quote's ellipsis between them. Null when no line has words, as for a
/// quote of headings alone.
pub fn paragraph(a: std.mem.Allocator, structure: *Structure, item: r.Item) Error!?[]const u8 {
    const source_index = try structure.position(item);
    const source = structure.inputs.corpus.sources[source_index];
    const lines = try structure.of(a, source_index);
    var bytes: std.ArrayList(u8) = .empty;
    for (item.citations) |citation| {
        const span = citation.value.location;
        if (citation.value.source_id.ordinal != source.id.ordinal or span.start.byte > span.end.byte or span.end.byte > source.bytes.len) return error.InvalidSpecificationUnit;
        var run: std.ArrayList(u8) = .empty;
        for (lines) |line| {
            const end = std.mem.indexOfAnyPos(u8, source.bytes, line.start, "\r\n") orelse source.bytes.len;
            if (line.start >= span.end.byte or end < span.start.byte or line.heading) continue;
            const from = @max(line.start + line.wording, span.start.byte);
            const to = @min(end, span.end.byte);
            if (from >= to) continue;
            const words = std.mem.trim(u8, source.bytes[from..to], " \t");
            if (words.len == 0) continue;
            if (run.items.len != 0) try run.append(a, ' ');
            try run.appendSlice(a, words);
        }
        if (run.items.len == 0) continue;
        if (bytes.items.len != 0) try bytes.appendSlice(a, " … ");
        try bytes.appendSlice(a, run.items);
    }
    if (bytes.items.len == 0) return null;
    return bytes.items;
}
