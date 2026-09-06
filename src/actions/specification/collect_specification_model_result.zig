const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const session = @import("../../domain/specification_session.zig");
const identity = @import("../../domain/model_request_identity.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "collect-specification-model-result", .kind = .action, .requires = &.{ .specification_generation_session, .model_request_identity_ledger, .prepared_model_request, .model_input_packet, .model_payload_schema_result }, .produces = &.{.raw_specification_unit}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, current: session.Session, packet: *const @import("../../domain/model_input_packet.zig").Packet, body: []const u8) session.Error![]const u8 {
        const expected = try session.owner(allocator, current);
        if (!identity.unitOwnerEql(expected, packet.unit()) or packet.purpose() != .initial_generation) return error.InvalidSpecificationUnit;
        return allocator.dupe(u8, body);
    }
};
