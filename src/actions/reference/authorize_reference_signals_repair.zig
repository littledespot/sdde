const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/reference_reconciliation_repair.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "authorize-reference-signals-repair",
        .kind = .action,
        .requires = &.{ .parsed_reference_reconciliation, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .validated_reference_signals },
        .produces = &.{.reference_reconciliation_repair},
        .invalidates = &.{ .validated_reference_dispositions, .validated_reference_signals },
        .side_effect = .none,
    };
    pub fn execute(_: Action, a: std.mem.Allocator, parsed: r.Parsed, context: @import("../../domain/reference_reconciliation_validation.zig").TextContext, rejection: r.diagnostic.Rejection) repair.Error!repair.Decision {
        return repair.authorize(a, parsed, context, rejection);
    }
};
