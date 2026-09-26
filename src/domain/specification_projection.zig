//! Typed business values to editable-view scalars. Provenance remains in the
//! canonical content, never in the business Markdown or a second text authority.
const std = @import("std");
const spec = @import("specification.zig");
const provenance = @import("specification_provenance.zig");
pub const Error = provenance.Error;

pub fn scalar(allocator: std.mem.Allocator, context: provenance.Context, attributed: spec.AttributedValue) Error!spec.Scalar {
    return scalarInScopes(allocator, context, attributed.value, try provenance.scopesFor(allocator, context, attributed));
}

pub fn recordScalar(allocator: std.mem.Allocator, context: provenance.Context, record: spec.RecordProposal, value: spec.BusinessValue) Error!spec.Scalar {
    return scalarInScopes(allocator, context, value, try provenance.scopesForRecord(allocator, context, record));
}

fn scalarInScopes(allocator: std.mem.Allocator, context: provenance.Context, value: spec.BusinessValue, scopes: []const @import("reference_evidence.zig").Scope) Error!spec.Scalar {
    var bytes: std.ArrayList(u8) = .empty;
    var spans: std.ArrayList(spec.CodeSpan) = .empty;
    for (value.segments) |segment| switch (segment) {
        .literal => |literal| try bytes.appendSlice(allocator, literal.value),
        .passive => |passive| {
            const record = try @import("passive_literals.zig").resolveIn(context.registry, context.inputs, scopes, passive.passive_literal_id);
            const start = bytes.items.len;
            try bytes.appendSlice(allocator, record.value);
            try appendSpan(allocator, &spans, start, bytes.items.len);
        },
        .exact_copy => |selected| {
            const items = try provenance.items(context);
            const token = @import("reference_support.zig").exact(items, selected.claim_id) catch return error.InvalidSpecification;
            if (!provenance.permitsExactKind(token.value.kind)) return error.InvalidSpecification;
            const raw = token.value.raw_value.bytes;
            const start = bytes.items.len;
            try bytes.appendSlice(allocator, raw);
            try appendSpan(allocator, &spans, start, bytes.items.len);
        },
    };
    return .{ .bytes = try bytes.toOwnedSlice(allocator), .code_spans = try spans.toOwnedSlice(allocator) };
}

// Adjacent display atoms share a code span; canonical identity stays in the IR.
fn appendSpan(a: std.mem.Allocator, spans: *std.ArrayList(spec.CodeSpan), start: usize, end: usize) std.mem.Allocator.Error!void {
    if (spans.items.len != 0 and spans.items[spans.items.len - 1].end == start) {
        spans.items[spans.items.len - 1].end = end;
    } else try spans.append(a, .{ .start = start, .end = end });
}

/// Caller owns an arena; input canonical content and reference context outlive it.
pub fn project(allocator: std.mem.Allocator, context: provenance.Context, content: spec.IdentifiedContent) Error!spec.CapturedDocument {
    const records = try allocator.alloc(spec.CapturedRecord, content.records.len);
    for (content.records, records) |record, *captured| {
        captured.id = record.id;
        const scopes = try provenance.scopesForRecord(allocator, context, record.proposal);
        switch (record.proposal.content) {
            inline else => |fields, kind| {
                var projected: @FieldType(spec.Content(spec.Scalar), @tagName(kind)) = undefined;
                inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                    const value = @field(fields, field.name);
                    if (comptime field.type == spec.BusinessValue) {
                        @field(projected, field.name) = try scalarInScopes(allocator, context, value, scopes);
                    } else {
                        const relationships = try allocator.alloc(spec.Scalar, value.len);
                        for (value, relationships) |entry, *result| result.* = try scalarInScopes(allocator, context, entry, scopes);
                        @field(projected, field.name) = relationships;
                    }
                }
                captured.content = @unionInit(spec.Content(spec.Scalar), @tagName(kind), projected);
            },
        }
    }
    const document: spec.CapturedDocument = .{
        .display_name = try scalar(allocator, context, content.display_name),
        .primary_user_story = try scalar(allocator, context, content.primary_user_story),
        .records = records,
        .entity_section = if (content.entities.disposition == .required) .present else .omitted,
    };
    try spec.validateDocument(document, true);
    return document;
}
