//! Read-only producer comparison views. Eligibility and repair authority remain
//! in source_omission; this projection only brings existing evidence together.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const loss = @import("source_omission.zig");
const evidence = @import("model_evidence.zig");
const Records = @import("reference_support.zig").Records;
const Context = @import("specification_provenance.zig").Context;
const Extraction = struct {
    chunk_id: r.extraction.identity.ChunkId,
    source_id: r.extraction.identity.SourceId,
    location: @FieldType(evidence.ExtractionReview, "location"),
    outcome: union(enum) { claims: []const r.ClaimId, no_feature_claim: []const u8, blocked: r.extraction.BlockReason },
    token_classifications: @FieldType(evidence.ExtractionReview, "token_classifications"),
};
pub const Signal = struct { id: r.SignalId, value: struct { claim_ids: []const r.ClaimId, citation_ids: []const r.CitationId, content: evidence.Meaning } };
pub const Conflict = struct { id: r.ConflictId, value: struct { claim_ids: []const r.ClaimId, citation_ids: []const r.CitationId, kind: r.ConflictKind, summary: []const u8, resolution: @FieldType(r.ValidatedConflict, "resolution") } };

pub const Producer = struct {
    location: ?loss.Location,
    output: union(enum) {
        extraction: struct { result: Extraction, claims: evidence.ResolvedProjection },
        token_classification: std.meta.Child(@FieldType(evidence.ExtractionReview, "token_classifications")),
        signal: struct { result: Signal, claims: evidence.ResolvedProjection },
        disposition: struct { result: r.ClaimDisposition, claims: evidence.ResolvedProjection },
        conflict: struct { result: Conflict, claims: evidence.ResolvedProjection },
    },
};

fn claims(a: std.mem.Allocator, items: r.Items, ids: []const r.ClaimId, context: Context) r.Error!evidence.ResolvedProjection {
    const selected = try a.alloc(r.Item, ids.len);
    for (ids, selected) |id, *item| item.* = try r.item(items, id);
    return evidence.resolvedProject(a, selected, context.inputs, context.registry);
}

fn scopes(a: std.mem.Allocator, items: r.Items, ids: []const r.ClaimId, context: Context) r.Error![]const r.evidence.Scope {
    return (try @import("reference_reconciliation_validation.zig").scopes(a, items, ids, .{ .inputs = context.inputs, .registry = context.registry, .current = context.current })).scopes;
}

pub fn projectSignal(a: std.mem.Allocator, records: Records, context: Context, signal: r.Signal) r.Error!Signal {
    const content: evidence.Meaning = switch (signal.value.content) {
        .model => |model| try evidence.modelMeaning(a, context.inputs, context.registry, try scopes(a, records.items, signal.value.claim_ids, context), model),
        .preserved_token => |reference| selected: {
            for (signal.value.claim_ids) |id| {
                const claim = (try r.item(records.items, id)).claim;
                if (claim.content != .preserved_token) continue;
                const token = claim.content.preserved_token.value;
                if (std.meta.eql(token.id, reference.token_id)) break :selected .{ .kind = "preserved_token", .meaning = token.raw_value.bytes };
            }
            return error.InvalidReferenceReconciliation;
        },
    };
    return .{ .id = signal.id, .value = .{ .claim_ids = signal.value.claim_ids, .citation_ids = signal.value.citation_ids, .content = content } };
}

pub fn projectConflict(a: std.mem.Allocator, records: Records, context: Context, conflict: r.Conflict) r.Error!Conflict {
    return .{ .id = conflict.id, .value = .{ .claim_ids = conflict.value.claim_ids, .citation_ids = conflict.value.citation_ids, .kind = conflict.value.kind, .summary = try evidence.resolveText(a, context.inputs, context.registry, try scopes(a, records.items, conflict.value.claim_ids, context), .{ .reference = conflict.value.summary.value }), .resolution = conflict.value.resolution } };
}

/// Caller-owned request arena. Every producer supplies comparison evidence;
/// only existing admitted choices expose a selectable location.
pub fn project(a: std.mem.Allocator, records: Records, context: Context, locations: []const loss.Location) r.Error![]const Producer {
    const extraction = try evidence.extractionReview(a, context.inputs, records.items.extraction);
    var result: std.ArrayList(Producer) = .empty;
    const producers = try loss.producerLocations(a, records);
    defer a.free(producers);
    for (producers) |location| {
        const output: @FieldType(Producer, "output") = switch (location) {
            .unlocalized, .candidate => continue,
            .extraction_claim => |id| value: {
                for (extraction) |chunk| if (chunk.chunk_id.eql(id)) break :value .{ .extraction = .{
                    .result = .{
                        .chunk_id = chunk.chunk_id,
                        .source_id = chunk.source_id,
                        .location = chunk.location,
                        .token_classifications = chunk.token_classifications,
                        .outcome = switch (chunk.outcome) {
                            .claims => |ids| .{ .claims = ids },
                            .no_feature_claim => |text| .{ .no_feature_claim = try evidence.resolveText(a, context.inputs, context.registry, &.{.{ .state_id = records.items.state_id, .chunk_id = chunk.chunk_id }}, .{ .reference = text }) },
                            .blocked => |reason| .{ .blocked = reason },
                        },
                    },
                    .claims = try claims(a, records.items, if (chunk.outcome == .claims) chunk.outcome.claims else &.{}, context),
                } };
                return error.InvalidReferenceReconciliation;
            },
            .token_classification => |id| value: {
                for (extraction) |chunk| for (chunk.token_classifications) |classification| {
                    if (std.meta.eql(classification.candidate.id, id)) break :value .{ .token_classification = classification };
                };
                return error.InvalidReferenceReconciliation;
            },
            .reconciliation_signal => |id| value: {
                for (records.signals) |signal| if (std.meta.eql(signal.id, id)) break :value .{ .signal = .{
                    .result = try projectSignal(a, records, context, signal),
                    .claims = try claims(a, records.items, signal.value.claim_ids, context),
                } };
                return error.InvalidReferenceReconciliation;
            },
            .reconciliation_disposition => |id| value: {
                for (records.dispositions) |disposition| if (std.meta.eql(disposition.claim_id, id)) {
                    var ids: std.ArrayList(r.ClaimId) = .empty;
                    try ids.append(a, id);
                    for (disposition.related_claim_ids) |related| if (!r.contains(r.ClaimId, ids.items, related)) try ids.append(a, related);
                    break :value .{ .disposition = .{ .result = disposition, .claims = try claims(a, records.items, ids.items, context) } };
                };
                return error.InvalidReferenceReconciliation;
            },
            .reconciliation_conflict => |id| value: {
                for (records.conflicts) |conflict| if (std.meta.eql(conflict.id, id)) break :value .{ .conflict = .{
                    .result = try projectConflict(a, records, context, conflict),
                    .claims = try claims(a, records.items, conflict.value.claim_ids, context),
                } };
                return error.InvalidReferenceReconciliation;
            },
        };
        const selectable = for (locations) |allowed| {
            if (location.eql(allowed)) break true;
        } else false;
        try result.append(a, .{ .location = if (selectable) location else null, .output = output });
    }
    return result.toOwnedSlice(a);
}
