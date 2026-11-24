const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
const v = @import("../../domain/reference_reconciliation_validation.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "check-reference-summary-reuse", .kind = .action, .requires = &.{ .reference_reconciliation_input, .citable_reference_inputs, .reference_passive_literals }, .produces = &.{}, .side_effect = .none };
    pub const Result = enum { reusable, semantic };

    pub fn execute(_: Action, a: std.mem.Allocator, input: r.Input, context: v.TextContext) r.Error!Result {
        return if (try v.reusableSummary(a, input, context) != null) .reusable else .semantic;
    }
};
