//! Request-scoped, lossless source-line selections. Models select supplied IDs;
//! captured evidence remains the sole owner of bytes and source coordinates.
const std = @import("std");
const evidence = @import("reference_evidence.zig");
const source = @import("reference_ingestion.zig");
pub const Id = struct {
    pub const model_scalar = "ordinal";
    ordinal: u32,
};
pub const Selection = struct { first: Id, last: Id };
pub const Choice = struct { id: Id, text: []const u8 };
pub const Issue = struct {
    reason: enum { missing_selection, unknown_selection, reversed_selection },
    index: usize,
    rejected: ?Selection,
    available: Selection,
};
pub const Result = union(enum) { valid: evidence.ValidatedCitations, invalid: Issue };

/// One supplied line: its ID, exact source span and bytes, line ending included.
pub const Line = struct { id: Id, span: source.Span, text: []const u8 };
const Iterator = struct {
    view: evidence.ChunkView,
    position: source.Position,
    ordinal: u32 = 0,

    fn next(self: *Iterator) evidence.Error!?Line {
        if (self.position.byte == self.view.chunk.span.end.byte) return null;
        const start = self.position;
        while (self.position.byte < self.view.chunk.span.end.byte) {
            self.position = source.advance(self.view.source.bytes, self.position) catch return error.InvalidSourceCitation;
            if (self.position.byte > self.view.chunk.span.end.byte) return error.InvalidSourceCitation;
            if (self.position.line != start.line) break;
        }
        self.ordinal = std.math.add(u32, self.ordinal, 1) catch return error.InvalidSourceCitation;
        return .{ .id = .{ .ordinal = self.ordinal }, .span = .{ .start = start, .end = self.position }, .text = self.view.source.bytes[start.byte..self.position.byte] };
    }
};

pub fn lines(a: std.mem.Allocator, inputs: evidence.Inputs, scope: evidence.Scope) evidence.Error![]const Line {
    const view = try evidence.resolve(inputs, scope);
    var iterator: Iterator = .{ .view = view, .position = view.chunk.span.start };
    var result: std.ArrayList(Line) = .empty;
    errdefer result.deinit(a);
    while (try iterator.next()) |line| try result.append(a, line);
    return result.toOwnedSlice(a);
}

pub fn project(a: std.mem.Allocator, inputs: evidence.Inputs, scope: evidence.Scope) evidence.Error![]const Choice {
    const supplied = try lines(a, inputs, scope);
    defer a.free(supplied);
    const choices = try a.alloc(Choice, supplied.len);
    for (supplied, choices) |line, *choice| choice.* = .{ .id = line.id, .text = line.text };
    return choices;
}

/// A model may cite a line only when it carries text (ADR 0036).
pub fn citable(text: []const u8) bool {
    return std.mem.trim(u8, text, " \t\r\n").len != 0;
}

pub fn validate(a: std.mem.Allocator, inputs: evidence.Inputs, scope: evidence.Scope, selections: []const Selection) evidence.Error!Result {
    const view = try evidence.resolve(inputs, scope);
    const units = try lines(a, inputs, scope);
    defer a.free(units);
    if (units.len == 0) return error.InvalidSourceCitation;
    const available: Selection = .{ .first = units[0].id, .last = units[units.len - 1].id };
    if (selections.len == 0) return .{ .invalid = .{ .reason = .missing_selection, .index = 0, .rejected = null, .available = available } };
    const proposals = try a.alloc(evidence.CitationProposal, selections.len);
    defer a.free(proposals);
    for (selections, proposals, 0..) |selection, *proposal, index| {
        const reason: ?@FieldType(Issue, "reason") = if (selection.first.ordinal == 0 or selection.last.ordinal == 0 or selection.first.ordinal > available.last.ordinal or selection.last.ordinal > available.last.ordinal)
            .unknown_selection
        else if (selection.first.ordinal > selection.last.ordinal)
            .reversed_selection
        else
            null;
        if (reason) |value| return .{ .invalid = .{ .reason = value, .index = index, .rejected = selection, .available = available } };
        const span: source.Span = .{ .start = units[selection.first.ordinal - 1].span.start, .end = units[selection.last.ordinal - 1].span.end };
        proposal.* = .{ .source_id = view.source.id, .block_id = view.chunk.block_id, .location = span, .verbatim = view.source.bytes[span.start.byte..span.end.byte] };
    }
    return .{ .valid = try @import("source_citations.zig").validate(a, inputs, .{ .scope = scope, .entries = proposals }) };
}
