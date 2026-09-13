const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
const v = @import("../../domain/reference_reconciliation_validation.zig");
const d = r.diagnostic;
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-conflict-proposals", .kind = .action, .requires = &.{ .validated_reference_signals, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain }, .produces = &.{.validated_reference_conflicts}, .side_effect = .none };
    validator: r.text.Validator,
    pub fn execute(self: Action, allocator: std.mem.Allocator, prior: r.CheckedSignals, context: v.TextContext) r.Error!d.Result(r.CheckedConflicts) {
        const items = prior.prior.input.progress.plan.layout.items;
        try v.input(allocator, prior.prior.input);
        try v.bind(allocator, items, context, self.validator);
        const conflicts = try allocator.alloc(r.ValidatedConflict, prior.prior.proposal.conflicts.len);
        const covered = try allocator.alloc(bool, items.entries.len);
        @memset(covered, false);
        for (prior.prior.proposal.conflicts, conflicts, 0..) |proposal, *conflict, index| {
            if (proposal.claim_ids.len < 2) return d.reject(r.CheckedConflicts, prior.prior.input, prior.prior.source, .{ .conflict = index }, .{ .rule = .cardinality, .observed = .{ .count = proposal.claim_ids.len }, .expected = .{ .constraint = .at_least_two } });
            if (v.claims(items, proposal.claim_ids, prior.prior.input.partition.group.claim_ids)) |issue| return d.reject(r.CheckedConflicts, prior.prior.input, prior.prior.source, .{ .conflict = index }, issue);
            if (try v.citations(allocator, items, proposal.claim_ids, proposal.citation_ids)) |issue| return d.reject(r.CheckedConflicts, prior.prior.input, prior.prior.source, .{ .conflict = index }, issue);
            for (proposal.claim_ids) |id| {
                const disposition = try v.disposition(prior.prior.dispositions, id);
                if (disposition.disposition != .conflicting) return d.reject(r.CheckedConflicts, prior.prior.input, prior.prior.source, .{ .conflict = index }, .{ .rule = .relationship, .observed = .{ .claims = proposal.claim_ids }, .expected = .{ .constraint = .conflicting_related_claims } });
                for (proposal.claim_ids) |other| if (other.ordinal != id.ordinal and !r.contains(r.ClaimId, disposition.related_claim_ids, other)) return d.reject(r.CheckedConflicts, prior.prior.input, prior.prior.source, .{ .conflict = index }, .{ .rule = .relationship, .observed = .{ .claims = proposal.claim_ids }, .expected = .{ .constraint = .conflicting_related_claims } });
                covered[id.ordinal - 1] = true;
            }
            for (prior.prior.proposal.conflicts[0..index]) |previous| {
                if (previous.kind != proposal.kind or previous.claim_ids.len != proposal.claim_ids.len) continue;
                for (previous.claim_ids) |id| {
                    if (!r.contains(r.ClaimId, proposal.claim_ids, id)) break;
                } else return d.reject(r.CheckedConflicts, prior.prior.input, prior.prior.source, .{ .conflict = index }, .{ .rule = .duplicate_conflict, .observed = .{ .claims = proposal.claim_ids }, .expected = .{ .constraint = .unique_members } });
            }
            conflict.* = .{ .claim_ids = proposal.claim_ids, .citation_ids = proposal.citation_ids, .kind = proposal.kind, .summary = self.validator.referenceIn(allocator, try v.scopes(allocator, items, proposal.claim_ids, context), proposal.summary) catch |err| return d.reject(r.CheckedConflicts, prior.prior.input, prior.prior.source, .{ .conflict = index }, try d.textFailure(err, .{ .text = proposal.summary })), .resolution = .unresolved };
        }
        for (prior.prior.dispositions, covered) |disposition, present| {
            if ((disposition.disposition == .conflicting) != present) return d.reject(r.CheckedConflicts, prior.prior.input, prior.prior.source, .conflicts, .{ .rule = .conflict_coverage, .observed = .{ .disposition = disposition }, .expected = .{ .constraint = .conflict_claim_covered } });
            if (!present) continue;
            for (disposition.related_claim_ids) |related| {
                for (conflicts) |conflict| {
                    if (r.contains(r.ClaimId, conflict.claim_ids, disposition.claim_id) and r.contains(r.ClaimId, conflict.claim_ids, related)) break;
                } else return d.reject(r.CheckedConflicts, prior.prior.input, prior.prior.source, .conflicts, .{ .rule = .conflict_coverage, .observed = .{ .disposition = disposition }, .expected = .{ .constraint = .conflict_pair_covered } });
            }
        }
        return .{ .valid = .{ .prior = prior, .conflicts = conflicts } };
    }
};
