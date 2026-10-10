const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
const v = @import("../../domain/reference_reconciliation_validation.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "reuse-reference-reconciliation-summary", .kind = .action, .requires = &.{ .reference_reconciliation_input, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain }, .produces = &.{.parsed_reference_reconciliation}, .side_effect = .none };
    validator: r.text.Validator,

    pub fn execute(self: Action, a: std.mem.Allocator, input: r.Input, context: v.TextContext) r.Error!r.Parsed {
        const child = (try v.reusableSummary(a, self.validator, input, context)) orelse return error.InvalidReferenceReconciliation;
        const statements = try a.alloc(r.StatementProposal, child.statements.len);
        for (child.statements, statements) |prior, *statement| statement.* = .{ .claim_ids = prior.claim_ids, .content = @import("../../domain/model_evidence.zig").content(prior.content) };
        return .{ .input = input, .proposal = .{ .summary = .{ .statements = statements } }, .carried_from = child.id };
    }
};
