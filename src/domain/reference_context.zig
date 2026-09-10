//! Read-only Markdown projection. The persisted snapshot owns reference data;
//! this view is never parsed back into authority.
const std = @import("std");
const snapshot = @import("reference_snapshot.zig");
const r = @import("reference_reconciliation.zig");
const text = @import("typed_text.zig");
const markdown = @import("specification_markdown.zig");
pub const Error = snapshot.Error || markdown.Error;

pub fn render(allocator: std.mem.Allocator, value: snapshot.Snapshot) Error![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const w = &out.writer;
    try write(w, "# Reference Context\n\nReference state: ");
    try markdown.code(w, value.inputs.corpus.state_id.bytes);
    try write(w, "\n\n## Referenced Files\n\n");
    for (value.inputs.corpus.sources) |source| {
        w.print("- **SRC-{d}** ", .{source.id.ordinal}) catch return error.OutOfMemory;
        const path = try std.mem.concat(allocator, u8, &.{ value.directory.bytes, "/", source.path.bytes });
        defer allocator.free(path);
        try markdown.code(w, path);
        try write(w, "\n");
    }
    inline for (.{
        .{ r.extraction.Kind.business, "Business Signals" },
        .{ r.extraction.Kind.design, "Design and Interaction Signals" },
        .{ r.extraction.Kind.scope_guard, "Terminal and Scope Guards" },
        .{ r.extraction.Kind.technical, "Technical Observations" },
        .{ r.extraction.Kind.validation, "Validation Signals" },
        .{ r.extraction.Kind.implementation_assumption, "Implementation Assumptions" },
        .{ r.extraction.Kind.open_question, "Open Questions" },
    }) |section| {
        try write(w, "\n## " ++ section[1] ++ "\n\n");
        for (value.signals) |signal| {
            if (signal.value.content != .model or signal.value.content.model != section[0]) continue;
            w.print("- **SIG-{d}** ", .{signal.id.ordinal}) catch return error.OutOfMemory;
            const content = @field(signal.value.content.model, @tagName(section[0])).value;
            if (comptime section[0] == .business or section[0] == .scope_guard) {
                try business(w, value, content);
            } else try semantic(w, value, content);
            try citations(w, signal.value.citation_ids);
        }
    }
    try write(w, "\n## Preserved Tokens\n\n");
    // Every exact token remains in the view, including tokens with no model
    // signal. Classification never delegates scalar reproduction to a model.
    for (value.extraction.claims) |claim| {
        if (claim.content != .preserved_token) continue;
        const token = claim.content.preserved_token;
        w.print("- **TOK-{d}** ({s}): ", .{ token.value.id.ordinal, @tagName(token.value.kind) }) catch return error.OutOfMemory;
        try markdown.code(w, token.value.raw_value.bytes);
        try citations(w, &.{token.citation_id});
    }
    try write(w, "\n## Conflicts\n\n");
    for (value.conflicts) |conflict| {
        w.print("- **CON-{d}** ({s}, unresolved): ", .{ conflict.id.ordinal, @tagName(conflict.value.kind) }) catch return error.OutOfMemory;
        try semantic(w, value, conflict.value.summary.value);
        try citations(w, conflict.value.citation_ids);
    }
    try write(w, "\n## Source Citations\n\n");
    for (value.extraction.citations) |citation| {
        const source = citation.value;
        w.print("- **CIT-{d}** — SRC-{d}, block {d}, lines {d}:{d}–{d}:{d}", .{ citation.id.ordinal, source.source_id.ordinal, source.block_id.ordinal, source.location.start.line, source.location.start.column, source.location.end.line, source.location.end.column }) catch return error.OutOfMemory;
        if (source.verbatim) |bytes| {
            try write(w, ": ");
            try markdown.code(w, bytes);
        }
        try write(w, "\n");
    }
    return out.toOwnedSlice();
}

fn write(w: *std.Io.Writer, bytes: []const u8) Error!void {
    w.writeAll(bytes) catch return error.OutOfMemory;
}
fn citations(w: *std.Io.Writer, ids: []const r.CitationId) Error!void {
    try write(w, " (citations:");
    for (ids) |id| w.print(" CIT-{d}", .{id.ordinal}) catch return error.OutOfMemory;
    try write(w, ")\n");
}
fn passive(w: *std.Io.Writer, value: snapshot.Snapshot, id: @import("passive_literals.zig").Id) Error!void {
    if (id.ordinal == 0 or id.ordinal > value.passive_records.len) return error.InvalidReferenceSnapshot;
    const record = value.passive_records[id.ordinal - 1];
    if (record.id.ordinal != id.ordinal) return error.InvalidReferenceSnapshot;
    try markdown.code(w, record.value);
}
fn business(w: *std.Io.Writer, value: snapshot.Snapshot, content: text.BusinessText) Error!void {
    for (content.segments) |segment| switch (segment) {
        .literal => |literal| try markdown.literal(w, literal.value),
        .passive => |reference| try passive(w, value, reference.passive_literal_id),
    };
}
fn semantic(w: *std.Io.Writer, value: snapshot.Snapshot, content: text.ReferenceSemanticText) Error!void {
    for (content.nodes) |node| switch (node) {
        .literal => |literal| try markdown.literal(w, literal.value),
        .passive => |reference| try passive(w, value, reference.passive_literal_id),
        .source => |reference| {
            if (reference.source_id.ordinal == 0 or reference.source_id.ordinal > value.inputs.corpus.sources.len) return error.InvalidReferenceSnapshot;
            try markdown.code(w, value.inputs.corpus.sources[reference.source_id.ordinal - 1].path.bytes);
        },
    };
}
