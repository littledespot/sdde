const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/specification_repair.zig");
const session = @import("../../domain/specification_session.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "parse-specification-repair", .kind = .action, .requires = &.{ .specification_repair_authorization, .model_input_packet, .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .model_payload_schema_result }, .produces = &.{.specification_repair_result}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, authorization: repair.Authorization, packet: *const @import("../../domain/model_input_packet.zig").Packet, body: []const u8) repair.Error!repair.Replacement {
        return repair.parse(allocator, authorization, packet, body);
    }
};
