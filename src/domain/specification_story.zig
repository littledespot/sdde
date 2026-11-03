//! ADR 0047: the engine composes the primary user story from the business claims
//! of its catalogue. Native code joins the quoted source lines and strips their
//! Markdown structure; it judges no meaning and writes no wording of its own.
const std = @import("std");
const g = @import("specification_generation.zig");
const p = @import("specification_provenance.zig");
const r = @import("reference_reconciliation.zig");
const text = @import("typed_text.zig");
const binding = @import("specification_source_binding.zig");
const sessions = @import("specification_session.zig");
const markdown = @import("markdown_code_spans.zig");

pub const Error = sessions.Error;
pub const Composition = union(enum) { story: g.spec.Values(.model).AttributedValue, blocked: binding.Rejection };
pub const Outcome = union(enum) { composed: sessions.Session, blocked: binding.Rejection };

/// The story unit's value: its catalogue's business claims in source order, each
/// quote flattened to one paragraph (`paragraph`) and joined by one space. A quote of
/// headings alone is skipped. The story selects the groups whose claims it quotes;
/// unit validation recognises its exact values as in model text. Without a
/// business claim to quote, it blocks.
pub fn compose(a: std.mem.Allocator, current: sessions.Session, context: p.Context) Error!Composition {
    const available = switch (try sessions.currentBinding(a, current, context)) {
        .primary_user_story => |catalogue| catalogue,
        .brief, .entities, .records => return error.InvalidSpecificationUnit,
    };
    const groups = try binding.catalogue(a, available.records, .content);
    var structure = try Structure.init(a, context.inputs);
    var quotes: std.ArrayList(Quote) = .empty;
    for (groups) |group| for (group.claim_ids) |id| {
        if (quoted(quotes.items, id)) continue;
        const item = try r.item(available.records.items, id);
        if (item.claim.content != .model or item.claim.content.model != .business) continue;
        const at = try sourcePosition(context.inputs, item);
        const segments = (try paragraph(a, &structure, item, at.source)) orelse continue;
        try quotes.append(a, .{ .claim_id = id, .at = at, .segments = segments });
    };
    if (quotes.items.len == 0) return .{ .blocked = try binding.storyRejection(a, context.references, .no_requirements) };
    std.mem.sort(Quote, quotes.items, {}, Quote.before);
    var joined: std.ArrayList(text.BusinessSegment) = .empty;
    for (quotes.items, 0..) |quote, index| {
        if (index != 0) try joined.append(a, .{ .literal = .{ .value = " " } });
        try joined.appendSlice(a, quote.segments);
    }
    // Unit validation recognises exact values with the same native recognizer as
    // model text, so a recognition failure is a typed unit issue there.
    const value: g.spec.BusinessValue = .{ .segments = joined.items };
    var signal_ids: std.ArrayList(r.SignalId) = .empty;
    for (groups) |group| for (group.claim_ids) |id| {
        if (!quoted(quotes.items, id)) continue;
        try signal_ids.append(a, group.signal_id);
        break;
    };
    return .{ .story = try g.associated(a, available, .{ .value = value, .signal_ids = signal_ids.items }, .content) };
}

/// Where a claim's quote starts: its source's corpus position, then its first cited byte.
const Position = struct { source: usize, byte: usize };
const Quote = struct {
    claim_id: r.ClaimId,
    at: Position,
    segments: []const text.BusinessSegment,

    fn before(_: void, left: Quote, right: Quote) bool {
        if (left.at.source != right.at.source) return left.at.source < right.at.source;
        if (left.at.byte != right.at.byte) return left.at.byte < right.at.byte;
        return left.claim_id.ordinal < right.claim_id.ordinal;
    }
};

fn quoted(quotes: []const Quote, id: r.ClaimId) bool {
    for (quotes) |quote| if (quote.claim_id.ordinal == id.ordinal) return true;
    return false;
}

fn sourcePosition(inputs: @import("reference_evidence.zig").Inputs, item: r.Item) Error!Position {
    const source = for (inputs.corpus.sources, 0..) |candidate, index| {
        if (candidate.id.ordinal == item.source_id.ordinal) break index;
    } else return error.InvalidSpecificationUnit;
    if (item.citations.len == 0) return error.InvalidSpecificationUnit;
    var byte: usize = std.math.maxInt(usize);
    for (item.citations) |citation| byte = @min(byte, citation.value.location.start.byte);
    return .{ .source = source, .byte = byte };
}

/// Each corpus source's line structure, read once through its source's reader.
const Structure = struct {
    inputs: @import("reference_evidence.zig").Inputs,
    sources: []?[]const markdown.ListLine,

    fn init(a: std.mem.Allocator, inputs: @import("reference_evidence.zig").Inputs) std.mem.Allocator.Error!Structure {
        const sources = try a.alloc(?[]const markdown.ListLine, inputs.corpus.sources.len);
        @memset(sources, null);
        return .{ .inputs = inputs, .sources = sources };
    }
    fn of(self: *Structure, a: std.mem.Allocator, index: usize) std.mem.Allocator.Error![]const markdown.ListLine {
        const source = self.inputs.corpus.sources[index];
        if (self.sources[index] == null) self.sources[index] = switch (source.reader) {
            .markdown_source_v1 => try markdown.listSegments(a, source.bytes),
        };
        return self.sources[index].?;
    }
};

/// A claim's quote as one paragraph, read from its cited source lines (ADR 0036):
/// blank and heading lines dropped, each other line's indentation and list marker
/// removed, and the lines joined by one space. A code line keeps its words as text.
/// Runs cited apart keep the quote's ellipsis between them. Null when no line has
/// words, as for a quote of headings alone.
fn paragraph(a: std.mem.Allocator, structure: *Structure, item: r.Item, source_index: usize) Error!?[]const text.BusinessSegment {
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
    const result = try a.alloc(text.BusinessSegment, 1);
    result[0] = .{ .literal = .{ .value = bytes.items } };
    return result;
}
