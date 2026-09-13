const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/reference_extraction_text_repair.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "parse-reference-text-repair", .kind = .action, .requires = &.{ .reference_text_repair_authorization, .model_input_packet, .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .model_payload_schema_result }, .produces = &.{.reference_text_repair_result}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, authorization: repair.Authorization, packet: *const @import("../../domain/model_input_packet.zig").Packet, bytes: []const u8) repair.Error!repair.Replacement {
        return repair.parse(a, authorization, packet, bytes);
    }
};
