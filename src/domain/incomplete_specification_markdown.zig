//! Incomplete-view renderer. Questions link to controlled forms; this format
//! deliberately cannot parse as the completed editable specification contract.
const std = @import("std");
const draft = @import("incomplete_specification.zig");
const c = @import("clarification_inputs.zig");
const r = @import("reference_reconciliation.zig");
const reading = @import("source_paragraph.zig");
const code_spans = @import("markdown_code_spans.zig");
const markdown = @import("specification_markdown.zig");
const naming = @import("naming_policy.zig");
const reference_markdown = @import("reference_markdown.zig");
const snapshot = @import("reference_snapshot.zig");
const text = @import("typed_text.zig");
const unicode = @import("../ports/unicode_normalizer.zig");
pub const Error = draft.Error || reference_markdown.Error || r.Error || reading.Error || naming.Error;

pub fn render(a: std.mem.Allocator, value: draft.State, clarifications: c.ValidatedState, normalizer: unicode.Normalizer) Error![]const u8 {
    _ = try draft.bindClarifications(value, clarifications);
    // The claims' joins and readings live in the scratch arena; only the view outlives it.
    var scratch: std.heap.ArenaAllocator = .init(a);
    defer scratch.deinit();
    const items = try @import("reference_claim_items.zig").build(scratch.allocator(), value.reference.inputs, value.reference.extraction);
    var structure = try reading.Structure.init(scratch.allocator(), value.reference.inputs);
    var out: std.Io.Writer.Allocating = .init(a);
    errdefer out.deinit();
    const w = &out.writer;
    try write(w, "# Feature Specification\n\n**Status: Incomplete — awaiting clarification**\n\nThe requirements below retain current source-supported business content. Resolve the linked questions before planning.\n");
    inline for (.{ .{ @import("reference_extraction.zig").Kind.business, "Supported Requirements" }, .{ @import("reference_extraction.zig").Kind.scope_guard, "Scope Constraints" } }) |section| {
        try write(w, "\n## " ++ section[1] ++ "\n\n");
        var count: usize = 0;
        for (value.reference.extraction.claims, value.reference.dispositions, items.entries) |claim, disposition, item| {
            if (!@import("reference_support.zig").eligibleClaim(disposition.disposition) or
                claim.content != .model or claim.content.model != section[0]) continue;
            try write(w, "- ");
            try claimText(scratch.allocator(), w, value.reference, &structure, item, @field(claim.content.model, @tagName(section[0])).value, normalizer);
            try write(w, "\n");
            count += 1;
        }
        if (count == 0) try write(w, "No supported content is available for this section yet.\n");
    }
    try write(w, "\n## Open Clarifications\n\n");
    for (value.open_clarifications) |id| {
        const name = id.filename();
        // Filenames and link targets come only from the validated native ID.
        w.print("- [{s}]({s}/{s})\n", .{ name[0..3], @import("workflow_artifact_registry.zig").clarification_directory_name, name }) catch return error.OutOfMemory;
    }
    return out.toOwnedSlice();
}

/// A claim's text on its list line (ADR 0017): the paragraph reading of its cited source lines, with
/// each of the source's own inline code spans written as an engine code span and the text between
/// them through the canonical escape table. The reading is source bytes, which no ingestion step
/// normalizes, so each run of prose is NFC like the stored claim text; a code span keeps its
/// source bytes, as an exact value does. The stored quote, as written, shows only for a claim
/// whose reading has no words, and it is already canonical. `a` is the caller's scratch arena.
fn claimText(a: std.mem.Allocator, w: *std.Io.Writer, reference: snapshot.Snapshot, structure: *reading.Structure, item: r.Item, stored: text.BusinessText, normalizer: unicode.Normalizer) Error!void {
    const words = (try reading.paragraph(a, structure, item)) orelse return reference_markdown.business(w, reference, stored, .block_start);
    var offset: usize = 0;
    for (try code_spans.scan(a, words)) |span| {
        // The scan's range is the span's interior; equal runs of backticks delimit it.
        const delimiter = std.mem.indexOfNone(u8, words[span.end..], "`") orelse words.len - span.end;
        if (delimiter == 0 or span.start < offset + delimiter or std.mem.indexOfNone(u8, words[span.start - delimiter .. span.start], "`") != null) return error.InvalidSpecificationUnit;
        try prose(a, w, words[offset .. span.start - delimiter], if (offset == 0) .block_start else .inline_text, normalizer);
        try markdown.code(w, words[span.start..span.end]);
        offset = span.end + delimiter;
    }
    try prose(a, w, words[offset..], if (offset == 0) .block_start else .inline_text, normalizer);
}

fn prose(a: std.mem.Allocator, w: *std.Io.Writer, bytes: []const u8, position: markdown.Position, normalizer: unicode.Normalizer) Error!void {
    if (bytes.len == 0) return;
    try markdown.literal(w, try naming.normalizeNfc(a, bytes, normalizer), position);
}
fn write(w: *std.Io.Writer, bytes: []const u8) Error!void {
    w.writeAll(bytes) catch return error.OutOfMemory;
}
