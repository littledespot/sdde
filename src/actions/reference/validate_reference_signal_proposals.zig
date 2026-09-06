const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
const v = @import("../../domain/reference_reconciliation_validation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-signal-proposals", .kind = .action, .requires = &.{ .validated_reference_dispositions, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain }, .produces = &.{.validated_reference_signals}, .side_effect = .none };
    validator: r.text.Validator,
    pub fn execute(self: Action, allocator: std.mem.Allocator, prior: r.CheckedDispositions, context: v.TextContext) r.Error!r.CheckedSignals {
        const items = prior.input.progress.plan.layout.items;
        try v.bind(allocator, items, context, self.validator);
        const signals = try allocator.alloc(r.ValidatedSignal, prior.proposal.signals.len);
        const covered = try allocator.alloc(bool, items.entries.len);
        @memset(covered, false);
        const token_covered = try allocator.alloc(bool, items.entries.len);
        @memset(token_covered, false);
        for (prior.proposal.signals, signals, 0..) |proposal, *signal, index| {
            try v.claims(items, proposal.claim_ids, prior.input.partition.group.claim_ids);
            try v.citations(allocator, items, proposal.claim_ids, proposal.citation_ids);
            for (proposal.claim_ids) |id| {
                const disposition = try v.disposition(prior.dispositions, id);
                if (disposition.disposition == .conflicting) return error.InvalidReferenceReconciliation;
                covered[id.ordinal - 1] = true;
                if (proposal.content == .preserved_token) token_covered[id.ordinal - 1] = true;
            }
            signal.* = .{ .claim_ids = proposal.claim_ids, .citation_ids = proposal.citation_ids, .content = try v.content(allocator, self.validator, context, items, proposal.claim_ids, proposal.content) };
            for (signals[0..index]) |previous| {
                // One projection per identical claim set/kind. Distinct signals
                // may overlap when they carry different supported claim sets.
                if (sameMembers(previous.claim_ids, signal.claim_ids)) return error.InvalidReferenceReconciliation;
            }
        }
        for (prior.dispositions, items.entries, covered, token_covered) |disposition, item, present, token_present| {
            if (disposition.disposition == .retained and !present) return error.InvalidReferenceReconciliation;
            if (item.claim.content == .preserved_token and disposition.disposition != .conflicting and !token_present) return error.InvalidReferenceReconciliation;
        }
        return .{ .prior = prior, .signals = signals };
    }
};
fn sameMembers(a: []const r.ClaimId, b: []const r.ClaimId) bool {
    if (a.len != b.len) return false;
    for (a) |id| if (!r.contains(r.ClaimId, b, id)) return false;
    return true;
}
