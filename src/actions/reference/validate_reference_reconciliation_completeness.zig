const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-reconciliation-completeness", .kind = .action, .requires = &.{.reference_reconciliation_records}, .produces = &.{.accounted_reference_reconciliation}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, records: r.Records) r.Error!r.Accounted {
        const assigned = records.assignments;
        try @import("../../domain/reference_reconciliation_validation.zig").history(allocator, assigned.checked.prior.prior.input.progress);
        if (records.signals.len != assigned.signal_ids.len or records.signals.len != assigned.checked.prior.signals.len or records.conflicts.len != assigned.conflict_ids.len or records.conflicts.len != assigned.checked.conflicts.len) return error.InvalidReferenceReconciliation;
        for (records.signals, assigned.signal_ids, assigned.checked.prior.signals, 1..) |signal, id, value, ordinal| {
            if (signal.id.ordinal != ordinal or signal.id.ordinal != id.ordinal or !std.meta.eql(signal.value, value)) return error.InvalidReferenceReconciliation;
        }
        for (records.conflicts, assigned.conflict_ids, assigned.checked.conflicts, 1..) |conflict, id, value, ordinal| {
            if (conflict.id.ordinal != ordinal or conflict.id.ordinal != id.ordinal or !std.meta.eql(conflict.value, value)) return error.InvalidReferenceReconciliation;
        }
        return .{ .records = records, .outcome = if (records.conflicts.len == 0) .complete else .blocked };
    }
};
