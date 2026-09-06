const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const extraction = @import("../../domain/reference_extraction.zig");
const tokens = extraction.tokens;
const evidence = @import("../../domain/reference_evidence.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-preserved-token-classifications", .kind = .action, .requires = &.{ .citable_reference_inputs, .structured_token_candidates, .text_validated_reference_extraction }, .produces = &.{.classified_reference_tokens}, .side_effect = .none };
    /// Complete classification of exactly the current chunk/candidate allowlists.
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: evidence.Inputs, candidates: tokens.Candidates, parsed: extraction.TextValidated) extraction.Error!extraction.Classified {
        try tokens.validateCandidates(allocator, inputs, candidates);
        if (parsed.entries.len != inputs.chunks.entries.len) return error.InvalidReferenceExtraction;
        const ordered = try allocator.alloc(extraction.TextValidatedResult, parsed.entries.len);
        const selections = try allocator.alloc(tokens.Selected, candidates.entries.len);
        var selection_index: usize = 0;
        for (inputs.chunks.entries, ordered) |chunk, *entry| {
            var selected: ?extraction.TextValidatedResult = null;
            for (parsed.entries) |candidate| {
                if (!candidate.scope.state_id.eql(inputs.corpus.state_id)) return error.InvalidReferenceExtraction;
                if (!candidate.scope.chunk_id.eql(chunk.id)) continue;
                if (selected != null) return error.InvalidReferenceExtraction;
                selected = candidate;
            }
            entry.* = selected orelse return error.InvalidReferenceExtraction;
            var classified_count: usize = 0;
            for (candidates.entries) |candidate| {
                if (!candidate.fact.scope.chunk_id.eql(chunk.id)) continue;
                var decision: ?tokens.Decision = if (entry.outcome == .blocked) .blocked else null;
                for (entry.token_classifications) |classification| {
                    if (!std.meta.eql(classification.id(), candidate.id)) continue;
                    if (decision != null) return error.InvalidStructuredTokens;
                    decision = switch (classification) {
                        .preserve => |value| .{ .preserve = value.kind },
                        .irrelevant => .irrelevant,
                    };
                    classified_count += 1;
                }
                selections[selection_index] = .{ .candidate = try tokens.copy(allocator, candidate), .decision = decision orelse return error.InvalidStructuredTokens };
                selection_index += 1;
            }
            if (classified_count != entry.token_classifications.len) return error.InvalidStructuredTokens;
        }
        if (selection_index != selections.len) return error.InvalidStructuredTokens;
        return .{ .text_validated = .{ .entries = ordered }, .selections = selections };
    }
};
