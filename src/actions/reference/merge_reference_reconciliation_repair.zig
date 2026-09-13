const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/reference_reconciliation_repair.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "merge-reference-reconciliation-repair", .kind = .action, .requires = &.{ .parsed_reference_reconciliation, .reference_reconciliation_repair, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain }, .produces = &.{}, .replaces = &.{.parsed_reference_reconciliation}, .invalidates = &.{.reference_reconciliation_repair}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, parsed: r.Parsed, context: @import("../../domain/reference_reconciliation_validation.zig").TextContext, authorization: repair.Authorization, replacement: ?repair.Replacement, origin: ?@import("../../domain/model_candidate_origin.zig").Origin) repair.Error!r.Parsed {
        return repair.merge(a, parsed, context, authorization, replacement, origin);
    }
};
