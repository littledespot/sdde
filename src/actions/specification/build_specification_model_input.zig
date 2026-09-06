const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const session = @import("../../domain/specification_session.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-specification-model-input", .kind = .action, .requires = &.{ .specification_generation_session, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain }, .produces = &.{.model_input_packet}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, current: session.Session, context: @import("../../domain/specification_provenance.zig").Context) session.Error!*@import("../../domain/model_input_packet.zig").Packet {
        return session.packet(allocator, current, context);
    }
};
