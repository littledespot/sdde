//! Mechanical support joins only. A real citation is not semantic entailment.
const std = @import("std");
const spec = @import("specification.zig");
const r = @import("reference_reconciliation.zig");
const evidence = @import("reference_evidence.zig");
const text = @import("typed_text.zig");
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

/// Business-provenance eligibility, shared by generation and coverage.
/// Missing disposition accounts cannot authorize a claim.
pub fn eligibleClaim(disposition: ?r.Disposition) bool {
    return disposition != null and disposition.? == .retained;
}

/// A draft needs at least one possible positive evidence selection. This is
/// structural readiness, not a judgment that the source supports every field.
pub fn generationReady(references: r.Accounted) bool {
    if (references.outcome != .complete) return false;
    for (references.records.assignments.checked.prior.prior.dispositions) |disposition| {
        if (eligibleClaim(disposition.disposition)) return true;
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
pub fn checkValueInUnit(allocator: std.mem.Allocator, validator: text.Validator, context: Context, selection: spec.Selection, values: []const spec.BusinessValue, value: spec.BusinessValue) Error!spec.BusinessValue {
    const resolved = try lineageForRepair(allocator, context, selection, values);
    var inspection: Inspection = .{};
    return valueIn(allocator, validator, context, resolved, value, &inspection);
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
        if (!permitsExactKind(token.value.kind) or !eligibleClaim(dispositionFor(references, id))) {
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
    for (provenance.claim_ids) |id| if (!eligibleClaim(dispositionFor(references, id))) return error.InvalidSpecification;
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
                "No passive references or exact-copy values are permitted; return source-backed text strings."
            else
                "No passive references are permitted; use source-backed text strings or a listed exact-copy claim.")
        else if (self.exact_copy.len == 0)
            "No exact-copy values are permitted; use source-backed text strings or listed passive IDs."
        else
            "Use source-backed text strings, listed passive IDs or a listed exact-copy claim.";
        return std.fmt.allocPrint(a, "Validation failed: {s} is unavailable for this field's authorized evidence. {s} Preserve the fixed evidence and source meaning.", .{ rejected, permitted });
    }
};

/// Code examples remain reference context under the business-specification contract.
pub fn permitsExactKind(kind: r.extraction.tokens.Kind) bool {
    return kind != .code_sample;
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

fn valueIn(allocator: std.mem.Allocator, validator: text.Validator, context: Context, resolved: Resolved, candidate: spec.BusinessValue, inspection: *Inspection) Error!spec.BusinessValue {
    inspection.value_choices = try resolvedChoices(allocator, context, resolved);
    return .{ .segments = switch (try validator.checkBusinessIn(allocator, .{
        .registry = context.registry,
        .current = context.current,
        .inputs = context.inputs,
        .scopes = resolved.scopes,
        .exact_copies = inspection.value_choices.?.exact_copy,
    }, .{ .segments = candidate.segments })) {
        .valid => |checked| checked.value.segments,
        .invalid => |issue| {
            inspection.text_issue = issue;
            return issue.failure();
        },
    } };
}

/// Intrinsic stored support joins. Current text/path policy is checked by the
/// live validators with its real toolchain, never reconstructed by a reader.
pub fn validateStored(a: std.mem.Allocator, inputs: evidence.Inputs, passive: @import("passive_literals.zig").Captured, references: @import("reference_support.zig").Records, brief: spec.Brief, candidate: spec.IdentifiedContent) Error!void {
    for ([_]spec.AttributedValue{ brief.title, brief.description, brief.primary_goal, candidate.display_name, candidate.primary_user_story, candidate.entities.basis }) |attributed| {
        const resolved = try resolveUnitRecords(.canonical, a, inputs, references, attributed.provenance, &.{attributed.value});
        try storedValue(inputs, passive, resolved, attributed.value);
    }
    for (candidate.records) |record| {
        const values = try recordValues(a, record.proposal.content);
        const resolved = try resolveUnitRecords(.canonical, a, inputs, references, record.proposal.provenance, values);
        switch (record.proposal.content) {
            inline else => |fields| inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                const value = @field(fields, field.name);
                if (comptime field.type == spec.BusinessValue) {
                    try storedValue(inputs, passive, resolved, value);
                } else for (value) |relationship| try storedValue(inputs, passive, resolved, relationship);
            },
        }
    }
}

fn storedValue(inputs: evidence.Inputs, passive: @import("passive_literals.zig").Captured, resolved: Resolved, value: spec.BusinessValue) Error!void {
    for (value.segments) |segment| switch (segment) {
        .passive => |reference| {
            _ = try @import("passive_literals.zig").resolveCaptured(passive, inputs, resolved.scopes, reference.passive_literal_id);
        },
        .literal, .exact_copy => {},
    };
}

pub fn inspectAttributed(comptime boundary: spec.Boundary, allocator: std.mem.Allocator, validator: text.Validator, context: Context, candidate: spec.Values(boundary).AttributedValue, inspection: *Inspection) Error!spec.AttributedValue {
    inspection.* = .{};
    const resolved = try resolveUnitRecords(boundary, allocator, context.inputs, @import("reference_support.zig").records(context.references), candidate.provenance, &.{candidate.value});
    inspection.part = .{ .value = .value };
    return .{ .value = try valueIn(allocator, validator, context, resolved, candidate.value, inspection), .provenance = resolved.provenance };
}

pub fn inspectRecord(comptime boundary: spec.Boundary, allocator: std.mem.Allocator, validator: text.Validator, context: Context, candidate: spec.Values(boundary).RecordProposal, inspection: *Inspection) Error!spec.RecordProposal {
    inspection.* = .{};
    const resolved = try resolveUnitRecords(boundary, allocator, context.inputs, @import("reference_support.zig").records(context.references), candidate.provenance, try recordValues(allocator, candidate.content));
    var result: spec.RecordProposal = .{ .content = candidate.content, .provenance = resolved.provenance };
    switch (candidate.content) {
        inline else => |fields, kind| {
            var normalized = fields;
            inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                const proposed = @field(fields, field.name);
                if (comptime field.type == spec.BusinessValue) {
                    inspection.part = .{ .value = @field(@import("specification_candidate.zig").ValueField, field.name) };
                    @field(normalized, field.name) = try valueIn(allocator, validator, context, resolved, proposed, inspection);
                } else {
                    const relationships = try allocator.alloc(spec.BusinessValue, proposed.len);
                    for (proposed, relationships, 0..) |entry, *checked, index| {
                        inspection.part = .{ .value = .{ .relationship = index } };
                        checked.* = try valueIn(allocator, validator, context, resolved, entry, inspection);
                    }
                    @field(normalized, field.name) = relationships;
                }
            }
            result.content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), normalized);
        },
    }
    return result;
}

pub fn checkAttributed(comptime boundary: spec.Boundary, a: std.mem.Allocator, validator: text.Validator, context: Context, candidate: spec.Values(boundary).AttributedValue) Error!spec.AttributedValue {
    var inspection: Inspection = .{};
    return inspectAttributed(boundary, a, validator, context, candidate, &inspection);
}
pub fn checkRecord(comptime boundary: spec.Boundary, a: std.mem.Allocator, validator: text.Validator, context: Context, candidate: spec.Values(boundary).RecordProposal) Error!spec.RecordProposal {
    var inspection: Inspection = .{};
    return inspectRecord(boundary, a, validator, context, candidate, &inspection);
}
