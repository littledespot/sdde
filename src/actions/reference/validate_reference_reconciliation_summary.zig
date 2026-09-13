const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
const validation = @import("../../domain/reference_reconciliation_validation.zig");
const d = r.diagnostic;
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-reconciliation-summary", .kind = .action, .requires = &.{ .parsed_reference_reconciliation, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain }, .produces = &.{.validated_reference_summary}, .side_effect = .none };
    validator: r.text.Validator,
    pub fn execute(self: Action, allocator: std.mem.Allocator, parsed: r.Parsed, context: validation.TextContext) r.Error!d.Result(r.CheckedSummary) {
        if (parsed.input.purpose != .summary or parsed.proposal != .summary) return error.InvalidReferenceReconciliation;
        try validation.input(allocator, parsed.input);
        if (parsed.source.revision == 0) return error.InvalidReferenceReconciliation;
        try validation.bind(allocator, parsed.input.progress.plan.layout.items, context, self.validator);
        const proposal = parsed.proposal.summary;
        const statements = try allocator.alloc(r.ValidatedStatement, proposal.statements.len);
        var represented: std.ArrayList(r.ClaimId) = .empty;
        for (proposal.statements, statements, 0..) |statement, *result, index| {
            if (statement.local_key == 0) return d.reject(r.CheckedSummary, parsed.input, parsed.source, .{ .statement = index }, .{ .rule = .local_key, .observed = .{ .count = statement.local_key }, .expected = .{ .constraint = .unique_nonzero } });
            for (proposal.statements[0..index]) |prior| if (prior.local_key == statement.local_key) return d.reject(r.CheckedSummary, parsed.input, parsed.source, .{ .statement = index }, .{ .rule = .local_key, .observed = .{ .count = statement.local_key }, .expected = .{ .constraint = .unique_nonzero } });
            if (validation.claims(parsed.input.progress.plan.layout.items, statement.claim_ids, parsed.input.partition.group.claim_ids)) |issue| return d.reject(r.CheckedSummary, parsed.input, parsed.source, .{ .statement = index }, issue);
            try represented.appendSlice(allocator, statement.claim_ids);
            result.* = .{ .local_key = statement.local_key, .claim_ids = statement.claim_ids, .content = switch (try validation.content(allocator, self.validator, context, parsed.input.progress.plan.layout.items, statement.claim_ids, statement.content)) {
                .valid => |value| value,
                .invalid => |issue| return d.reject(r.CheckedSummary, parsed.input, parsed.source, .{ .statement = index }, issue),
            } };
        }
        r.sameSet(r.ClaimId, represented.items, parsed.input.partition.group.claim_ids) catch return d.reject(r.CheckedSummary, parsed.input, parsed.source, .summary, .{ .rule = .membership, .observed = .{ .claims = represented.items }, .expected = .{ .claims = parsed.input.partition.group.claim_ids } });
        std.mem.sort(r.ValidatedStatement, statements, {}, struct {
            fn less(_: void, a: r.ValidatedStatement, b: r.ValidatedStatement) bool {
                return a.local_key < b.local_key;
            }
        }.less);
        return .{ .valid = .{ .input = parsed.input, .statements = statements } };
    }
};
