const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const session = @import("../../domain/specification_session.zig");
const request = @import("../../domain/scenario_link_request.zig");
const link = @import("../../domain/scenario_link.zig");
const provenance = @import("../../domain/specification_provenance.zig");
const packets = @import("../../domain/model_input_packet.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-scenario-link-input", .kind = .action, .requires = &.{ .specification_generation_session, .scenario_link_progress, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain }, .produces = &.{.model_input_packet}, .side_effect = .none };

    /// The request for the first pending edge case that has no choice yet.
    pub fn execute(_: Action, allocator: std.mem.Allocator, current: session.Session, context: provenance.Context, chosen: []const link.Link) request.Error!*packets.Packet {
        return request.packet(allocator, current, context, chosen.len);
    }
};
