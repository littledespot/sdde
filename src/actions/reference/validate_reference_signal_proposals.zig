const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
const v = @import("../../domain/reference_reconciliation_validation.zig");
const d = r.diagnostic;
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-signal-proposals", .kind = .action, .requires = &.{ .validated_reference_dispositions, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain }, .produces = &.{.validated_reference_signals}, .side_effect = .none };
    validator: r.text.Validator,
    pub fn execute(self: Action, allocator: std.mem.Allocator, prior: r.CheckedDispositions, context: v.TextContext) r.Error!d.Result(r.CheckedSignals) {
        var result = try self.check(allocator, prior, context);
        if (result == .invalid) {
            const parsed: r.Parsed = .{ .source = prior.source, .input = prior.input, .proposal = .{ .global = prior.proposal } };
            result.invalid.relations = try v.relations(allocator, self.validator, context, parsed, prior.dispositions, result.invalid);
            result.invalid.dependencies = try @import("../../domain/reference_reconciliation_context.zig").snapshot(allocator, parsed, context);
        }
        return result;
    }
    fn check(self: Action, allocator: std.mem.Allocator, prior: r.CheckedDispositions, context: v.TextContext) r.Error!d.Result(r.CheckedSignals) {
        const items = prior.input.progress.plan.layout.items;
        try v.input(allocator, prior.input);
        try v.bind(allocator, items, context, self.validator);
        const signals = try allocator.alloc(r.ValidatedSignal, prior.proposal.signals.len);
        for (prior.proposal.signals, signals, 0..) |proposal, *signal, index| {
            if (try v.signalClaims(items, prior.dispositions, proposal.claim_ids, prior.input.partition.group.claim_ids)) |issue| return d.reject(r.CheckedSignals, prior.input, prior.source, .{ .signal = index }, issue);
            signal.* = .{ .claim_ids = proposal.claim_ids, .citation_ids = try r.citationUnion(allocator, items, proposal.claim_ids), .content = switch (try v.content(allocator, self.validator, context, items, proposal.claim_ids, proposal.content)) {
                .valid => |value| value,
                .invalid => |issue| return d.reject(r.CheckedSignals, prior.input, prior.source, .{ .signal = index }, issue),
            } };
            if (!v.signalSelectionAvailable(prior.proposal.signals[0..index], index, proposal.claim_ids)) return d.reject(r.CheckedSignals, prior.input, prior.source, .{ .signal = index }, .{ .rule = .duplicate_signal, .observed = .{ .claims = proposal.claim_ids }, .expected = .{ .constraint = .unique_members } });
        }
        if (try v.signalCoverage(allocator, items, prior.dispositions, prior.proposal.signals)) |issue| return d.reject(r.CheckedSignals, prior.input, prior.source, .signals, issue);
        return .{ .valid = .{ .prior = prior, .signals = signals } };
    }
};
