//! Mechanical source-selection validation; no semantic-support or retry policy.
const std = @import("std");
const extraction = @import("reference_extraction.zig");
const evidence = @import("reference_evidence.zig");
const selections = @import("source_selections.zig");
pub const Rejection = struct {
    scope: evidence.Scope,
    revision: u64,
    claim_index: usize,
    field: enum { citations } = .citations,
    issue: selections.Issue,
    origin: ?@import("model_candidate_origin.zig").Origin = null,
};

pub const Result = union(enum) {
    valid: extraction.Classified,
    token_classifications: @import("token_classification_validation.zig").Rejection,
    source_selections: Rejection,
};

pub fn validate(a: std.mem.Allocator, inputs: evidence.Inputs, candidates: extraction.tokens.Candidates, current: extraction.TextValidated) extraction.Error!Result {
    const classified = try @import("token_classification_validation.zig").validate(a, inputs, candidates, current);
    if (classified == .invalid) return .{ .token_classifications = classified.invalid };
    if (try validateCitations(a, inputs, classified.valid.text_validated)) |rejection| return .{ .source_selections = rejection };
    return .{ .valid = classified.valid };
}

fn validateCitations(a: std.mem.Allocator, inputs: evidence.Inputs, current: extraction.TextValidated) extraction.Error!?Rejection {
    if (current.revision == 0 or current.entries.len != inputs.chunks.entries.len) return error.InvalidReferenceExtraction;
    for (current.entries) |entry| {
        _ = try evidence.resolve(inputs, entry.scope);
        if (entry.outcome != .claims) continue;
        for (entry.outcome.claims, 0..) |claim, index| {
            switch (try selections.validate(a, inputs, entry.scope, claim.citations)) {
                .valid => |checked| a.free(checked.entries),
                .invalid => |issue| return .{ .scope = entry.scope, .revision = current.revision, .claim_index = index, .issue = issue, .origin = try claim.rejectionOrigin(issue) },
            }
        }
    }
    return null;
}
