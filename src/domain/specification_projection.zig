//! Typed business values to view and model-facing text. Provenance remains in the
//! canonical content, never in the business Markdown or a second text authority.
const std = @import("std");
const spec = @import("specification.zig");
const provenance = @import("specification_provenance.zig");
pub const Error = provenance.Error;
pub const Brief = struct { title: []const u8, description: []const u8, primary_goal: []const u8 };

/// Read-only business context allocated in the caller's scratch arena;
/// canonical fragments and lineage stay native.
pub fn brief(allocator: std.mem.Allocator, context: provenance.Context, value: spec.Brief) Error!Brief {
    return .{
        .title = try businessText(allocator, context, value.title),
        .description = try businessText(allocator, context, value.description),
        .primary_goal = try businessText(allocator, context, value.primary_goal),
    };
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

/// Completed-state source view, one per record. Canonical admission and the
/// reference ledger (live or snapshot records) determine each record's effective
/// lineage independently.
pub fn traceRequirements(allocator: std.mem.Allocator, inputs: @import("reference_evidence.zig").Inputs, references: @import("reference_support.zig").Records, content: spec.IdentifiedContent) Error![]const RequirementTrace {
    const support = @import("reference_support.zig");
    const traces = try allocator.alloc(RequirementTrace, content.records.len);
    for (content.records, traces) |record, *trace| {
        // Same mapping as `scopesForRecord`: canonical text that no longer resolves is
        // an invalid specification, not a typed-text admission result.
        const resolved = provenance.storedRecordLineage(allocator, inputs, references, record.proposal) catch |err| return if (err == error.InvalidTypedText) error.InvalidSpecification else err;
        trace.* = .{
            .id = record.id,
            .occurrences = support.occurrences(allocator, references.items, inputs, resolved.effective_claim_ids) catch |err| switch (err) {
                error.InvalidReferenceState => return error.InvalidSpecification,
                else => |other| return other,
            },
        };
    }
    return traces;
}

/// The completed snapshot's view of `traceRequirements`.
pub fn traceSnapshot(allocator: std.mem.Allocator, snapshot: @import("reference_snapshot.zig").Snapshot, content: spec.IdentifiedContent) Error![]const RequirementTrace {
    return traceRequirements(allocator, snapshot.inputs, try @import("reference_support.zig").snapshot(allocator, snapshot), content);
}

/// The record's cited lines per source file, in corpus order, each file's ranges
/// merged (`mergeLines`). The span owner turns each citation into its lines.
/// Caller owns an arena.
pub fn sourceLines(allocator: std.mem.Allocator, directory: @import("reference_ingestion.zig").RelativePath, inputs: @import("reference_evidence.zig").Inputs, occurrences: []const @import("reference_support.zig").Occurrence) Error![]const spec.SourceLines {
    var files: std.ArrayList(spec.SourceLines) = .empty;
    for (occurrences) |occurrence| {
        if (!for (inputs.corpus.sources) |source| {
            if (source.id.ordinal == occurrence.citation.value.source_id.ordinal) break true;
        } else false) return error.InvalidSpecification;
    }
    for (inputs.corpus.sources) |source| {
        var ranges: std.ArrayList(spec.LineRange) = .empty;
        for (occurrences) |occurrence| {
            const citation = occurrence.citation.value;
            if (citation.source_id.ordinal != source.id.ordinal) continue;
            const cited = @import("source_coordinates.zig").lines(citation.location) catch return error.InvalidSpecification;
            try ranges.append(allocator, .{ .first = cited.first, .last = cited.last });
        }
        if (ranges.items.len == 0) continue;
        try files.append(allocator, .{ .path = try @import("reference_ingestion.zig").displayPath(allocator, directory, source.path), .ranges = mergeLines(ranges.items) });
    }
    return files.toOwnedSlice(allocator);
}

/// An entity's related statements (§23): the requirement and behaviour records that share
/// one of its source groups, in document order. The entity selected those groups; the
/// engine reads no wording, and the display never becomes provenance. Caller owns an arena.
pub fn relatedStatements(allocator: std.mem.Allocator, records: []const spec.IdentifiedRecord, entity: spec.RecordProposal) std.mem.Allocator.Error![]const spec.Id {
    const reconciliation = @import("reference_reconciliation.zig");
    var ids: std.ArrayList(spec.Id) = .empty;
    for (records) |other| {
        if (!std.meta.activeTag(other.proposal.content).isStatement()) continue;
        for (other.proposal.source_group_ids) |group| {
            if (!reconciliation.contains(reconciliation.SignalId, entity.source_group_ids, group)) continue;
            try ids.append(allocator, other.id);
            break;
        }
    }
    return ids.toOwnedSlice(allocator);
}

/// An edge case's outcome (§23): the Then of the acceptance criterion it links to, as that
/// criterion's own display. Criteria precede edge cases in document order, so `done` holds it.
fn linkedOutcome(done: []const spec.CapturedRecord, link: ?spec.Id) Error!spec.Scalar {
    const id = link orelse return error.InvalidSpecification;
    for (done) |other| {
        const other_id = other.id orelse continue;
        if (!std.meta.eql(other_id, id)) continue;
        if (other.content != .acceptance_criterion) return error.InvalidSpecification;
        return other.content.acceptance_criterion.then;
    }
    return error.InvalidSpecification;
}

/// Sorts `ranges` in place and returns its prefix with overlapping or touching ranges
/// joined, so one set of cited lines has one display.
pub fn mergeLines(ranges: []spec.LineRange) []const spec.LineRange {
    if (ranges.len == 0) return ranges;
    std.mem.sort(spec.LineRange, ranges, {}, struct {
        fn less(_: void, left: spec.LineRange, right: spec.LineRange) bool {
            return left.first < right.first or (left.first == right.first and left.last < right.last);
        }
    }.less);
    var merged: usize = 0;
    for (ranges[1..]) |range| {
        const current = &ranges[merged];
        if (range.first <= current.last +| 1) {
            current.last = @max(current.last, range.last);
        } else {
            merged += 1;
            ranges[merged] = range;
        }
    }
    return ranges[0 .. merged + 1];
}

pub fn scalar(allocator: std.mem.Allocator, context: provenance.Context, attributed: spec.AttributedValue) Error!spec.Scalar {
    return scalarInScopes(allocator, context, attributed.value, try provenance.scopesFor(allocator, context, attributed));
}

pub fn recordScalar(allocator: std.mem.Allocator, context: provenance.Context, record: spec.RecordProposal, value: spec.BusinessValue) Error!spec.Scalar {
    return scalarInScopes(allocator, context, value, try provenance.scopesForRecord(allocator, context, record));
}

/// Render an unaccepted native candidate for diagnosis. Source selection and
/// insertion identity are resolved by their existing owner; this grants no
/// text admission or repaired-candidate authority.
pub fn modelValue(allocator: std.mem.Allocator, context: provenance.Context, value: spec.Model.AttributedValue) Error!spec.Scalar {
    const resolved = try provenance.lineageForRepair(allocator, context, value.provenance, &.{value.value});
    return scalarInScopes(allocator, context, value.value, resolved.scopes);
}

pub fn modelRecord(allocator: std.mem.Allocator, context: provenance.Context, record: spec.Model.RecordProposal) Error!spec.Content(spec.Scalar) {
    const resolved = try provenance.lineageForRepair(allocator, context, record.provenance, try provenance.recordValues(allocator, record.content));
    return switch (record.content) {
        inline else => |fields, kind| result: {
            var rendered: @FieldType(spec.Content(spec.Scalar), @tagName(kind)) = undefined;
            inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                @field(rendered, field.name) = try scalarInScopes(allocator, context, @field(fields, field.name), resolved.scopes);
            }
            break :result @unionInit(spec.Content(spec.Scalar), @tagName(kind), rendered);
        },
    };
}

const DisplayAtom = struct { start: usize, end: usize, kind: enum { passive, exact_copy } };

fn scalarInScopes(allocator: std.mem.Allocator, context: provenance.Context, value: spec.BusinessValue, scopes: []const @import("reference_evidence.zig").Scope) Error!spec.Scalar {
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(allocator);
    var atoms: std.ArrayList(DisplayAtom) = .empty;
    defer atoms.deinit(allocator);
    for (value.segments) |segment| switch (segment) {
        .literal => |literal| try bytes.appendSlice(allocator, literal.value),
        .passive => |passive| {
            const record = try @import("passive_literals.zig").resolveIn(context.registry, context.inputs, scopes, passive.passive_literal_id);
            const start = bytes.items.len;
            try bytes.appendSlice(allocator, record.value);
            try atoms.append(allocator, .{ .start = start, .end = bytes.items.len, .kind = .passive });
        },
        .exact_copy => |selected| {
            const items = try provenance.items(context);
            const token = @import("reference_support.zig").exact(items, selected.claim_id) catch return error.InvalidSpecification;
            if (!try @import("specification_exact_tokens.zig").permits(items, selected.claim_id)) return error.InvalidSpecification;
            const raw = token.value.raw_value.bytes;
            const start = bytes.items.len;
            try bytes.appendSlice(allocator, raw);
            try atoms.append(allocator, .{ .start = start, .end = bytes.items.len, .kind = .exact_copy });
        },
    };
    const prose = @import("exact_value_boundary.zig").Utf8Prose.parse(bytes.items) orelse return error.InvalidSpecification;
    var spans: std.ArrayList(spec.CodeSpan) = .empty;
    errdefer spans.deinit(allocator);
    for (atoms.items, 0..) |atom, index| {
        if (atom.kind == .exact_copy and delimitedByText(prose, atoms.items, index)) continue;
        try appendSpan(allocator, &spans, atom.start, atom.end);
    }
    const owned = try bytes.toOwnedSlice(allocator);
    errdefer allocator.free(owned);
    return .{ .bytes = owned, .code_spans = try spans.toOwnedSlice(allocator) };
}

/// §23: the engine's code span is a delimiter, so an exact copy that the field's literal
/// text already wraps in one balanced pair from the shared closed table gets none. A
/// display atom touching the copy never supplies the pair, even when its bytes begin
/// with the closer. A copy ending in terminal punctuation keeps its span: inside the
/// pair, that punctuation reads as the prose's own. Passive values keep their span.
fn delimitedByText(prose: @import("exact_value_boundary.zig").Utf8Prose, atoms: []const DisplayAtom, index: usize) bool {
    const atom = atoms[index];
    if (index != 0 and atoms[index - 1].end == atom.start) return false;
    if (index + 1 != atoms.len and atoms[index + 1].start == atom.end) return false;
    if (@import("exact_value_boundary.zig").endsWithTerminal(prose.bytes[atom.start..atom.end])) return false;
    return prose.directlyWrapped(atom.start, atom.end, .{ .left = .field_edge, .right = .field_edge });
}

// Adjacent display atoms share a code span; canonical identity stays in the IR.
fn appendSpan(a: std.mem.Allocator, spans: *std.ArrayList(spec.CodeSpan), start: usize, end: usize) std.mem.Allocator.Error!void {
    if (spans.items.len != 0 and spans.items[spans.items.len - 1].end == start) {
        spans.items[spans.items.len - 1].end = end;
    } else try spans.append(a, .{ .start = start, .end = end });
}

/// Caller owns an arena; input canonical content and reference context outlive it.
/// `directory` is the selected reference directory the source paths are shown in.
pub fn project(allocator: std.mem.Allocator, context: provenance.Context, directory: @import("reference_ingestion.zig").RelativePath, content: spec.IdentifiedContent) Error!spec.CapturedDocument {
    const records = try allocator.alloc(spec.CapturedRecord, content.records.len);
    const traces = try traceRequirements(allocator, context.inputs, @import("reference_support.zig").records(context.references), content);
    for (content.records, records, traces, 0..) |record, *captured, trace, index| {
        captured.id = record.id;
        const family: spec.Kind = record.proposal.content;
        captured.sources = if (family.showsSources()) try sourceLines(allocator, directory, context.inputs, trace.occurrences) else &.{};
        captured.related = if (family == .entity) try relatedStatements(allocator, content.records, record.proposal) else &.{};
        captured.outcome = if (family.showsOutcome()) try linkedOutcome(records[0..index], record.outcome_of) else null;
        const scopes = try provenance.scopesForRecord(allocator, context, record.proposal);
        switch (record.proposal.content) {
            inline else => |fields, kind| {
                var projected: @FieldType(spec.Content(spec.Scalar), @tagName(kind)) = undefined;
                inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                    @field(projected, field.name) = try scalarInScopes(allocator, context, @field(fields, field.name), scopes);
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
