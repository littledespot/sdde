const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
const validation = @import("../../domain/reference_reconciliation_validation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-reconciliation-summary", .kind = .action, .requires = &.{ .parsed_reference_reconciliation, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain }, .produces = &.{.validated_reference_summary}, .side_effect = .none };
    validator: r.text.Validator,
    pub fn execute(self: Action, allocator: std.mem.Allocator, parsed: r.Parsed, context: validation.TextContext) r.Error!r.CheckedSummary {
        if (parsed.input.purpose != .summary or parsed.proposal != .summary) return error.InvalidReferenceReconciliation;
        try validation.bind(allocator, parsed.input.progress.plan.layout.items, context, self.validator);
        const proposal = parsed.proposal.summary;
        try r.sameSet(r.ClaimId, proposal.member_claim_ids, parsed.input.partition.group.claim_ids);
        try r.sameSet(r.SummaryId, proposal.member_summary_ids, parsed.input.member_summary_ids);
        const statements = try allocator.alloc(r.ValidatedStatement, proposal.statements.len);
        var represented: std.ArrayList(r.ClaimId) = .empty;
        for (proposal.statements, statements, 0..) |statement, *result, index| {
            if (statement.local_key == 0) return error.InvalidReferenceReconciliation;
            for (proposal.statements[0..index]) |prior| if (prior.local_key == statement.local_key) return error.InvalidReferenceReconciliation;
            try validation.claims(parsed.input.progress.plan.layout.items, statement.claim_ids, proposal.member_claim_ids);
            try represented.appendSlice(allocator, statement.claim_ids);
            result.* = .{ .local_key = statement.local_key, .claim_ids = statement.claim_ids, .content = try validation.content(allocator, self.validator, context, parsed.input.progress.plan.layout.items, statement.claim_ids, statement.content) };
        }
        try r.sameSet(r.ClaimId, represented.items, proposal.member_claim_ids);
        std.mem.sort(r.ValidatedStatement, statements, {}, struct {
            fn less(_: void, a: r.ValidatedStatement, b: r.ValidatedStatement) bool {
                return a.local_key < b.local_key;
            }
        }.less);
        return .{ .input = parsed.input, .statements = statements };
    }
};
