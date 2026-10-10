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
/// none of these supporting outputs carries repair authority.
pub fn project(a: std.mem.Allocator, records: Records, context: Context) r.Error![]const Producer {
    const extraction = try evidence.extractionReview(a, context.inputs, records.items.extraction);
    var result: std.ArrayList(Producer) = .empty;
    const producers = try loss.producerLocations(a, records);
    defer a.free(producers);
    for (producers) |location| {
        const output: @FieldType(Producer, "output") = switch (location) {
            .unlocalized, .candidate, .unsupported_role, .unsupported_summary => continue,
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
        try result.append(a, .{ .output = output });
    }
    return result.toOwnedSlice(a);
}

const authority = @import("required_authority.zig");
fn intersects(left: []const r.ClaimId, right: []const r.ClaimId) bool {
    for (left) |id| if (r.contains(r.ClaimId, right, id)) return true;
    return false;
}

/// Loss requests expose complete native collections with local member labels.
/// Canonical claim/citation identities and half-open source coordinates stay in
/// the retained assignment.
/// Preservation compares resolved meaning, not extraction categories. Categories
/// remain in canonical evidence and classification decisions, where they matter.
pub const ClaimMeaning = struct { meaning: []const u8, source_id: r.extraction.identity.SourceId };

pub fn claimMeaning(a: std.mem.Allocator, items: r.Items, id: r.ClaimId, context: Context) r.Error!ClaimMeaning {
    const value = try evidence.requirement(a, try r.item(items, id), context.inputs, context.registry);
    return .{ .meaning = value.meaning, .source_id = value.source_id };
}

fn meanings(a: std.mem.Allocator, values: []const evidence.ResolvedClaim) std.mem.Allocator.Error![]const ClaimMeaning {
    const result = try a.alloc(ClaimMeaning, values.len);
    for (values, result) |value, *copy| copy.* = .{ .meaning = value.meaning, .source_id = value.source_id };
    return result;
}

const Classification = struct {
    source_id: r.extraction.identity.SourceId,
    verbatim: ?[]const u8,
    decision: @FieldType(std.meta.Child(@FieldType(evidence.ExtractionReview, "token_classifications")), "decision"),
};

fn classificationMeaning(value: std.meta.Child(@FieldType(evidence.ExtractionReview, "token_classifications"))) Classification {
    return .{ .source_id = value.candidate.id.source_id, .verbatim = value.candidate.verbatim, .decision = value.decision };
}

const ConflictMeaning = struct { kind: r.ConflictKind, summary: []const u8, resolution: @FieldType(r.ValidatedConflict, "resolution") };
fn conflictMeaning(value: Conflict) ConflictMeaning {
    return .{ .kind = value.value.kind, .summary = value.value.summary, .resolution = value.value.resolution };
}

const Subject = @import("specification_review_subject.zig").LossSubject;
pub const FixedSubject = union(enum) {
    business: @FieldType(Subject, "business"),
    brief_field: @FieldType(Subject, "brief_field"),
    pending_subject: @FieldType(Subject, "pending_subject"),
    reference: union(enum) {
        source: r.extraction.identity.SourceId,
        signal: evidence.Meaning,
        token: struct { kind: @import("structured_tokens.zig").Kind, value: []const u8 },
        conflict: ConflictMeaning,
    },
};

pub fn fixedSubject(value: Subject) FixedSubject {
    return switch (value) {
        .business => |subject| .{ .business = subject },
        .brief_field => |subject| .{ .brief_field = subject },
        .pending_subject => |subject| .{ .pending_subject = subject },
        .reference => |subject| .{ .reference = switch (subject) {
            .source => |source| .{ .source = source },
            .signal => |signal| .{ .signal = signal.value.content },
            .token => |token| .{ .token = .{ .kind = token.kind, .value = token.value } },
            .conflict => |conflict| .{ .conflict = conflictMeaning(conflict) },
        } },
    };
}

pub const SupportingProducer = struct {
    output: union(enum) {
        extraction: struct {
            source_id: r.extraction.identity.SourceId,
            outcome: union(enum) { claims: []const ClaimMeaning, no_feature_claim: []const u8, blocked: r.extraction.BlockReason },
            token_classifications: []const Classification,
        },
        token_classification: Classification,
        signal: struct { inputs: []const ClaimMeaning, content: evidence.Meaning, roles: []const r.GenerationRole },
        disposition: struct { input: ClaimMeaning, related: []const ClaimMeaning, disposition: r.Disposition },
        conflict: struct { inputs: []const ClaimMeaning, content: ConflictMeaning },
    },
};

pub fn comparisonSupport(a: std.mem.Allocator, records: Records, context: Context, source_ids: []const r.extraction.identity.SourceId, ids: []const r.ClaimId) r.Error![]const SupportingProducer {
    var selected: std.ArrayList(SupportingProducer) = .empty;
    for (try project(a, records, context)) |producer| {
        const relevant = switch (producer.output) {
            .extraction => |value| authority.contains(r.extraction.identity.SourceId, source_ids, value.result.source_id),
            .token_classification => |value| authority.contains(r.extraction.identity.SourceId, source_ids, value.candidate.id.source_id),
            .signal => |value| intersects(value.result.value.claim_ids, ids),
            .disposition => |value| r.contains(r.ClaimId, ids, value.result.claim_id),
            .conflict => |value| intersects(value.result.value.claim_ids, ids),
        };
        if (!relevant) continue;
        const output: @FieldType(SupportingProducer, "output") = switch (producer.output) {
            .extraction => |value| blk: {
                const decisions = try a.alloc(Classification, value.result.token_classifications.len);
                for (value.result.token_classifications, decisions) |decision, *copy| copy.* = classificationMeaning(decision);
                break :blk .{ .extraction = .{
                    .source_id = value.result.source_id,
                    .outcome = switch (value.result.outcome) {
                        .claims => .{ .claims = try meanings(a, value.claims.claims) },
                        .no_feature_claim => |reason| .{ .no_feature_claim = reason },
                        .blocked => |reason| .{ .blocked = reason },
                    },
                    .token_classifications = decisions,
                } };
            },
            .token_classification => |value| .{ .token_classification = classificationMeaning(value) },
            .signal => |value| .{ .signal = .{
                .inputs = try meanings(a, value.claims.claims),
                .content = value.result.value.content,
                .roles = for (records.signals) |signal| {
                    if (std.meta.eql(signal.id, value.result.id)) break signal.value.generation_roles;
                } else return error.InvalidReferenceReconciliation,
            } },
            .disposition => |value| blk: {
                const related = try a.alloc(ClaimMeaning, value.result.related_claim_ids.len);
                for (value.result.related_claim_ids, related) |id, *copy| copy.* = try claimMeaning(a, records.items, id, context);
                break :blk .{ .disposition = .{ .input = try claimMeaning(a, records.items, value.result.claim_id, context), .related = related, .disposition = value.result.disposition } };
            },
            .conflict => |value| .{ .conflict = .{ .inputs = try meanings(a, value.claims.claims), .content = conflictMeaning(value.result) } },
        };
        try selected.append(a, .{ .output = output });
    }
    return selected.toOwnedSlice(a);
}
