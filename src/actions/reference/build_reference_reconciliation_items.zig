const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-reference-reconciliation-items", .kind = .action, .requires = &.{ .citable_reference_inputs, .accounted_reference_extraction }, .produces = &.{.reference_reconciliation_items}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: r.evidence.Inputs, accounted: r.extraction.Accounted) r.Error!r.Items {
        if (accounted.outcome != .complete or !inputs.corpus.state_id.eql(accounted.ledger.state_id)) return error.InvalidReferenceReconciliation;
        return @import("../../domain/reference_claim_items.zig").build(allocator, inputs, accounted.ledger);
    }
};
