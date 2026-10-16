//! Mechanical support joins only. A real citation is not semantic entailment.
const std = @import("std");
const spec = @import("specification.zig");
const r = @import("reference_reconciliation.zig");
const evidence = @import("reference_evidence.zig");
const text = @import("typed_text.zig");
const refs = @import("reference_support.zig");
const recognition = @import("exact_value_recognition.zig");
pub const Error = r.Error || spec.Error;
pub const Context = struct {
    inputs: evidence.Inputs,
    references: r.Accounted,
    registry: @import("passive_literals.zig").Registry,
    current: *const @import("toolchain_safety.zig").ValidToolchain,
};

/// Shared native evidence read set for generation and deterministic coverage.
pub const Dependencies = struct {
    text: text.Dependencies,
    lineage: @import("reference_reconciliation_context.zig").Lineage,
    dispositions: []const r.ClaimDisposition,
    signals: []const r.Signal,
    conflicts: []const r.Conflict,
    outcome: @FieldType(r.Accounted, "outcome"),
};
pub fn dependencies(a: std.mem.Allocator, context: Context) Error!Dependencies {
    const prior = context.references.records.assignments.checked.prior.prior;
    return .{ .text = try text.dependencies(context.inputs, context.registry, context.current), .lineage = try @import("reference_reconciliation_context.zig").lineage(a, prior.input.progress), .dispositions = prior.dispositions, .signals = context.references.records.signals, .conflicts = context.references.records.conflicts, .outcome = context.references.outcome };
}

pub fn items(context: Context) Error!r.Items {
    const result = context.references.records.assignments.checked.prior.prior.input.progress.plan.layout.items;
    if (!result.state_id.eql(context.inputs.corpus.state_id)) return error.InvalidSpecification;
    return result;
}

/// Authoring needs retained reference evidence. Positive support and question
/// eligibility remain separate checks, not a judgment of every field's meaning.
pub fn generationReady(references: r.Accounted) bool {
    if (references.outcome != .complete) return false;
    for (references.records.assignments.checked.prior.prior.dispositions) |disposition| {
        if (refs.eligibleClaim(disposition.disposition)) return true;
    }
    return false;
}

/// Check trusted evidence and text authority before classifying candidate errors.
pub fn bind(allocator: std.mem.Allocator, validator: text.Validator, context: Context) Error!void {
    const all = try items(context);
    if (context.references.outcome != .complete) return error.InvalidSpecification;
    const reconciliation = @import("reference_reconciliation_validation.zig");
    try reconciliation.history(allocator, context.references.records.assignments.checked.prior.prior.input.progress);
    try reconciliation.bind(allocator, all, .{ .inputs = context.inputs, .registry = context.registry, .current = context.current }, validator);
}

/// Initial reference-grounded generation. Applicable user-response support is
/// supplied by the clarification lifecycle, not inferred from loaded form IDs.
pub const Resolved = struct { provenance: spec.Provenance, effective_claim_ids: []const r.ClaimId, scopes: []const evidence.Scope };

fn resolve(comptime boundary: spec.Boundary, allocator: std.mem.Allocator, context: Context, provenance: spec.Values(boundary).Evidence) Error!Resolved {
    return resolveRecords(boundary, allocator, context.inputs, @import("reference_support.zig").records(context.references), provenance);
}

pub fn resolveRecords(comptime boundary: spec.Boundary, allocator: std.mem.Allocator, inputs: evidence.Inputs, references: @import("reference_support.zig").Records, provenance: spec.Values(boundary).Evidence) Error!Resolved {
    return resolveUnitRecords(boundary, allocator, inputs, references, provenance, &.{});
}
pub fn lineageForRepair(allocator: std.mem.Allocator, context: Context, selection: spec.Selection, values: []const spec.BusinessValue) Error!Resolved {
    return resolveUnitRecords(.model, allocator, context.inputs, @import("reference_support.zig").records(context.references), selection, values);
}
pub fn checkValueInUnit(allocator: std.mem.Allocator, validator: text.Validator, context: Context, selection: spec.Selection, values: []const spec.BusinessValue, value: spec.BusinessValue, field: text.field_policy.Field) Error!spec.BusinessValue {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const resolved = try lineageForRepair(allocator, context, selection, values);
    var inspection: Inspection = .{};
    const recognized = try recognizeValue(arena.allocator(), refs.records(context.references), value, field, resolved.effective_claim_ids);
    return valueIn(allocator, validator, context, resolved, recognized, field, &inspection);
}

fn dispositionFor(references: @import("reference_support.zig").Records, id: r.ClaimId) ?r.Disposition {
    for (references.dispositions) |entry| if (entry.claim_id.ordinal == id.ordinal) return entry.disposition;
    return null;
}

/// The owning field/record supplies its declared values. Invalid model handles
/// remain candidate defects and cannot contribute authority to the lineage.
fn resolveUnitRecords(comptime boundary: spec.Boundary, allocator: std.mem.Allocator, inputs: evidence.Inputs, references: @import("reference_support.zig").Records, provenance: spec.Values(boundary).Evidence, values: []const spec.BusinessValue) Error!Resolved {
    const claims = references.items;
    if (provenance.clarification_response_ids.len != 0) return error.InvalidSpecification;
    if (boundary == .canonical) try r.unique(r.CitationId, provenance.citation_ids);
    var exact: std.ArrayList(r.ClaimId) = .empty;
    defer exact.deinit(allocator);
    for (values) |value| for (value.segments) |segment| {
        if (segment != .exact_copy) continue;
        const id = segment.exact_copy.claim_id;
        const token = @import("reference_support.zig").exact(claims, id) catch {
            if (boundary == .canonical) return error.InvalidTypedText;
            continue;
        };
        if (!permitsExactKind(token.value.kind) or !refs.eligibleClaim(dispositionFor(references, id))) {
            if (boundary == .canonical) return error.InvalidTypedText;
            continue;
        }
        try exact.append(allocator, id);
    };
    const effective = try @import("reference_support.zig").lineage(allocator, provenance.claim_ids, exact.items);
    if (effective.len == 0) return error.InvalidSpecification;
    const selected = @import("reference_support.zig").select(allocator, claims, inputs, effective) catch |err| switch (err) {
        error.InvalidReferenceState => return error.InvalidSpecification,
        else => |other| return other,
    };
    if (provenance.claim_ids.len != 0 and !(refs.eligibleSelection(references.dispositions, provenance.claim_ids) catch return error.InvalidSpecification)) return error.InvalidSpecification;
    // Stable unique union in selected-claim order, not an arbitrary superset.
    const citations = selected.citation_ids;
    if (boundary == .canonical) {
        if (citations.len != provenance.citation_ids.len) return error.InvalidSpecification;
        for (citations, provenance.citation_ids) |expected, actual| if (expected.ordinal != actual.ordinal) return error.InvalidSpecification;
    }
    return .{ .provenance = .{ .claim_ids = provenance.claim_ids, .citation_ids = citations, .clarification_response_ids = provenance.clarification_response_ids }, .effective_claim_ids = selected.claim_ids, .scopes = selected.scopes };
}

pub fn scopes(allocator: std.mem.Allocator, context: Context, provenance: spec.Provenance) Error![]const evidence.Scope {
    return (try resolve(.canonical, allocator, context, provenance)).scopes;
}
pub fn scopesFor(allocator: std.mem.Allocator, context: Context, attributed: spec.AttributedValue) Error![]const evidence.Scope {
    const resolved = resolveUnitRecords(.canonical, allocator, context.inputs, @import("reference_support.zig").records(context.references), attributed.provenance, &.{attributed.value}) catch |err| return if (err == error.InvalidTypedText) error.InvalidSpecification else err;
    return resolved.scopes;
}
pub fn scopesForRecord(allocator: std.mem.Allocator, context: Context, record: spec.RecordProposal) Error![]const evidence.Scope {
    const resolved = resolveUnitRecords(.canonical, allocator, context.inputs, @import("reference_support.zig").records(context.references), record.provenance, try recordValues(allocator, record.content)) catch |err| return if (err == error.InvalidTypedText) error.InvalidSpecification else err;
    return resolved.scopes;
}
pub fn storedRecordLineage(allocator: std.mem.Allocator, inputs: evidence.Inputs, references: @import("reference_support.zig").Records, record: spec.RecordProposal) Error!Resolved {
    return resolveUnitRecords(.canonical, allocator, inputs, references, record.provenance, try recordValues(allocator, record.content));
}

/// Construct complete provenance from meaningful, currently eligible selections.
pub fn select(allocator: std.mem.Allocator, context: Context, selection: spec.Selection) Error!spec.Provenance {
    return (try resolve(.model, allocator, context, selection)).provenance;
}

pub fn effectiveClaims(a: std.mem.Allocator, selected: []const r.ClaimId, values: []const spec.BusinessValue) Error![]const r.ClaimId {
    var exact: std.ArrayList(r.ClaimId) = .empty;
    defer exact.deinit(a);
    for (values) |value| for (value.segments) |segment| {
        if (segment == .exact_copy) try exact.append(a, segment.exact_copy.claim_id);
    };
    return @import("reference_support.zig").lineage(a, selected, exact.items);
}

pub fn recordValues(a: std.mem.Allocator, content: spec.Content(spec.BusinessValue)) Error![]const spec.BusinessValue {
    var values: std.ArrayList(spec.BusinessValue) = .empty;
    switch (content) {
        inline else => |fields| inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
            const value = @field(fields, field.name);
            if (comptime field.type == spec.BusinessValue) {
                try values.append(a, value);
            } else for (value) |relationship| try values.append(a, relationship);
        },
    }
    return values.toOwnedSlice(a);
}

pub const ValueChoices = struct {
    exact_copy: []const text.ExactCopy,
    passive: []const @import("passive_literals.zig").Id = &.{},

    pub fn permits(self: ValueChoices, selected: text.ExactCopy) bool {
        return text.permitsExact(self.exact_copy, selected);
    }

    pub fn correction(self: ValueChoices, a: std.mem.Allocator, issue: text.Issue) std.mem.Allocator.Error![]const u8 {
        const rejected = switch (issue.reason) {
            .unknown_passive => if (issue.rejected_passive) |id|
                try std.fmt.allocPrint(a, "passive reference ID {d}", .{id.ordinal})
            else
                return issue.description(),
            .unknown_exact => if (issue.rejected_exact) |handle|
                try std.fmt.allocPrint(a, "exact-copy claim {d}", .{handle.claim_id.ordinal})
            else
                return issue.description(),
            else => return issue.description(),
        };
        defer a.free(rejected);
        const permitted = if (self.passive.len == 0)
            (if (self.exact_copy.len == 0)
                "Return source-backed prose without reference handles."
            else
                "Write source-backed prose and preserve any required exact value with its original bytes. Do not supply exact-copy handles.")
        else if (self.exact_copy.len == 0)
            "Write source-backed prose or use a listed passive reference ID. Do not supply exact-copy handles."
        else
            "Write source-backed prose, preserving exact values verbatim; only listed passive reference IDs may be selected.";
        return std.fmt.allocPrint(a, "Validation failed: {s} is unavailable for this field's authorized evidence. {s} Preserve the fixed evidence and source meaning.", .{ rejected, permitted });
    }
};

/// Code examples remain reference context under the business-specification contract.
pub fn permitsExactKind(kind: r.extraction.tokens.Kind) bool {
    return kind != .code_sample;
}

/// The native current occurrence scope owns eligibility. A lexical match may
/// contribute E, but never changes the authored groups or their explicit S.
/// Atomic value repairs supply their fixed previous S+E as the optional bound.
pub fn exactOccurrences(a: std.mem.Allocator, references: refs.Records, fixed: ?[]const r.ClaimId) Error![]const recognition.Occurrence {
    var result: std.ArrayList(recognition.Occurrence) = .empty;
    errdefer result.deinit(a);
    for (references.dispositions) |disposition| {
        if (!refs.eligibleClaim(disposition.disposition)) continue;
        if (fixed) |ids| if (!r.contains(r.ClaimId, ids, disposition.claim_id)) continue;
        const item = try r.item(references.items, disposition.claim_id);
        if (item.claim.content != .preserved_token) continue;
        const token = item.claim.content.preserved_token;
        if (!permitsExactKind(token.value.kind)) continue;
        try result.append(a, .{ .claim_id = item.claim.id, .bytes = token.value.raw_value.bytes });
    }
    return result.toOwnedSlice(a);
}

/// Recognize raw, adjacent prose before normalization. Canonical exact segments
/// are flattened with the same captured bytes and recognized again; their old
/// handle never disambiguates an otherwise ambiguous current occurrence scope.
/// Passive display references remain distinct typed boundaries.
pub fn recognizeValue(a: std.mem.Allocator, references: refs.Records, value: spec.BusinessValue, field: text.field_policy.Field, fixed: ?[]const r.ClaimId) Error!spec.BusinessValue {
    return recognizeValueDetailed(a, references, value, field, fixed) catch |err| switch (err) {
        error.AmbiguousExactValue => error.InvalidTypedText,
        else => |failure| failure,
    };
}

fn recognizeValueDetailed(a: std.mem.Allocator, references: refs.Records, value: spec.BusinessValue, field: text.field_policy.Field, fixed: ?[]const r.ClaimId) (Error || error{AmbiguousExactValue})!spec.BusinessValue {
    if (text.field_policy.get(field).exact_copy == .prohibited) return value;
    const occurrences = try exactOccurrences(a, references, fixed);
    defer a.free(occurrences);
    var segments: std.ArrayList(text.BusinessSegment) = .empty;
    errdefer {
        for (segments.items) |segment| if (segment == .literal) a.free(segment.literal.value);
        segments.deinit(a);
    }
    var run: std.ArrayList(u8) = .empty;
    defer run.deinit(a);
    var index: usize = 0;
    while (index < value.segments.len) {
        if (value.segments[index] == .passive) {
            try segments.append(a, value.segments[index]);
            index += 1;
            continue;
        }
        run.clearRetainingCapacity();
        const run_start = index;
        while (index < value.segments.len and value.segments[index] != .passive) : (index += 1) switch (value.segments[index]) {
            .literal => |literal| try run.appendSlice(a, literal.value),
            .exact_copy => |copy| {
                for (occurrences) |occurrence| {
                    if (occurrence.claim_id.ordinal == copy.claim_id.ordinal) break;
                } else return error.InvalidTypedText;
                const token = refs.exact(references.items, copy.claim_id) catch return error.InvalidTypedText;
                try run.appendSlice(a, token.value.raw_value.bytes);
            },
            .passive => unreachable,
        };
        // Invalid prose remains a candidate for the canonical text validator;
        // it creates no new occurrence or lineage during recognition. This also
        // preserves the original failed value for bounded repair comparison.
        if (!text.validScalar(run.items)) {
            for (value.segments[run_start..index]) |segment| switch (segment) {
                .literal => |literal| try appendLiteral(a, &segments, literal.value),
                .exact_copy, .passive => try segments.append(a, segment),
            };
            continue;
        }
        var found = try recognition.recognize(a, run.items, occurrences, .{ .left = if (run_start == 0) .field_edge else .reference_boundary, .right = if (index == value.segments.len) .field_edge else .reference_boundary });
        defer found.deinit(a);
        switch (found) {
            .rejected => return error.InvalidTypedText,
            .ambiguous => return error.AmbiguousExactValue,
            .no_match => if (run.items.len != 0) try appendLiteral(a, &segments, run.items),
            .matched => |witnesses| {
                var cursor: usize = 0;
                for (witnesses) |witness| {
                    if (witness.start_byte > cursor) try appendLiteral(a, &segments, run.items[cursor..witness.start_byte]);
                    try segments.append(a, .{ .exact_copy = .{ .claim_id = witness.claim_id } });
                    cursor = witness.end_byte;
                }
                if (cursor < run.items.len) try appendLiteral(a, &segments, run.items[cursor..]);
            },
        }
    }
    return .{ .segments = try segments.toOwnedSlice(a) };
}

fn appendLiteral(a: std.mem.Allocator, segments: *std.ArrayList(text.BusinessSegment), bytes: []const u8) std.mem.Allocator.Error!void {
    const copy = try a.dupe(u8, bytes);
    errdefer a.free(copy);
    try segments.append(a, .{ .literal = .{ .value = copy } });
}

pub fn recognizeRecord(a: std.mem.Allocator, references: refs.Records, content: spec.Content(spec.BusinessValue), fixed: ?[]const r.ClaimId) Error!spec.Content(spec.BusinessValue) {
    return switch (content) {
        inline else => |fields, kind| result: {
            var result = fields;
            inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                const value = @field(fields, field.name);
                if (comptime field.type == spec.BusinessValue) {
                    @field(result, field.name) = try recognizeValue(a, references, value, spec.textField(kind, field.name), fixed);
                } else {
                    const relationships = try a.alloc(spec.BusinessValue, value.len);
                    for (value, relationships) |entry, *recognized| recognized.* = try recognizeValue(a, references, entry, spec.textField(kind, field.name), fixed);
                    @field(result, field.name) = relationships;
                }
            }
            break :result @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), result);
        },
    };
}

/// Model-facing projections contain literal exact bytes, never canonical
/// engine-derived occurrence handles. Passive references retain their own wire
/// contract and cannot be mistaken for authored exact-value prose.
pub fn modelValue(a: std.mem.Allocator, references: refs.Records, value: spec.BusinessValue) Error!spec.BusinessValue {
    var result: std.ArrayList(text.BusinessSegment) = .empty;
    errdefer {
        for (result.items) |segment| if (segment == .literal) a.free(segment.literal.value);
        result.deinit(a);
    }
    var literal: std.ArrayList(u8) = .empty;
    defer literal.deinit(a);
    for (value.segments) |segment| switch (segment) {
        .literal => |node| try literal.appendSlice(a, node.value),
        .exact_copy => |node| {
            const token = refs.exact(references.items, node.claim_id) catch return error.InvalidTypedText;
            try literal.appendSlice(a, token.value.raw_value.bytes);
        },
        .passive => {
            if (literal.items.len != 0) {
                try appendLiteral(a, &result, literal.items);
                literal.clearRetainingCapacity();
            }
            try result.append(a, segment);
        },
    };
    if (literal.items.len != 0) try appendLiteral(a, &result, literal.items);
    return .{ .segments = try result.toOwnedSlice(a) };
}

pub fn modelRecord(a: std.mem.Allocator, references: refs.Records, content: spec.Content(spec.BusinessValue)) Error!spec.Content(spec.BusinessValue) {
    return switch (content) {
        inline else => |fields, kind| result: {
            var projected = fields;
            inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                const value = @field(fields, field.name);
                if (comptime field.type == spec.BusinessValue) {
                    @field(projected, field.name) = try modelValue(a, references, value);
                } else {
                    const relationships = try a.alloc(spec.BusinessValue, value.len);
                    for (value, relationships) |entry, *next| next.* = try modelValue(a, references, entry);
                    @field(projected, field.name) = relationships;
                }
            }
            break :result @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), projected);
        },
    };
}

pub fn modelAttributed(comptime boundary: spec.Boundary, a: std.mem.Allocator, references: refs.Records, value: spec.Values(boundary).AttributedValue) Error!spec.Values(boundary).AttributedValue {
    var projected = value;
    projected.value = try modelValue(a, references, value.value);
    return projected;
}

pub fn modelContent(a: std.mem.Allocator, references: refs.Records, content: spec.IdentifiedContent) Error!spec.IdentifiedContent {
    var projected = content;
    projected.display_name = try modelAttributed(.canonical, a, references, content.display_name);
    projected.primary_user_story = try modelAttributed(.canonical, a, references, content.primary_user_story);
    projected.entities.basis = try modelAttributed(.canonical, a, references, content.entities.basis);
    const records = try a.dupe(spec.IdentifiedRecord, content.records);
    for (records) |*record| record.proposal.content = try modelRecord(a, references, record.proposal.content);
    projected.records = records;
    return projected;
}

fn sameValue(a: std.mem.Allocator, left: spec.BusinessValue, right: spec.BusinessValue) std.mem.Allocator.Error!bool {
    const l = try std.json.Stringify.valueAlloc(a, left, .{});
    defer a.free(l);
    const right_bytes = try std.json.Stringify.valueAlloc(a, right, .{});
    defer a.free(right_bytes);
    return std.mem.eql(u8, l, right_bytes);
}

fn recognizeInspected(comptime boundary: spec.Boundary, a: std.mem.Allocator, references: refs.Records, value: spec.BusinessValue, field: text.field_policy.Field, inspection: *Inspection) Error!spec.BusinessValue {
    const recognized = recognizeValueDetailed(a, references, value, field, null) catch |err| switch (err) {
        error.AmbiguousExactValue => {
            inspection.text_issue = .{ .reason = .ambiguous_exact, .first_node = 0, .last_node = if (value.segments.len == 0) 0 else value.segments.len - 1, .field = field };
            return error.InvalidTypedText;
        },
        error.InvalidTypedText => {
            inspection.text_issue = .{ .reason = .unknown_exact, .first_node = 0, .last_node = if (value.segments.len == 0) 0 else value.segments.len - 1, .field = field };
            for (value.segments, 0..) |segment, index| if (segment == .exact_copy) {
                _ = refs.exact(references.items, segment.exact_copy.claim_id) catch {
                    inspection.text_issue.?.first_node = index;
                    inspection.text_issue.?.last_node = index;
                    inspection.text_issue.?.rejected_exact = segment.exact_copy;
                    break;
                };
            };
            return error.InvalidTypedText;
        },
        else => |failure| return failure,
    };
    if (boundary == .canonical and !try sameValue(a, value, recognized)) {
        inspection.text_issue = .{ .reason = .unknown_exact, .first_node = 0, .last_node = if (value.segments.len == 0) 0 else value.segments.len - 1, .field = field };
        return error.InvalidTypedText;
    }
    return recognized;
}
fn valueChoices(a: std.mem.Allocator, all: r.Items, claim_ids: []const r.ClaimId) Error!ValueChoices {
    var choices: std.ArrayList(text.ExactCopy) = .empty;
    for (claim_ids) |id| {
        const claim = (try r.item(all, id)).claim;
        if (claim.content == .preserved_token) {
            const token = claim.content.preserved_token;
            if (!permitsExactKind(token.value.kind)) continue;
            try choices.append(a, .{ .claim_id = id });
        }
    }
    return .{ .exact_copy = try choices.toOwnedSlice(a) };
}
pub const Inspection = struct { value_choices: ?ValueChoices = null, part: @import("specification_candidate.zig").Part = .provenance, text_issue: ?text.Issue = null };

pub fn choicesFor(a: std.mem.Allocator, context: Context, selection: spec.Selection) Error!ValueChoices {
    return resolvedChoices(a, context, try resolve(.model, a, context, selection));
}

fn resolvedChoices(a: std.mem.Allocator, context: Context, resolved: Resolved) Error!ValueChoices {
    var choices = try valueChoices(a, try items(context), resolved.effective_claim_ids);
    const passive = try @import("reference_model_input.zig").passiveChoices(a, context.registry, context.inputs, resolved.scopes);
    defer a.free(passive);
    const ids = try a.alloc(@import("passive_literals.zig").Id, passive.len);
    for (passive, ids) |record, *id| id.* = record.id;
    choices.passive = ids;
    return choices;
}

fn valueIn(allocator: std.mem.Allocator, validator: text.Validator, context: Context, resolved: Resolved, candidate: spec.BusinessValue, field: text.field_policy.Field, inspection: *Inspection) Error!spec.BusinessValue {
    inspection.value_choices = try resolvedChoices(allocator, context, resolved);
    const accepted: spec.BusinessValue = .{ .segments = switch (try validator.checkBusinessIn(allocator, .{
        .registry = context.registry,
        .current = context.current,
        .inputs = context.inputs,
        .scopes = resolved.scopes,
        .exact_copies = inspection.value_choices.?.exact_copy,
        .field = field,
    }, .{ .segments = candidate.segments })) {
        .valid => |checked| checked.value.segments,
        .invalid => |issue| {
            inspection.text_issue = issue;
            return issue.failure();
        },
    } };
    errdefer {
        for (accepted.segments) |segment| if (segment == .literal) allocator.free(segment.literal.value);
        allocator.free(accepted.segments);
    }
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const recognized = try recognizeValue(arena.allocator(), refs.records(context.references), accepted, field, null);
    if (!try sameValue(arena.allocator(), accepted, recognized)) {
        inspection.text_issue = .{ .reason = .unknown_exact, .first_node = 0, .last_node = if (accepted.segments.len == 0) 0 else accepted.segments.len - 1, .field = field };
        return error.InvalidTypedText;
    }
    return accepted;
}

/// Intrinsic stored support joins. Current text/path policy is checked by the
/// live validators with its real toolchain, never reconstructed by a reader.
pub fn validateStored(a: std.mem.Allocator, inputs: evidence.Inputs, passive: @import("passive_literals.zig").Captured, references: @import("reference_support.zig").Records, brief: spec.Brief, candidate: spec.IdentifiedContent) Error!void {
    const Singleton = struct { value: spec.AttributedValue, field: text.field_policy.Field };
    for ([_]Singleton{
        .{ .value = brief.title, .field = .spec_title },                  .{ .value = brief.description, .field = .spec_description },
        .{ .value = brief.primary_goal, .field = .spec_goal },            .{ .value = candidate.display_name, .field = .spec_title },
        .{ .value = candidate.primary_user_story, .field = .spec_story }, .{ .value = candidate.entities.basis, .field = .spec_entity_basis },
    }) |entry| {
        const attributed = entry.value;
        if (attributed.source_group_ids.len == 0) return error.InvalidSpecification;
        const groups = try validateAssociation(.canonical, a, inputs, references, attributed.source_group_ids, attributed.provenance, .content);
        defer a.free(groups);
        const resolved = try resolveUnitRecords(.canonical, a, inputs, references, attributed.provenance, &.{attributed.value});
        try storedValue(a, inputs, passive, references, resolved, attributed.value, entry.field);
    }
    for (candidate.records) |record| {
        if (record.proposal.source_group_ids.len != 1) return error.InvalidSpecification;
        const groups = try validateAssociation(.canonical, a, inputs, references, record.proposal.source_group_ids, record.proposal.provenance, .content);
        defer a.free(groups);
        const values = try recordValues(a, record.proposal.content);
        const resolved = try resolveUnitRecords(.canonical, a, inputs, references, record.proposal.provenance, values);
        switch (record.proposal.content) {
            inline else => |fields, kind| inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                const value = @field(fields, field.name);
                if (comptime field.type == spec.BusinessValue) {
                    try storedValue(a, inputs, passive, references, resolved, value, spec.textField(kind, field.name));
                } else for (value) |relationship| try storedValue(a, inputs, passive, references, resolved, relationship, spec.textField(kind, field.name));
            },
        }
    }
}

fn storedValue(a: std.mem.Allocator, inputs: evidence.Inputs, passive: @import("passive_literals.zig").Captured, references: refs.Records, resolved: Resolved, value: spec.BusinessValue, field: text.field_policy.Field) Error!void {
    for (value.segments) |segment| if (segment == .literal and !text.validScalar(segment.literal.value)) return error.InvalidTypedText;
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const recognized = try recognizeValue(arena.allocator(), references, value, field, null);
    if (!try sameValue(arena.allocator(), value, recognized)) return error.InvalidTypedText;
    const choices = try valueChoices(a, references.items, resolved.effective_claim_ids);
    defer a.free(choices.exact_copy);
    try text.stored(text.BusinessSegment, a, .{ .inputs = inputs, .passive = passive, .scopes = resolved.scopes, .field = field, .exact_copies = choices.exact_copy }, value.segments);
}

/// Associations are occurrences, never reconstructed from matching claim sets.
pub fn validateAssociation(comptime boundary: spec.Boundary, a: std.mem.Allocator, inputs: evidence.Inputs, references: refs.Records, ids: []const r.SignalId, provenance: spec.Values(boundary).Evidence, mode: @import("specification_source_binding.zig").Mode) Error![]const r.SignalId {
    if (ids.len == 0) {
        if (provenance.claim_ids.len != 0) return error.InvalidSpecification;
        return &.{};
    }
    const selected = @import("specification_source_binding.zig").resolveGroups(a, references, inputs, ids, mode) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecification;
    defer a.free(selected.selection.claim_ids);
    errdefer a.free(selected.source_group_ids);
    if (selected.selection.claim_ids.len != provenance.claim_ids.len) return error.InvalidSpecification;
    for (selected.selection.claim_ids, provenance.claim_ids) |expected, actual| if (expected.ordinal != actual.ordinal) return error.InvalidSpecification;
    if (boundary == .canonical) {
        for (selected.source_group_ids, ids) |expected, actual| if (expected.ordinal != actual.ordinal) return error.InvalidSpecification;
    }
    return selected.source_group_ids;
}
pub fn inspectAttributed(comptime boundary: spec.Boundary, allocator: std.mem.Allocator, validator: text.Validator, context: Context, candidate: spec.Values(boundary).AttributedValue, field: text.field_policy.Field, inspection: *Inspection) Error!spec.AttributedValue {
    return inspectAttributedFor(boundary, allocator, validator, context, candidate, field, .content, inspection);
}
pub fn inspectAttributedFor(comptime boundary: spec.Boundary, allocator: std.mem.Allocator, validator: text.Validator, context: Context, candidate: spec.Values(boundary).AttributedValue, field: text.field_policy.Field, mode: @import("specification_source_binding.zig").Mode, inspection: *Inspection) Error!spec.AttributedValue {
    var scratch: std.heap.ArenaAllocator = .init(allocator);
    defer scratch.deinit();
    inspection.* = .{};
    const groups = try validateAssociation(boundary, allocator, context.inputs, refs.records(context.references), candidate.source_group_ids, candidate.provenance, mode);
    errdefer allocator.free(groups);
    inspection.part = .{ .value = .value };
    const recognized = try recognizeInspected(boundary, scratch.allocator(), refs.records(context.references), candidate.value, field, inspection);
    inspection.part = .provenance;
    const resolved = try resolveUnitRecords(boundary, allocator, context.inputs, refs.records(context.references), candidate.provenance, &.{recognized});
    inspection.part = .{ .value = .value };
    return .{ .value = try valueIn(allocator, validator, context, resolved, recognized, field, inspection), .source_group_ids = groups, .provenance = resolved.provenance };
}

pub fn inspectRecord(comptime boundary: spec.Boundary, allocator: std.mem.Allocator, validator: text.Validator, context: Context, candidate: spec.Values(boundary).RecordProposal, inspection: *Inspection) Error!spec.RecordProposal {
    var scratch: std.heap.ArenaAllocator = .init(allocator);
    defer scratch.deinit();
    inspection.* = .{};
    if (candidate.source_group_ids.len != 1) return error.InvalidSpecification;
    const groups = try validateAssociation(boundary, allocator, context.inputs, refs.records(context.references), candidate.source_group_ids, candidate.provenance, .content);
    errdefer allocator.free(groups);
    var recognized_content = candidate.content;
    switch (candidate.content) {
        inline else => |fields, kind| {
            var recognized_fields = fields;
            inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                const value = @field(fields, field.name);
                if (comptime field.type == spec.BusinessValue) {
                    inspection.part = .{ .value = @field(@import("specification_candidate.zig").ValueField, field.name) };
                    @field(recognized_fields, field.name) = try recognizeInspected(boundary, scratch.allocator(), refs.records(context.references), value, spec.textField(kind, field.name), inspection);
                } else {
                    const relationships = try scratch.allocator().alloc(spec.BusinessValue, value.len);
                    for (value, relationships, 0..) |entry, *recognized, index| {
                        inspection.part = .{ .value = .{ .relationship = index } };
                        recognized.* = try recognizeInspected(boundary, scratch.allocator(), refs.records(context.references), entry, spec.textField(kind, field.name), inspection);
                    }
                    @field(recognized_fields, field.name) = relationships;
                }
            }
            recognized_content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), recognized_fields);
        },
    }
    inspection.part = .provenance;
    const resolved = try resolveUnitRecords(boundary, allocator, context.inputs, refs.records(context.references), candidate.provenance, try recordValues(allocator, recognized_content));
    var result: spec.RecordProposal = .{ .content = recognized_content, .source_group_ids = groups, .provenance = resolved.provenance };
    switch (recognized_content) {
        inline else => |fields, kind| {
            var normalized = fields;
            inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                const proposed = @field(fields, field.name);
                if (comptime field.type == spec.BusinessValue) {
                    inspection.part = .{ .value = @field(@import("specification_candidate.zig").ValueField, field.name) };
                    @field(normalized, field.name) = try valueIn(allocator, validator, context, resolved, proposed, spec.textField(kind, field.name), inspection);
                } else {
                    const relationships = try allocator.alloc(spec.BusinessValue, proposed.len);
                    for (proposed, relationships, 0..) |entry, *checked, index| {
                        inspection.part = .{ .value = .{ .relationship = index } };
                        checked.* = try valueIn(allocator, validator, context, resolved, entry, spec.textField(kind, field.name), inspection);
                    }
                    @field(normalized, field.name) = relationships;
                }
            }
            result.content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), normalized);
        },
    }
    return result;
}

pub fn checkAttributed(comptime boundary: spec.Boundary, a: std.mem.Allocator, validator: text.Validator, context: Context, candidate: spec.Values(boundary).AttributedValue, field: text.field_policy.Field) Error!spec.AttributedValue {
    var inspection: Inspection = .{};
    return inspectAttributed(boundary, a, validator, context, candidate, field, &inspection);
}
pub fn checkRecord(comptime boundary: spec.Boundary, a: std.mem.Allocator, validator: text.Validator, context: Context, candidate: spec.Values(boundary).RecordProposal) Error!spec.RecordProposal {
    var inspection: Inspection = .{};
    return inspectRecord(boundary, a, validator, context, candidate, &inspection);
}
