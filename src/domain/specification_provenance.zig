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
const Resolved = struct { provenance: spec.Provenance, scopes: []const evidence.Scope };

fn resolve(comptime boundary: spec.Boundary, allocator: std.mem.Allocator, context: Context, provenance: spec.Values(boundary).Evidence) Error!Resolved {
    const claims = try items(context);
    if (provenance.claim_ids.len == 0 or provenance.clarification_response_ids.len != 0) return error.InvalidSpecification;
    try r.unique(r.ClaimId, provenance.claim_ids);
    if (boundary == .canonical) try r.unique(r.CitationId, provenance.citation_ids);
    const result = try allocator.alloc(evidence.Scope, provenance.claim_ids.len);
    const dispositions = context.references.records.assignments.checked.prior.prior.dispositions;
    for (provenance.claim_ids, result) |id, *scope| {
        const claim = (try r.item(claims, id)).claim;
        var retained = false;
        for (dispositions) |disposition| if (disposition.claim_id.ordinal == id.ordinal) {
            retained = disposition.disposition == .retained;
            break;
        };
        if (!retained) return error.InvalidSpecification;
        scope.* = .{ .state_id = claims.state_id, .chunk_id = claim.chunk_id };
        _ = try evidence.resolve(context.inputs, scope.*);
    }
    // Stable unique union in selected-claim order, not an arbitrary superset.
    const citations = try r.citationUnion(allocator, claims, provenance.claim_ids);
    if (boundary == .canonical) {
        if (citations.len != provenance.citation_ids.len) return error.InvalidSpecification;
        for (citations, provenance.citation_ids) |expected, actual| if (expected.ordinal != actual.ordinal) return error.InvalidSpecification;
    }
    return .{ .provenance = .{ .claim_ids = provenance.claim_ids, .citation_ids = citations, .clarification_response_ids = provenance.clarification_response_ids }, .scopes = result };
}

pub fn scopes(allocator: std.mem.Allocator, context: Context, provenance: spec.Provenance) Error![]const evidence.Scope {
    return (try resolve(.canonical, allocator, context, provenance)).scopes;
}

/// Construct complete provenance from meaningful, currently eligible selections.
pub fn select(allocator: std.mem.Allocator, context: Context, selection: spec.Selection) Error!spec.Provenance {
    return (try resolve(.model, allocator, context, selection)).provenance;
}

pub const ValueChoices = struct {
    normalized: bool = true,
    exact_copy: []const @FieldType(spec.BusinessValue, "exact_copy"),
};
fn valueChoices(a: std.mem.Allocator, context: Context, provenance: spec.Provenance) Error!ValueChoices {
    var choices: std.ArrayList(@FieldType(spec.BusinessValue, "exact_copy")) = .empty;
    const all = try items(context);
    for (provenance.claim_ids) |id| {
        const claim = (try r.item(all, id)).claim;
        if (claim.content == .preserved_token) {
            const token = claim.content.preserved_token;
            try choices.append(a, .{ .token_id = token.value.id, .citation_id = token.citation_id });
        }
    }
    return .{ .exact_copy = try choices.toOwnedSlice(a) };
}
pub const Inspection = struct { value_choices: ?ValueChoices = null, part: @import("specification_candidate.zig").Part = .provenance, text_issue: ?text.Issue = null };

fn valueIn(allocator: std.mem.Allocator, validator: text.Validator, context: Context, resolved: Resolved, candidate: spec.BusinessValue, inspection: *Inspection) Error!spec.BusinessValue {
    inspection.value_choices = try valueChoices(allocator, context, resolved.provenance);
    return switch (candidate) {
        .normalized => |proposed| .{ .normalized = switch (try validator.checkBusinessIn(allocator, .{ .registry = context.registry, .current = context.current, .inputs = context.inputs, .scopes = resolved.scopes }, proposed)) {
            .valid => |checked| checked.value,
            .invalid => |issue| {
                inspection.text_issue = issue;
                return issue.failure();
            },
        } },
        .exact_copy => |selected| result: {
            for (inspection.value_choices.?.exact_copy) |choice| if (std.meta.eql(choice, selected)) break :result candidate;
            return error.InvalidSpecification;
        },
    };
}

pub fn inspectAttributed(comptime boundary: spec.Boundary, allocator: std.mem.Allocator, validator: text.Validator, context: Context, candidate: spec.Values(boundary).AttributedValue, inspection: *Inspection) Error!spec.AttributedValue {
    inspection.* = .{};
    const resolved = try resolve(boundary, allocator, context, candidate.provenance);
    inspection.part = .{ .value = .value };
    return .{ .value = try valueIn(allocator, validator, context, resolved, candidate.value, inspection), .provenance = resolved.provenance };
}

pub fn inspectRecord(comptime boundary: spec.Boundary, allocator: std.mem.Allocator, validator: text.Validator, context: Context, candidate: spec.Values(boundary).RecordProposal, inspection: *Inspection) Error!spec.RecordProposal {
    inspection.* = .{};
    const resolved = try resolve(boundary, allocator, context, candidate.provenance);
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
