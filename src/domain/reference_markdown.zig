//! Shared safe rendering of typed reference text and inert display literals.
const snapshot = @import("reference_snapshot.zig");
const std = @import("std");
const text = @import("typed_text.zig");
const markdown = @import("specification_markdown.zig");
pub const Error = snapshot.Error || markdown.Error;
fn passive(w: *std.Io.Writer, value: snapshot.Snapshot, id: @import("passive_literals.zig").Id) Error!void {
    if (id.ordinal == 0 or id.ordinal > value.passive_records.len) return error.InvalidReferenceSnapshot;
    const record = value.passive_records[id.ordinal - 1];
    if (record.id.ordinal != id.ordinal) return error.InvalidReferenceSnapshot;
    try markdown.code(w, record.value);
}
pub fn business(w: *std.Io.Writer, value: snapshot.Snapshot, content: text.BusinessText) Error!void {
    for (content.segments) |segment| switch (segment) {
        .exact_copy => return error.InvalidReferenceSnapshot,
        .literal => |literal| try markdown.literal(w, literal.value),
        .passive => |reference| try passive(w, value, reference.passive_literal_id),
    };
}
pub fn semantic(w: *std.Io.Writer, value: snapshot.Snapshot, content: text.ReferenceSemanticText) Error!void {
    for (content.nodes) |node| switch (node) {
        .literal => |literal| try markdown.literal(w, literal.value),
        .passive => |reference| try passive(w, value, reference.passive_literal_id),
        .source => |reference| {
            if (reference.source_id.ordinal == 0 or reference.source_id.ordinal > value.inputs.corpus.sources.len) return error.InvalidReferenceSnapshot;
            try markdown.code(w, value.inputs.corpus.sources[reference.source_id.ordinal - 1].path.bytes);
        },
    };
}
