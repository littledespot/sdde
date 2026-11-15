const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const session = @import("../../domain/specification_session.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-specification-model-input", .kind = .action, .requires = &.{ .specification_generation_session, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .packet_guidance }, .produces = &.{.model_input_packet}, .side_effect = .none };
    /// The request of the unit in flight: a brief, entities or records unit, or while scenarios are
    /// written (ADR 0038 Decision 3), the numbered slots of the next group.
    pub fn execute(_: Action, allocator: std.mem.Allocator, current: session.Session, context: @import("../../domain/specification_provenance.zig").Context, guidance: *const @import("../../domain/packet_guidance.zig").Guidance) @import("../../domain/scenario_request.zig").Error!*@import("../../domain/model_input_packet.zig").Packet {
        if (session.scenarioPhase(current)) return @import("../../domain/scenario_request.zig").packet(allocator, current, context, guidance);
        return session.packet(allocator, current, context, guidance);
    }
};
