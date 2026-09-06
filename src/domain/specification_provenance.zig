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

pub fn items(context: Context) Error!r.Items {
    const result = context.references.records.assignments.checked.prior.prior.input.progress.plan.layout.items;
    if (!result.state_id.eql(context.inputs.corpus.state_id)) return error.InvalidSpecification;
    return result;
}

/// Initial reference-grounded generation. Applicable user-response support is
/// supplied by the clarification lifecycle, not inferred from loaded form IDs.
pub fn scopes(allocator: std.mem.Allocator, context: Context, provenance: spec.Provenance) Error![]const evidence.Scope {
    const claims = try items(context);
    if (provenance.claim_ids.len == 0 or provenance.clarification_response_ids.len != 0) return error.InvalidSpecification;
    try r.unique(r.ClaimId, provenance.claim_ids);
    try r.unique(r.CitationId, provenance.citation_ids);
    var citations: std.ArrayList(r.CitationId) = .empty;
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
        for (claim.citation_ids) |citation| if (!r.contains(r.CitationId, citations.items, citation)) try citations.append(allocator, citation);
        scope.* = .{ .state_id = claims.state_id, .chunk_id = claim.chunk_id };
        _ = try evidence.resolve(context.inputs, scope.*);
    }
    // Stable unique union in selected-claim order, not an arbitrary superset.
    if (citations.items.len != provenance.citation_ids.len) return error.InvalidSpecification;
    for (citations.items, provenance.citation_ids) |expected, actual| if (expected.ordinal != actual.ordinal) return error.InvalidSpecification;
    return result;
}

pub fn value(allocator: std.mem.Allocator, validator: text.Validator, context: Context, provenance: spec.Provenance, candidate: spec.BusinessValue) Error!spec.BusinessValue {
    const allowed = try scopes(allocator, context, provenance);
    return switch (candidate) {
        .normalized => |proposed| .{ .normalized = (try validator.businessIn(allocator, .{ .registry = context.registry, .current = context.current, .inputs = context.inputs, .scopes = allowed }, proposed)).value },
        .exact_copy => |selected| result: {
            const all = try items(context);
            for (provenance.claim_ids) |id| {
                const claim = (try r.item(all, id)).claim;
                if (claim.content == .preserved_token) {
                    const token = claim.content.preserved_token;
                    if (token.value.id.ordinal == selected.token_id.ordinal and token.citation_id.ordinal == selected.citation_id.ordinal) break :result candidate;
                }
            }
            return error.InvalidSpecification;
        },
    };
}

pub fn attributed(allocator: std.mem.Allocator, validator: text.Validator, context: Context, candidate: spec.AttributedValue) Error!spec.AttributedValue {
    return .{ .value = try value(allocator, validator, context, candidate.provenance, candidate.value), .provenance = candidate.provenance };
}

pub fn record(allocator: std.mem.Allocator, validator: text.Validator, context: Context, candidate: spec.RecordProposal) Error!spec.RecordProposal {
    var result = candidate;
    switch (candidate.content) {
        inline else => |fields, kind| {
            var normalized = fields;
            inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                const proposed = @field(fields, field.name);
                if (comptime field.type == spec.BusinessValue) {
                    @field(normalized, field.name) = try value(allocator, validator, context, candidate.provenance, proposed);
                } else {
                    const relationships = try allocator.alloc(spec.BusinessValue, proposed.len);
                    for (proposed, relationships) |entry, *checked| checked.* = try value(allocator, validator, context, candidate.provenance, entry);
                    @field(normalized, field.name) = relationships;
                }
            }
            result.content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), normalized);
        },
    }
    return result;
}
