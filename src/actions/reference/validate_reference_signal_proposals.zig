const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
const v = @import("../../domain/reference_reconciliation_validation.zig");
const d = r.diagnostic;
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-signal-proposals", .kind = .action, .requires = &.{ .validated_reference_dispositions, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain }, .produces = &.{.validated_reference_signals}, .side_effect = .none };
    validator: r.text.Validator,
    pub fn execute(self: Action, allocator: std.mem.Allocator, prior: r.CheckedDispositions, context: v.TextContext) r.Error!d.Result(r.CheckedSignals) {
        var result = try v.checkSignals(allocator, self.validator, prior, context);
        if (result == .invalid) {
            const parsed: r.Parsed = .{ .source = prior.source, .input = prior.input, .proposal = .{ .global = prior.proposal } };
            result.invalid.relations = try v.relations(allocator, self.validator, context, parsed, prior.dispositions, result.invalid);
            result.invalid.dependencies = try @import("../../domain/reference_reconciliation_context.zig").snapshot(allocator, parsed, context);
        }
        return result;
    }
};
