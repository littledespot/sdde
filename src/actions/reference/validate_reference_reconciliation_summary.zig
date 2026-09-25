const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
const validation = @import("../../domain/reference_reconciliation_validation.zig");
const d = r.diagnostic;
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-reconciliation-summary", .kind = .action, .requires = &.{ .parsed_reference_reconciliation, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain }, .produces = &.{.validated_reference_summary}, .side_effect = .none };
    validator: r.text.Validator,
    pub fn execute(self: Action, allocator: std.mem.Allocator, parsed: r.Parsed, context: validation.TextContext) r.Error!d.Result(r.CheckedSummary) {
        var result = try validation.checkSummary(allocator, self.validator, parsed, context);
        if (result == .invalid) {
            result.invalid.relations = try validation.relations(allocator, self.validator, context, parsed, &.{}, result.invalid);
            result.invalid.dependencies = try @import("../../domain/reference_reconciliation_context.zig").snapshot(allocator, parsed, context);
        }
        return result;
    }
};
