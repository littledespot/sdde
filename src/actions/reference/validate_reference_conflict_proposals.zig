const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
const v = @import("../../domain/reference_reconciliation_validation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-conflict-proposals", .kind = .action, .requires = &.{ .validated_reference_signals, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain }, .produces = &.{.validated_reference_conflicts}, .side_effect = .none };
    validator: r.text.Validator,
    pub fn execute(self: Action, allocator: std.mem.Allocator, prior: r.CheckedSignals, context: v.TextContext) r.Error!r.CheckedConflicts {
        const items = prior.prior.input.progress.plan.layout.items;
        try v.bind(allocator, items, context, self.validator);
        const conflicts = try allocator.alloc(r.ValidatedConflict, prior.prior.proposal.conflicts.len);
        const covered = try allocator.alloc(bool, items.entries.len);
        @memset(covered, false);
        for (prior.prior.proposal.conflicts, conflicts) |proposal, *conflict| {
            if (proposal.claim_ids.len < 2) return error.InvalidReferenceReconciliation;
            try v.claims(items, proposal.claim_ids, prior.prior.input.partition.group.claim_ids);
            try v.citations(allocator, items, proposal.claim_ids, proposal.citation_ids);
            for (proposal.claim_ids) |id| {
                const disposition = try v.disposition(prior.prior.dispositions, id);
                if (disposition.disposition != .conflicting or covered[id.ordinal - 1] or disposition.related_claim_ids.len + 1 != proposal.claim_ids.len) return error.InvalidReferenceReconciliation;
                for (disposition.related_claim_ids) |related| if (!r.contains(r.ClaimId, proposal.claim_ids, related)) return error.InvalidReferenceReconciliation;
                covered[id.ordinal - 1] = true;
            }
            conflict.* = .{ .claim_ids = proposal.claim_ids, .citation_ids = proposal.citation_ids, .kind = proposal.kind, .summary = try self.validator.referenceIn(allocator, try v.scopes(allocator, items, proposal.claim_ids, context), proposal.summary), .resolution = .unresolved };
        }
        for (prior.prior.dispositions, covered) |disposition, present| if ((disposition.disposition == .conflicting) != present) return error.InvalidReferenceReconciliation;
        return .{ .prior = prior, .conflicts = conflicts };
    }
};
