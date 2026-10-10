const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
const v = @import("../../domain/reference_reconciliation_validation.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "check-reference-summary-reuse", .kind = .action, .requires = &.{ .reference_reconciliation_input, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain }, .produces = &.{}, .side_effect = .none };
    pub const Result = enum { reusable, semantic };
    validator: r.text.Validator,

    pub fn execute(self: Action, a: std.mem.Allocator, input: r.Input, context: v.TextContext) r.Error!Result {
        return if (try v.reusableSummary(a, self.validator, input, context) != null) .reusable else .semantic;
    }
};
