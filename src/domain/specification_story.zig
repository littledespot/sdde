//! ADR 0047: the engine composes the primary user story from the business claims
//! of its catalogue. Native code joins the quoted source lines and strips their
//! Markdown structure; it judges no meaning and writes no wording of its own.
const std = @import("std");
const g = @import("specification_generation.zig");
const p = @import("specification_provenance.zig");
const r = @import("reference_reconciliation.zig");
const text = @import("typed_text.zig");
const binding = @import("specification_source_binding.zig");
const refs = @import("reference_support.zig");
const sessions = @import("specification_session.zig");
const reading = @import("source_paragraph.zig");

pub const Error = sessions.Error;
pub const Composition = union(enum) { story: g.spec.Values(.model).AttributedValue, blocked: binding.Rejection };
pub const Outcome = union(enum) { composed: sessions.Session, blocked: binding.Rejection };

/// The story unit's value: its catalogue's business claims, and any question an applied answer kept, in source order, each
/// quote flattened to one paragraph (`reading.paragraph`) and joined by one space. A quote of
/// headings alone is skipped. The story selects the groups whose claims it quotes;
/// unit validation recognises its exact values as in model text. Without a
/// business claim to quote, it blocks.
pub fn compose(a: std.mem.Allocator, current: sessions.Session, context: p.Context) Error!Composition {
    const available = switch (try sessions.currentBinding(a, current, context)) {
        .primary_user_story => |catalogue| catalogue,
        .brief, .entities, .records => return error.InvalidSpecificationUnit,
    };
    const groups = try binding.catalogue(a, available.records, .content);
    var structure = try reading.Structure.init(a, context.inputs);
    var quotes: std.ArrayList(Quote) = .empty;
    for (groups) |group| for (group.claim_ids) |id| {
        if (quoted(quotes.items, id)) continue;
        const item = try r.item(available.records.items, id);
        if (item.claim.content != .model or (item.claim.content.model != .business and !try refs.answeredQuestion(available.records, id))) continue;
        const at = try sourcePosition(structure, item);
        const words = (try reading.paragraph(a, &structure, item)) orelse continue;
        const segments = try a.alloc(text.BusinessSegment, 1);
        segments[0] = .{ .literal = .{ .value = words } };
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

fn sourcePosition(structure: reading.Structure, item: r.Item) Error!Position {
    const source = try structure.position(item);
    if (item.citations.len == 0) return error.InvalidSpecificationUnit;
    var byte: usize = std.math.maxInt(usize);
    for (item.citations) |citation| byte = @min(byte, citation.value.location.start.byte);
    return .{ .source = source, .byte = byte };
}
