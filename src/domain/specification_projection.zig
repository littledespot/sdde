//! Typed business values to view and model-facing text. Provenance remains in the
//! canonical content, never in the business Markdown or a second text authority.
const std = @import("std");
const spec = @import("specification.zig");
const provenance = @import("specification_provenance.zig");
pub const Error = provenance.Error;
pub const Brief = struct { title: []const u8, description: []const u8, primary_goal: []const u8 };
pub const EntityDecision = struct { disposition: spec.Applicability, basis: []const u8 };

/// Read-only business context allocated in the caller's scratch arena;
/// canonical fragments and lineage stay native.
pub fn brief(allocator: std.mem.Allocator, context: provenance.Context, value: spec.Brief) Error!Brief {
    return .{
        .title = try businessText(allocator, context, value.title),
        .description = try businessText(allocator, context, value.description),
        .primary_goal = try businessText(allocator, context, value.primary_goal),
    };
}

/// Caller supplies the same scratch-arena ownership as brief/project.
pub fn entities(allocator: std.mem.Allocator, context: provenance.Context, value: spec.ApplicabilityProposal) Error!EntityDecision {
    return .{ .disposition = value.disposition, .basis = try businessText(allocator, context, value.basis) };
}

fn businessText(allocator: std.mem.Allocator, context: provenance.Context, value: spec.AttributedValue) Error![]const u8 {
    const projected = try scalar(allocator, context, value);
    allocator.free(projected.code_spans);
    return projected.bytes;
}
pub const RequirementTrace = struct {
    id: spec.Id,
    occurrences: []const @import("reference_support.zig").Occurrence,
};

/// Completed-state source view. Canonical admission and the same reference
/// ledger determine each record's effective lineage independently.
pub fn traceRequirements(allocator: std.mem.Allocator, snapshot: @import("reference_snapshot.zig").Snapshot, content: spec.IdentifiedContent) Error![]const RequirementTrace {
    const support = @import("reference_support.zig");
    const references = try support.snapshot(allocator, snapshot);
    const traces = try allocator.alloc(RequirementTrace, content.records.len);
    for (content.records, traces) |record, *trace| {
        const resolved = try provenance.storedRecordLineage(allocator, snapshot.inputs, references, record.proposal);
        trace.* = .{
            .id = record.id,
            .occurrences = support.occurrences(allocator, references.items, snapshot.inputs, resolved.effective_claim_ids) catch |err| switch (err) {
                error.InvalidReferenceState => return error.InvalidSpecification,
                else => |other| return other,
            },
        };
    }
    return traces;
}

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
