const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/specification_coverage_repair.zig");
const sessions = @import("../../domain/specification_session.zig");
const p = @import("../../domain/specification_provenance.zig");
const spec = @import("../../domain/specification.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "parse-specification-omission-repair", .kind = .action, .requires = &.{ .specification_omission_repair, .model_request_identity_ledger, .prepared_model_request, .model_input_packet, .model_payload_schema_result }, .produces = &.{}, .replaces = &.{.specification_omission_repair}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, authorization: repair.Authorization, packet: *const @import("../../domain/model_input_packet.zig").Packet, bytes: []const u8) repair.Error!repair.Replacement {
        return repair.parseOmission(a, authorization, packet, bytes);
    }
};
