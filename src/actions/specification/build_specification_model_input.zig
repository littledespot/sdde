const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const session = @import("../../domain/specification_session.zig");
const packets = @import("../../domain/model_input_packet.zig");
const principle_context = @import("../../domain/specification_principles.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-specification-model-input", .kind = .action, .requires = &.{ .specification_generation_session, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .packet_guidance, .principle_registry }, .produces = &.{.model_input_packet}, .side_effect = .none };
    /// The request of the unit in flight: a brief, entities or records unit, or while scenarios are
    /// written (ADR 0038 Decision 3), the numbered slots of the next group. The records request
    /// also carries the project's principles (D17.1).
    pub fn execute(_: Action, allocator: std.mem.Allocator, current: session.Session, context: @import("../../domain/specification_provenance.zig").Context, guidance: *const @import("../../domain/packet_guidance.zig").Guidance, principles: @import("../../domain/principle_registry.zig").Registry) @import("../../domain/scenario_request.zig").Error!*packets.Packet {
        if (session.scenarioPhase(current)) return @import("../../domain/scenario_request.zig").packet(allocator, current, context, guidance);
        const base = try session.packet(allocator, current, context, guidance);
        if (!principle_context.carried(current, principles)) return base;
        defer packets.release(base);
        return principle_context.carry(allocator, base, principles);
    }
};
