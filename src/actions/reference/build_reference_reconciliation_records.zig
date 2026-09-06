const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-reference-reconciliation-records", .kind = .action, .requires = &.{.reference_reconciliation_identities}, .produces = &.{.reference_reconciliation_records}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, assigned: r.RecordAssignments) r.Error!r.Records {
        if (assigned.signal_ids.len != assigned.checked.prior.signals.len or assigned.conflict_ids.len != assigned.checked.conflicts.len) return error.InvalidReferenceReconciliation;
        const signals = try allocator.alloc(r.Signal, assigned.signal_ids.len);
        const conflicts = try allocator.alloc(r.Conflict, assigned.conflict_ids.len);
        for (signals, assigned.signal_ids, assigned.checked.prior.signals) |*signal, id, value| signal.* = .{ .id = id, .value = value };
        for (conflicts, assigned.conflict_ids, assigned.checked.conflicts) |*conflict, id, value| conflict.* = .{ .id = id, .value = value };
        return .{ .assignments = assigned, .signals = signals, .conflicts = conflicts };
    }
};
