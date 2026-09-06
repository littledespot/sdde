const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "assign-reference-reconciliation-identities", .kind = .action, .requires = &.{.validated_reference_conflicts}, .produces = &.{.reference_reconciliation_identities}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, checked: r.CheckedConflicts) r.Error!r.RecordAssignments {
        const signals = try allocator.alloc(r.SignalId, checked.prior.signals.len);
        const conflicts = try allocator.alloc(r.ConflictId, checked.conflicts.len);
        for (signals, 0..) |*id, index| id.* = .{ .ordinal = try r.ordinal(index) };
        for (conflicts, 0..) |*id, index| id.* = .{ .ordinal = try r.ordinal(index) };
        return .{ .checked = checked, .signal_ids = signals, .conflict_ids = conflicts };
    }
};
