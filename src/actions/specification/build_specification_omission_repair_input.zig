const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/specification_coverage_repair.zig");
const sessions = @import("../../domain/specification_session.zig");
const p = @import("../../domain/specification_provenance.zig");
const spec = @import("../../domain/specification.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-specification-omission-repair-input", .kind = .action, .requires = &.{ .specification_generation_session, .identified_specification_content, .required_authority_inputs, .required_authority_observations, .required_authority_result, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .specification_omission_repair }, .produces = &.{.model_input_packet}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, current: sessions.Session, context: p.Context, candidate: spec.IdentifiedContent, support: repair.Support, authorization: repair.Authorization) repair.Error!*@import("../../domain/model_input_packet.zig").Packet {
        return repair.omissionPacket(a, current, context, candidate, support, authorization);
    }
};
