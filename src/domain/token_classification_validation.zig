//! Mechanical classification coverage; semantic preserve/irrelevant choices
//! remain model candidates. Source authority failures are never repair requests.
const std = @import("std");
const extraction = @import("reference_extraction.zig");
const tokens = extraction.tokens;
const evidence = @import("reference_evidence.zig");
pub const Issues = struct {
    missing: []const tokens.CandidateId,
    duplicate: []const tokens.CandidateId,
    unknown: []const tokens.CandidateId,
    forbidden: []const tokens.CandidateId,
};
pub const Choices = struct { outcome: std.meta.Tag(@FieldType(extraction.TextValidatedResult, "outcome")), decisions: []const std.meta.Tag(tokens.Classification) };
pub fn choices(outcome: std.meta.Tag(@FieldType(extraction.TextValidatedResult, "outcome"))) Choices {
    return .{ .outcome = outcome, .decisions = switch (outcome) {
        .claims => &.{ .preserve, .irrelevant },
        .no_feature_claim => &.{.irrelevant},
        .blocked => &.{},
    } };
}
pub const Rejection = struct {
    dependencies: ?@import("atomic_repair.zig").Snapshot = null,
    origin: ?@import("model_candidate_origin.zig").Origin = null,
    scope: evidence.Scope,
    revision: u64,
    field: enum { token_classifications } = .token_classifications,
    issues: Issues,
    choices: Choices,
    observed: []const tokens.Classification,
};
pub const Result = union(enum) { valid: extraction.Classified, invalid: Rejection };

pub fn validate(a: std.mem.Allocator, inputs: evidence.Inputs, candidates: tokens.Candidates, parsed: extraction.TextValidated) extraction.Error!Result {
    return check(a, inputs, candidates, parsed, null);
}

/// The selected chunk uses the complete validator's classification checks.
/// This observation does not publish a partially classified extraction.
pub fn validScope(a: std.mem.Allocator, inputs: evidence.Inputs, candidates: tokens.Candidates, parsed: extraction.TextValidated, scope: evidence.Scope) extraction.Error!bool {
    _ = try evidence.resolve(inputs, scope);
    return (try check(a, inputs, candidates, parsed, scope)) == .valid;
}

fn check(a: std.mem.Allocator, inputs: evidence.Inputs, candidates: tokens.Candidates, parsed: extraction.TextValidated, selected_scope: ?evidence.Scope) extraction.Error!Result {
    try tokens.validateCandidates(a, inputs, candidates);
    if (parsed.revision == 0 or parsed.entries.len != inputs.chunks.entries.len) return error.InvalidReferenceExtraction;
    const ordered = try a.alloc(extraction.TextValidatedResult, parsed.entries.len);
    for (inputs.chunks.entries, ordered) |chunk, *entry| {
        var selected: ?extraction.TextValidatedResult = null;
        for (parsed.entries) |candidate| {
            if (!candidate.scope.state_id.eql(inputs.corpus.state_id)) return error.InvalidReferenceExtraction;
            if (!candidate.scope.chunk_id.eql(chunk.id)) continue;
            if (selected != null) return error.InvalidReferenceExtraction;
            selected = candidate;
        }
        entry.* = selected orelse return error.InvalidReferenceExtraction;
    }
    const selection_count = if (selected_scope) |scope| count: {
        var count: usize = 0;
        for (candidates.entries) |candidate| if (candidate.fact.scope.chunk_id.eql(scope.chunk_id)) {
            count += 1;
        };
        break :count count;
    } else candidates.entries.len;
    const selections = try a.alloc(tokens.Selected, selection_count);
    var index: usize = 0;
    for (ordered) |entry| {
        if (selected_scope) |scope| if (!entry.scope.chunk_id.eql(scope.chunk_id)) continue;
        var missing: std.ArrayList(tokens.CandidateId) = .empty;
        var duplicate: std.ArrayList(tokens.CandidateId) = .empty;
        var unknown: std.ArrayList(tokens.CandidateId) = .empty;
        var forbidden: std.ArrayList(tokens.CandidateId) = .empty;
        for (candidates.entries) |candidate| {
            if (!candidate.fact.scope.chunk_id.eql(entry.scope.chunk_id)) continue;
            var count: usize = 0;
            var decision: tokens.Decision = .blocked;
            for (entry.token_classifications) |classification| {
                if (!std.meta.eql(classification.id(), candidate.id)) continue;
                count += 1;
                decision = switch (classification) {
                    .preserve => |value| .{ .preserve = value.kind },
                    .irrelevant => .irrelevant,
                };
            }
            if (entry.outcome != .blocked and count == 0) try missing.append(a, candidate.id);
            if (count > 1) try duplicate.append(a, candidate.id);
            selections[index] = .{ .candidate = try tokens.copy(a, candidate), .decision = decision };
            index += 1;
        }
        for (entry.token_classifications) |classification| {
            const known = for (candidates.entries) |candidate| {
                if (candidate.fact.scope.chunk_id.eql(entry.scope.chunk_id) and std.meta.eql(classification.id(), candidate.id)) break true;
            } else false;
            if (!known) try unknown.append(a, classification.id());
            if (std.mem.indexOfScalar(std.meta.Tag(tokens.Classification), choices(entry.outcome).decisions, classification) == null) try forbidden.append(a, classification.id());
        }
        if (missing.items.len + duplicate.items.len + unknown.items.len + forbidden.items.len != 0) {
            // A blocked entry is engine-owned, so contradictory data is an
            // authority failure, not an invitation to have the model repair it.
            if (entry.outcome == .blocked) return error.InvalidReferenceExtraction;
            return .{ .invalid = .{ .dependencies = try @import("reference_extraction_context.zig").snapshot(a, .{ .inputs = inputs, .candidates = candidates, .candidate = parsed }), .scope = entry.scope, .revision = parsed.revision, .origin = entry.classification_origin, .observed = entry.token_classifications, .choices = choices(entry.outcome), .issues = .{
                .missing = try missing.toOwnedSlice(a),
                .duplicate = try duplicate.toOwnedSlice(a),
                .unknown = try unknown.toOwnedSlice(a),
                .forbidden = try forbidden.toOwnedSlice(a),
            } } };
        }
    }
    if (index != selections.len) return error.InvalidStructuredTokens;
    var retained = parsed;
    retained.entries = ordered;
    return .{ .valid = .{ .dependencies = try @import("reference_extraction_context.zig").snapshot(a, .{ .inputs = inputs, .candidates = candidates, .candidate = parsed }), .text_validated = retained, .selections = selections } };
}
