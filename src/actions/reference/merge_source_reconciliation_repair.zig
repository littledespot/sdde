const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const loss = @import("../../domain/source_omission.zig");
const rec = @import("../../domain/reference_reconciliation_repair.zig").Omission;
const r = @import("../../domain/reference_reconciliation.zig");
const Context = @import("../../domain/reference_reconciliation_validation.zig").TextContext;
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "merge-source-reconciliation-repair", .kind = .action, .requires = &loss.reconciliation_requires, .produces = &.{}, .replaces = &.{.parsed_reference_reconciliation}, .invalidates = &loss.reconciliation_dependents, .side_effect = .none };
    pub fn execute(_: @This(), a: std.mem.Allocator, parsed: r.Parsed, ctx: Context, support: loss.Support, repair: loss.Repair) rec.Error!r.Parsed {
        const response = repair.response orelse return error.InvalidAtomicRepair;
        if (repair.authorization != .reconciliation or response.value != .reconciliation) return error.InvalidAtomicRepair;
        return rec.merge(a, parsed, ctx, support, repair.authorization.reconciliation, response.value.reconciliation, response.origin);
    }
};
