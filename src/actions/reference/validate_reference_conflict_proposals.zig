const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
const v = @import("../../domain/reference_reconciliation_validation.zig");
const d = r.diagnostic;
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-conflict-proposals", .kind = .action, .requires = &.{ .validated_reference_roles, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain }, .produces = &.{.validated_reference_conflicts}, .side_effect = .none };
    validator: r.text.Validator,
    pub fn execute(self: Action, allocator: std.mem.Allocator, prior: r.CheckedSignals, context: v.TextContext) r.Error!d.Result(r.CheckedConflicts) {
        if (prior.prior.phase != .complete) return error.InvalidReferenceReconciliation;
        var result = try self.check(allocator, prior, context);
        if (result == .invalid) {
            const parsed: r.Parsed = .{ .phase = prior.prior.phase, .source = prior.prior.source, .input = prior.prior.input, .proposal = .{ .global = prior.prior.proposal } };
            result.invalid.relations = try v.relations(allocator, self.validator, context, parsed, prior.prior.dispositions, result.invalid);
            result.invalid.dependencies = try @import("../../domain/reference_reconciliation_context.zig").snapshot(allocator, parsed, context);
        }
        return result;
    }
    fn check(self: Action, allocator: std.mem.Allocator, prior: r.CheckedSignals, context: v.TextContext) r.Error!d.Result(r.CheckedConflicts) {
        const items = prior.prior.input.progress.plan.layout.items;
        try v.input(allocator, prior.prior.input);
        try v.bind(allocator, items, context, self.validator);
        const conflicts = try allocator.alloc(r.ValidatedConflict, prior.prior.proposal.conflicts.len);
        for (conflicts, 0..) |*conflict, index| {
            conflict.* = switch (try v.checkConflict(allocator, self.validator, context, prior.prior, index)) {
                .valid => |value| value,
                .invalid => |issue| return d.reject(r.CheckedConflicts, prior.prior.input, prior.prior.source, .{ .conflict = index }, issue),
            };
            if (prior.prior.proposal.conflict_groups.len > 0) {
                for (prior.prior.proposal.conflict_groups) |group| {
                    if (v.sameMembers(group.claim_ids, conflict.claim_ids)) break;
                } else return d.reject(r.CheckedConflicts, prior.prior.input, prior.prior.source, .{ .conflict = index }, .{ .rule = .relationship, .observed = .{ .claims = conflict.claim_ids }, .expected = .{ .constraint = .conflicting_related_claims } });
            }
        }
        for (prior.prior.proposal.conflict_groups) |group| {
            for (prior.prior.proposal.conflicts) |conflict| {
                if (v.sameMembers(group.claim_ids, conflict.claim_ids)) break;
            } else return d.reject(r.CheckedConflicts, prior.prior.input, prior.prior.source, .conflicts, .{ .rule = .conflict_coverage, .observed = .{ .claims = group.claim_ids }, .expected = .{ .constraint = .conflict_claim_covered } });
        }
        if (try v.conflictCoverage(allocator, items, prior.prior.dispositions, prior.prior.proposal.conflicts)) |issue| return d.reject(r.CheckedConflicts, prior.prior.input, prior.prior.source, .conflicts, issue);
        return .{ .valid = .{ .prior = prior, .conflicts = conflicts } };
    }
};
