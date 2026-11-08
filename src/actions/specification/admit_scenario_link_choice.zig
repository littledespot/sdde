const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const session = @import("../../domain/specification_session.zig");
const request = @import("../../domain/scenario_link_request.zig");
const link = @import("../../domain/scenario_link.zig");
const provenance = @import("../../domain/specification_provenance.zig");
const packets = @import("../../domain/model_input_packet.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "admit-scenario-link-choice", .kind = .action, .requires = &.{ .specification_generation_session, .scenario_link_progress, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .model_request_identity_ledger, .prepared_model_request, .model_input_packet, .model_payload_schema_result }, .produces = &.{}, .replaces = &.{.scenario_link_progress}, .side_effect = .none };

    /// The choices so far followed by the one the model's answer makes. The answer must be
    /// one of the criteria offered for the edge case that is next in the plan.
    pub fn execute(_: Action, allocator: std.mem.Allocator, current: session.Session, context: provenance.Context, chosen: []const link.Link, offered: *const packets.Packet, body: []const u8) request.Error![]const link.Link {
        const choice = try request.admit(allocator, current, context, chosen.len, offered, body);
        const next = try allocator.alloc(link.Link, chosen.len + 1);
        @memcpy(next[0..chosen.len], chosen);
        next[chosen.len] = choice;
        return next;
    }
};
