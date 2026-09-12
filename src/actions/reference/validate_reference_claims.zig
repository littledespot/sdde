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
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: evidence.Inputs, parsed: extraction.Prepared) extraction.Error!extraction.Validation {
        if (parsed.revision == 0 or parsed.entries.len != inputs.chunks.entries.len) return error.InvalidReferenceExtraction;
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
                    for (proposals, values, 0..) |proposal, *value, claim_index| {
                        const checked = switch (proposal) {
                            .model => |claim| switch (try @import("../../domain/source_selections.zig").validate(allocator, inputs, candidate.scope, claim.citations)) {
                                .valid => |result| result,
                                .invalid => |issue| return .{ .invalid = .{ .scope = candidate.scope, .revision = parsed.revision, .claim_index = claim_index, .issue = issue, .origin = try claim.rejectionOrigin(issue) } },
                            },
                            .preserved_token => |token| try citations.validate(allocator, inputs, .{ .scope = candidate.scope, .entries = &.{.{ .source_id = token.citation.source_id, .block_id = token.citation.block_id, .location = token.citation.location, .verbatim = token.citation.verbatim }} }),
                        };
                        // The returned pipeline value retains parsed candidates,
                        // not the independently owned captured-input allocation.
                        const owned = try allocator.alloc(evidence.ValidatedCitation, checked.entries.len);
                        for (checked.entries, owned) |citation, *copy| {
                            copy.* = citation;
                            if (citation.verbatim) |bytes| copy.verbatim = try allocator.dupe(u8, bytes);
                        }
                        allocator.free(checked.entries);
                        value.* = .{ .content = switch (proposal) {
                            .model => |claim| .{ .model = claim.content },
                            .preserved_token => |token| .{ .preserved_token = token.value },
                        }, .citations = owned };
                    }
                    break :claims .{ .claims = values };
                },
            };
        }
        return .{ .valid = .{ .state_id = if (entries.len == 0) .{ .bytes = try allocator.dupe(u8, inputs.corpus.state_id.bytes) } else entries[0].scope.state_id, .entries = entries } };
    }
};
