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
        const covered = try allocator.alloc(bool, items.entries.len);
        @memset(covered, false);
        const token_covered = try allocator.alloc(bool, items.entries.len);
        @memset(token_covered, false);
        for (prior.proposal.signals, signals, 0..) |proposal, *signal, index| {
            if (v.claims(items, proposal.claim_ids, prior.input.partition.group.claim_ids)) |issue| return d.reject(r.CheckedSignals, prior.input, prior.source, .{ .signal = index }, issue);
            for (proposal.claim_ids) |id| {
                if (!try v.signalEligible(prior.dispositions, id)) return d.reject(r.CheckedSignals, prior.input, prior.source, .{ .signal = index }, .{ .rule = .relationship, .observed = .{ .claims = proposal.claim_ids }, .expected = .{ .constraint = .nonconflicting_claims } });
                covered[id.ordinal - 1] = true;
                if (proposal.content == .preserved_token) token_covered[id.ordinal - 1] = true;
            }
            signal.* = .{ .claim_ids = proposal.claim_ids, .citation_ids = try r.citationUnion(allocator, items, proposal.claim_ids), .content = switch (try v.content(allocator, self.validator, context, items, proposal.claim_ids, proposal.content)) {
                .valid => |value| value,
                .invalid => |issue| return d.reject(r.CheckedSignals, prior.input, prior.source, .{ .signal = index }, issue),
            } };
            if (!v.signalSelectionAvailable(prior.proposal.signals[0..index], index, proposal.claim_ids)) return d.reject(r.CheckedSignals, prior.input, prior.source, .{ .signal = index }, .{ .rule = .duplicate_signal, .observed = .{ .claims = proposal.claim_ids }, .expected = .{ .constraint = .unique_members } });
        }
        for (prior.dispositions, items.entries, covered, token_covered) |disposition, item, present, token_present| {
            if (disposition.disposition == .retained and !present) return d.reject(r.CheckedSignals, prior.input, prior.source, .signals, .{ .rule = .signal_coverage, .observed = .{ .disposition = disposition }, .expected = .{ .constraint = .retained_claim_covered } });
            if (item.claim.content == .preserved_token and disposition.disposition != .conflicting and !token_present) return d.reject(r.CheckedSignals, prior.input, prior.source, .signals, .{ .rule = .signal_coverage, .observed = .{ .disposition = disposition }, .expected = .{ .constraint = .token_projected } });
        }
        return .{ .valid = .{ .prior = prior, .signals = signals } };
    }
};
