//! Read-only Markdown projection. The persisted snapshot owns reference data;
//! this view is never parsed back into authority.
const std = @import("std");
const snapshot = @import("reference_snapshot.zig");
const r = @import("reference_reconciliation.zig");
const markdown = @import("specification_markdown.zig");
pub const Error = snapshot.Error || markdown.Error;

/// Whether the signal holds an `open_question` claim that an applied answer kept: the snapshot's `answer_retained`, which
/// readback checks, names claims that stand alone in a signal of their own.
fn answeredQuestion(value: snapshot.Snapshot, signal: r.Signal) bool {
    return signal.value.content == .model and signal.value.content.model == .open_question and signal.value.claim_ids.len == 1 and
        r.contains(r.ClaimId, value.answer_retained, signal.value.claim_ids[0]);
}

fn hasAnsweredQuestion(value: snapshot.Snapshot) bool {
    for (value.signals) |signal| if (answeredQuestion(value, signal)) return true;
    return false;
}

pub fn render(allocator: std.mem.Allocator, value: snapshot.Snapshot, traces: ?[]const @import("specification_projection.zig").RequirementTrace) Error![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const w = &out.writer;
    try write(w, "# Reference Context\n\nReference state: ");
    try markdown.code(w, value.inputs.corpus.state_id.bytes);
    try write(w, "\n\n## Referenced Files\n\n");
    for (value.inputs.corpus.sources) |source| {
        w.print("- **SRC-{d}** ", .{source.id.ordinal}) catch return error.OutOfMemory;
        const path = try @import("reference_ingestion.zig").displayPath(allocator, value.directory, source.path);
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
        .{ r.extraction.Kind.open_question, "Answered Questions" },
    }) |section| {
        const answered_section = comptime std.mem.eql(u8, section[1], "Answered Questions");
        // The section of answered questions appears only when an applied answer kept a question, so a run with no such answer
        // renders the view it always has.
        if (!answered_section or hasAnsweredQuestion(value)) try write(w, "\n## " ++ section[1] ++ "\n\n");
        for (value.signals) |signal| {
            if (signal.value.content != .model or signal.value.content.model != section[0]) continue;
            // A question an applied answer kept is listed apart from the questions still open (ADR 0025).
            if (comptime section[0] == .open_question) if (answeredQuestion(value, signal) != answered_section) continue;
            w.print("- **SIG-{d}** ", .{signal.id.ordinal}) catch return error.OutOfMemory;
            const content = @field(signal.value.content.model, @tagName(section[0])).value;
            if (comptime section[0] == .business or section[0] == .scope_guard) {
                try @import("reference_markdown.zig").business(w, value, content, .inline_text);
            } else try @import("reference_markdown.zig").semantic(w, value, content);
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
        if (token.value.kind == .code_sample) {
            try citations(w, &.{token.citation_id});
            try markdown.codeBlock(w, token.value.raw_value.bytes);
        } else {
            try markdown.code(w, token.value.raw_value.bytes);
            try citations(w, &.{token.citation_id});
        }
    }
    try write(w, "\n## Conflicts\n\n");
    for (value.conflicts) |conflict| {
        w.print("- **CON-{d}** ({s}, unresolved): ", .{ conflict.id.ordinal, @tagName(conflict.value.kind) }) catch return error.OutOfMemory;
        try @import("reference_markdown.zig").semantic(w, value, conflict.value.summary.value);
        try citations(w, conflict.value.citation_ids);
    }
    try write(w, "\n## Source Citations\n\n");
    for (value.extraction.citations) |citation| {
        const source = citation.value;
        w.print("- <a id=\"cit-{d}\"></a>**CIT-{d}** — SRC-{d}, block {d}, lines {d}:{d}–{d}:{d}", .{ citation.id.ordinal, citation.id.ordinal, source.source_id.ordinal, source.block_id.ordinal, source.location.start.line, source.location.start.column, source.location.end.line, source.location.end.column }) catch return error.OutOfMemory;
        if (source.verbatim) |bytes| {
            try write(w, ": ");
            try markdown.code(w, bytes);
        }
        try write(w, "\n");
    }
    if (traces) |entries| {
        try write(w, "\n## Generated Requirement Sources\n\n");
        for (entries) |trace| {
            w.print("- **{s}-{d:0>3}**:", .{ trace.id.kind.prefix(), trace.id.ordinal }) catch return error.OutOfMemory;
            for (trace.occurrences) |occurrence| {
                const citation = occurrence.citation;
                w.print(" [claim {d}, CIT-{d}](#cit-{d}) (SRC-{d}, block {d}, lines {d}:{d}–{d}:{d})", .{ occurrence.claim_id.ordinal, citation.id.ordinal, citation.id.ordinal, citation.value.source_id.ordinal, citation.value.block_id.ordinal, citation.value.location.start.line, citation.value.location.start.column, citation.value.location.end.line, citation.value.location.end.column }) catch return error.OutOfMemory;
            }
            try write(w, "\n");
        }
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
