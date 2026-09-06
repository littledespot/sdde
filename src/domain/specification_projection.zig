//! Typed business values to editable-view scalars. Provenance remains in the
//! canonical content, never in the business Markdown or a second text authority.
const std = @import("std");
const spec = @import("specification.zig");
const provenance = @import("specification_provenance.zig");
pub const Error = provenance.Error;

pub fn scalar(allocator: std.mem.Allocator, context: provenance.Context, attributed: spec.AttributedValue) Error!spec.Scalar {
    const scopes = try provenance.scopes(allocator, context, attributed.provenance);
    switch (attributed.value) {
        .exact_copy => |selected| {
            const items = try provenance.items(context);
            for (attributed.provenance.claim_ids) |id| {
                const claim = (try @import("reference_reconciliation.zig").item(items, id)).claim;
                if (claim.content != .preserved_token) continue;
                const token = claim.content.preserved_token;
                if (token.value.id.ordinal == selected.token_id.ordinal and token.citation_id.ordinal == selected.citation_id.ordinal)
                    return .{ .bytes = token.value.raw_value.bytes };
            }
            return error.InvalidSpecification;
        },
        .normalized => |value| {
            var bytes: std.ArrayList(u8) = .empty;
            var spans: std.ArrayList(spec.CodeSpan) = .empty;
            for (value.segments) |segment| switch (segment) {
                .literal => |literal| try bytes.appendSlice(allocator, literal.value),
                .passive => |passive| {
                    const record = try @import("passive_literals.zig").resolveIn(context.registry, context.inputs, scopes, passive.passive_literal_id);
                    const start = bytes.items.len;
                    try bytes.appendSlice(allocator, record.value);
                    try spans.append(allocator, .{ .start = start, .end = bytes.items.len });
                },
            };
            return .{ .bytes = try bytes.toOwnedSlice(allocator), .code_spans = try spans.toOwnedSlice(allocator) };
        },
    }
}

/// Caller owns an arena; input canonical content and reference context outlive it.
pub fn project(allocator: std.mem.Allocator, context: provenance.Context, content: spec.IdentifiedContent) Error!spec.CapturedDocument {
    const records = try allocator.alloc(spec.CapturedRecord, content.records.len);
    for (content.records, records) |record, *captured| {
        captured.id = record.id;
        switch (record.proposal.content) {
            inline else => |fields, kind| {
                var projected: @FieldType(spec.Content(spec.Scalar), @tagName(kind)) = undefined;
                inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                    const value = @field(fields, field.name);
                    if (comptime field.type == spec.BusinessValue) {
                        @field(projected, field.name) = try scalar(allocator, context, .{ .value = value, .provenance = record.proposal.provenance });
                    } else {
                        const relationships = try allocator.alloc(spec.Scalar, value.len);
                        for (value, relationships) |entry, *result| result.* = try scalar(allocator, context, .{ .value = entry, .provenance = record.proposal.provenance });
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
