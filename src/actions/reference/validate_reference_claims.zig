const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const evidence = @import("../../domain/reference_evidence.zig");
const extraction = @import("../../domain/reference_extraction.zig");
const citations = @import("../../domain/source_citations.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-reference-claims",
        .kind = .action,
        .requires = &.{ .citable_reference_inputs, .prepared_reference_claims },
        .produces = &.{.validated_reference_claims},
        .side_effect = .none,
    };
    /// Structural validation only. Results are ordered by engine chunk order;
    /// model response arrival order cannot change canonical ID assignment.
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: evidence.Inputs, parsed: extraction.Prepared) extraction.Error!extraction.Validated {
        if (parsed.entries.len != inputs.chunks.entries.len) return error.InvalidReferenceExtraction;
        const entries = try allocator.alloc(extraction.ValidatedResult, parsed.entries.len);
        for (inputs.chunks.entries, parsed.entries, entries) |chunk, candidate, *entry| {
            if (!candidate.scope.state_id.eql(inputs.corpus.state_id) or !candidate.scope.chunk_id.eql(chunk.id)) return error.InvalidReferenceExtraction;
            _ = try evidence.resolve(inputs, candidate.scope);
            entry.scope = candidate.scope;
            entry.outcome = switch (candidate.outcome) {
                .blocked => |reason| .{ .blocked = reason },
                .no_feature_claim => |reason| .{ .no_feature_claim = reason },
                .claims => |proposals| claims: {
                    if (proposals.len == 0) return error.InvalidReferenceExtraction;
                    const values = try allocator.alloc(extraction.ValidatedClaim, proposals.len);
                    for (proposals, values) |proposal, *value| {
                        const checked = try citations.validate(allocator, inputs, .{ .scope = candidate.scope, .entries = proposal.citations });
                        // The returned pipeline value retains parsed candidates,
                        // not the independently owned captured-input allocation.
                        const owned = try allocator.alloc(evidence.ValidatedCitation, checked.entries.len);
                        for (checked.entries, owned) |citation, *copy| {
                            copy.* = citation;
                            if (citation.verbatim) |bytes| copy.verbatim = try allocator.dupe(u8, bytes);
                        }
                        allocator.free(checked.entries);
                        value.* = .{ .content = proposal.content, .citations = owned };
                    }
                    break :claims .{ .claims = values };
                },
            };
        }
        return .{ .state_id = if (entries.len == 0) .{ .bytes = try allocator.dupe(u8, inputs.corpus.state_id.bytes) } else entries[0].scope.state_id, .entries = entries };
    }
};
