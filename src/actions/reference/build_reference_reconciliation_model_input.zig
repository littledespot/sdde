const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const inputs = @import("../../domain/reference_model_input.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-reference-reconciliation-model-input", .kind = .action, .requires = &.{ .reference_reconciliation_input, .citable_reference_inputs, .reference_passive_literals, .packet_guidance }, .produces = &.{.model_input_packet}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, input: @import("../../domain/reference_reconciliation.zig").Input, source: @import("../../domain/reference_evidence.zig").Inputs, registry: @import("../../domain/passive_literals.zig").Registry, guidance: *const @import("../../domain/packet_guidance.zig").Guidance) inputs.ReconciliationError!*@import("../../domain/model_input_packet.zig").Packet {
        return inputs.reconciliationCompositionPacket(allocator, input, source, registry, guidance.summary_purpose);
    }
};
