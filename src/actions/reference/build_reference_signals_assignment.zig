const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const stage = @import("../../domain/reference_reconciliation_stage.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-reference-signals-assignment", .kind = .action, .requires = &.{ .validated_reference_dispositions, .citable_reference_inputs, .reference_passive_literals }, .produces = &.{.model_input_packet}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, prior: stage.Prior, inputs: r.evidence.Inputs, registry: @import("../../domain/passive_literals.zig").Registry) @import("../../domain/reference_model_input.zig").ReconciliationError!*@import("../../domain/model_input_packet.zig").Packet {
        if (prior != .signals) return error.InvalidReferenceReconciliation;
        return stage.packet(a, prior, inputs, registry);
    }
};
