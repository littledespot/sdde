const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const extraction = @import("../../domain/reference_extraction.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-preserved-token-claims", .kind = .action, .requires = &.{.preserved_token_identities}, .produces = &.{.prepared_reference_claims}, .side_effect = .none };
    /// Model and deterministic claims enter the same citation/identity pipeline.
    pub fn execute(_: Action, allocator: std.mem.Allocator, assigned: extraction.TokenAssignments) extraction.Error!extraction.Prepared {
        const entries = try allocator.alloc(extraction.PreparedResult, assigned.classified.text_validated.entries.len);
        for (assigned.classified.text_validated.entries, entries) |entry, *result| {
            var claims: std.ArrayList(extraction.PreparedClaim) = .empty;
            if (entry.outcome == .claims) for (entry.outcome.claims) |claim| try claims.append(allocator, .{ .model = claim });
            for (assigned.entries) |assignment| {
                if (assignment.selection_index >= assigned.classified.selections.len) return error.InvalidStructuredTokens;
                const selected = assigned.classified.selections[assignment.selection_index];
                if (!selected.candidate.fact.scope.chunk_id.eql(entry.scope.chunk_id)) continue;
                if (entry.outcome != .claims or selected.decision != .preserve) return error.InvalidStructuredTokens;
                const citation = selected.candidate.fact.citation;
                try claims.append(allocator, .{ .preserved_token = .{ .value = .{ .id = assignment.id, .candidate_id = selected.candidate.id, .kind = selected.decision.preserve, .raw_value = .{ .bytes = citation.verbatim.? }, .downstream_obligation_id = .{ .token_id = assignment.id } }, .citation = citation } });
            }
            result.* = .{ .scope = entry.scope, .outcome = switch (entry.outcome) {
                .claims => .{ .claims = try claims.toOwnedSlice(allocator) },
                .no_feature_claim => |reason| .{ .no_feature_claim = reason },
                .blocked => |reason| .{ .blocked = reason },
            } };
        }
        return .{ .revision = assigned.classified.text_validated.revision, .entries = entries };
    }
};
