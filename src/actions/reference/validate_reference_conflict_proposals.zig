const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
const v = @import("../../domain/reference_reconciliation_validation.zig");
const d = r.diagnostic;
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-conflict-proposals", .kind = .action, .requires = &.{ .validated_reference_signals, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain }, .produces = &.{.validated_reference_conflicts}, .side_effect = .none };
    validator: r.text.Validator,
    pub fn execute(self: Action, allocator: std.mem.Allocator, prior: r.CheckedSignals, context: v.TextContext) r.Error!d.Result(r.CheckedConflicts) {
        var result = try self.check(allocator, prior, context);
        if (result == .invalid) {
            const parsed: r.Parsed = .{ .source = prior.prior.source, .input = prior.prior.input, .proposal = .{ .global = prior.prior.proposal } };
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
        for (prior.prior.proposal.conflicts, conflicts, 0..) |proposal, *conflict, index| {
            if (try v.conflictClaims(items, prior.prior.dispositions, proposal.claim_ids, prior.prior.input.partition.group.claim_ids)) |issue| return d.reject(r.CheckedConflicts, prior.prior.input, prior.prior.source, .{ .conflict = index }, issue);
            if (!v.conflictSelectionAvailable(prior.prior.proposal.conflicts[0..index], index, proposal.kind, proposal.claim_ids)) return d.reject(r.CheckedConflicts, prior.prior.input, prior.prior.source, .{ .conflict = index }, .{ .rule = .duplicate_conflict, .observed = .{ .claims = proposal.claim_ids }, .expected = .{ .constraint = .unique_members } });
            conflict.* = .{ .claim_ids = proposal.claim_ids, .citation_ids = try r.citationUnion(allocator, items, proposal.claim_ids), .kind = proposal.kind, .summary = switch (try self.validator.checkReferenceIn(allocator, try v.scopes(allocator, items, proposal.claim_ids, context), proposal.summary)) {
                .valid => |checked| checked,
                .invalid => |issue| return d.reject(r.CheckedConflicts, prior.prior.input, prior.prior.source, .{ .conflict = index }, d.textFailure(issue, .{ .text = proposal.summary })),
            }, .resolution = .unresolved };
        }
        if (try v.conflictCoverage(allocator, items, prior.prior.dispositions, prior.prior.proposal.conflicts)) |issue| return d.reject(r.CheckedConflicts, prior.prior.input, prior.prior.source, .conflicts, issue);
        return .{ .valid = .{ .prior = prior, .conflicts = conflicts } };
    }
};
