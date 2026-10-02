//! Validate one semantic authoring-role projection against fixed signal groups.
const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
const v = @import("../../domain/reference_reconciliation_validation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-role-assignments", .kind = .action, .requires = &.{.validated_reference_signals}, .produces = &.{.validated_reference_roles}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, prior: r.CheckedSignals) r.Error!r.diagnostic.Result(r.CheckedSignals) {
        return v.checkRoles(allocator, prior);
    }
};
