const support = @import("../../domain/specification_support.zig");
const repair = @import("../../domain/specification_support_repair.zig");
const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "parse-specification-support-repair", .kind = .action, .requires = &.{ .specification_support_repair, .model_request_identity_ledger, .prepared_model_request, .model_input_packet, .model_payload_schema_result }, .produces = &.{}, .replaces = &.{.specification_support_repair}, .side_effect = .none };
    pub fn execute(_: Action, comptime purpose: support.Purpose, allocator: std.mem.Allocator, authorization: repair.Contract(purpose).Authorization, packet: *const @import("../../domain/model_input_packet.zig").Packet, bytes: []const u8) repair.Contract(purpose).Error!repair.Contract(purpose).Replacement {
        return repair.Contract(purpose).parse(allocator, authorization, packet, bytes);
    }
};
