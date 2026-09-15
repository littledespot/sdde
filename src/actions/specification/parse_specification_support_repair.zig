const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/specification_support_repair.zig");
const support = @import("../../domain/specification_support.zig");
const authority = @import("../../domain/required_authority.zig");
const p = @import("../../domain/specification_provenance.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "parse-specification-support-repair", .kind = .action, .requires = &.{ .specification_support_repair, .model_request_identity_ledger, .prepared_model_request, .model_input_packet, .model_payload_schema_result }, .produces = &.{}, .replaces = &.{.specification_support_repair}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, authorization: repair.Authorization, packet: *const @import("../../domain/model_input_packet.zig").Packet, bytes: []const u8) repair.Error!repair.Replacement {
        return repair.parse(allocator, authorization, packet, bytes);
    }
};
