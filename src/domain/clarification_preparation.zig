//! Pure question/context projection into caller-arena storage. Semantic findings
//! and answer authority stay with their owners.
const std = @import("std");
const c = @import("clarification_inputs.zig");
const r = @import("reference_reconciliation.zig");
const reference_view = @import("workflow_artifact_registry.zig").reference_context_filename;
pub const Prepared = struct { question: []const u8, why_required: []const u8 };
pub const Evidence = struct { citation_ids: []const r.CitationId = &.{}, source_ids: []const @import("reference_identity.zig").SourceId = &.{} };
pub fn prepare(allocator: std.mem.Allocator, question: []const u8, reason: []const u8, items: []const r.Item, evidence: Evidence) c.Error!Prepared {
    if (!c.validText(question, c.max_text_bytes) or !c.validText(reason, c.max_text_bytes)) return error.InvalidClarificationInput;
    var context: std.ArrayList(u8) = .empty;
    defer context.deinit(allocator);
    var selected: std.ArrayList(r.extraction.Citation) = .empty;
    defer selected.deinit(allocator);
    for (items) |item| {
        for (item.citations) |citation| next: {
            if (evidence.citation_ids.len != 0) {
                if (!r.contains(r.CitationId, evidence.citation_ids, citation.id)) continue;
            } else if (!r.contains(@import("reference_identity.zig").SourceId, evidence.source_ids, item.source_id)) continue;
            for (selected.items) |prior| if (std.meta.eql(prior.id, citation.id) or contains(prior.value, citation.value)) break :next;
            var index: usize = 0;
            while (index < selected.items.len) {
                if (contains(citation.value, selected.items[index].value)) {
                    _ = selected.orderedRemove(index);
                } else index += 1;
            }
            try selected.append(allocator, citation);
        }
    }
    for (selected.items) |citation| {
        const value = citation.value;
        const line = try std.fmt.allocPrint(allocator, "\nSource {d}, lines {d}–{d}: {s}", .{ value.source_id.ordinal, value.location.start.line, value.location.end.line, value.verbatim orelse "See " ++ reference_view ++ " for the captured source." });
        defer allocator.free(line);
        try context.appendSlice(allocator, line);
    }
    const heading = "\n\nCurrent source evidence (the review concern remains unresolved):";
    // Reference the complete existing view when excerpts exceed the form contract;
    // never truncate a quotation or invent a semantic summary to make it fit.
    const fallback = "\n\nCurrent source evidence: see " ++ reference_view ++ ". The review concern is not a resolved answer.";
    if (items.len != 0 and question.len + fallback.len > c.max_text_bytes) {
        if (reason.len + fallback.len > c.max_text_bytes) return error.InvalidClarificationInput;
        return .{ .question = try allocator.dupe(u8, question), .why_required = try std.fmt.allocPrint(allocator, "{s}{s}", .{ reason, fallback }) };
    }
    const result = if (items.len == 0) try allocator.dupe(u8, question) else if (context.items.len != 0 and question.len + heading.len + context.items.len <= c.max_text_bytes)
        try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ question, heading, context.items })
    else
        try std.fmt.allocPrint(allocator, "{s}{s}", .{ question, fallback });
    return .{ .question = result, .why_required = reason };
}

/// Presentation only: suppress an excerpt only when a selected outer quotation
/// contains its exact bytes at the same captured source coordinates.
fn contains(outer: r.evidence.ValidatedCitation, inner: r.evidence.ValidatedCitation) bool {
    if (!std.meta.eql(outer.source_id, inner.source_id) or !std.meta.eql(outer.block_id, inner.block_id) or outer.location.start.byte > inner.location.start.byte or outer.location.end.byte < inner.location.end.byte) return false;
    const bytes = outer.verbatim orelse return false;
    const excerpt = inner.verbatim orelse return false;
    const offset = inner.location.start.byte - outer.location.start.byte;
    return offset <= bytes.len and excerpt.len <= bytes.len - offset and std.mem.eql(u8, bytes[offset..][0..excerpt.len], excerpt);
}
