//! The source selector of a clarification subject: which text of which source a need is about. It is derived from the
//! engine's own evidence, the citations of the claims a need concerns, and never from a model value, a per-run ID or a
//! hash, so the same gap on the same sources names the same subject on every run (design.md §3.3, item 31).
const std = @import("std");
const c = @import("clarification_inputs.zig");
const r = @import("reference_reconciliation.zig");
const coordinates = @import("source_coordinates.zig");

pub const Error = std.mem.Allocator.Error || error{InvalidClarificationInput};

/// One whole source. The path borrows the corpus; the caller owns the returned slice.
pub fn wholeSource(allocator: std.mem.Allocator, sources: []const r.evidence.Source, id: r.evidence.identity.SourceId) Error![]const c.SourceSpan {
    const spans = try allocator.alloc(c.SourceSpan, 1);
    errdefer allocator.free(spans);
    spans[0] = .{ .path = (try sourceOf(sources, id)).path.bytes, .lines = null };
    return spans;
}

/// The lines the named citations cover, as canonical spans (`merged`). A citation the evidence does not hold, a source the
/// corpus does not hold, or no citation at all, is not a subject. Paths borrow the corpus; the caller owns the returned
/// slice.
pub fn fromCitations(allocator: std.mem.Allocator, sources: []const r.evidence.Source, entries: []const r.Item, citation_ids: []const r.CitationId) Error![]const c.SourceSpan {
    const placed = try allocator.alloc(Placed, citation_ids.len);
    defer allocator.free(placed);
    for (citation_ids, placed) |id, *target| {
        const citation = citationOf(entries, id) orelse return error.InvalidClarificationInput;
        const lines = coordinates.lines(citation.value.location) catch return error.InvalidClarificationInput;
        target.* = .{ .path = (try sourceOf(sources, citation.value.source_id)).path.bytes, .first = lines.first, .last = lines.last };
    }
    return merged(allocator, placed);
}

/// Lines of one source, in any order and possibly repeated.
pub const Placed = struct { path: []const u8, first: u32, last: u32 };

/// Canonical spans of `placed`, which this sorts: lines that overlap or touch on one source are one span, so how a need's
/// evidence was split into citations does not change its subject. Nothing placed, lines that are not one-based and
/// ordered, and more spans than a subject may name (`max_subject_spans`) are not a subject.
pub fn merged(allocator: std.mem.Allocator, placed: []Placed) Error![]const c.SourceSpan {
    if (placed.len == 0) return error.InvalidClarificationInput;
    for (placed) |item| if (item.first == 0 or item.last < item.first) return error.InvalidClarificationInput;
    std.mem.sort(Placed, placed, {}, lessPlaced);
    var spans: std.ArrayList(c.SourceSpan) = .empty;
    errdefer spans.deinit(allocator);
    for (placed) |item| {
        if (spans.items.len != 0) {
            const tail = &spans.items[spans.items.len - 1];
            if (std.mem.eql(u8, tail.path, item.path)) {
                const lines = tail.lines.?;
                if (item.first <= lines.last +| 1) {
                    tail.lines = .{ .first = lines.first, .last = @max(lines.last, item.last) };
                    continue;
                }
            }
        }
        try spans.append(allocator, .{ .path = item.path, .lines = .{ .first = item.first, .last = item.last } });
    }
    const result = try spans.toOwnedSlice(allocator);
    errdefer allocator.free(result);
    if (!c.validSources(result)) return error.InvalidClarificationInput;
    return result;
}

fn lessPlaced(_: void, a: Placed, b: Placed) bool {
    const path = std.mem.order(u8, a.path, b.path);
    if (path != .eq) return path == .lt;
    if (a.first != b.first) return a.first < b.first;
    return a.last < b.last;
}

fn citationOf(entries: []const r.Item, id: r.CitationId) ?r.extraction.Citation {
    for (entries) |entry| for (entry.citations) |citation| if (citation.id.ordinal == id.ordinal) return citation;
    return null;
}

fn sourceOf(sources: []const r.evidence.Source, id: r.evidence.identity.SourceId) error{InvalidClarificationInput}!r.evidence.Source {
    for (sources) |source| if (source.id.ordinal == id.ordinal) return source;
    return error.InvalidClarificationInput;
}
