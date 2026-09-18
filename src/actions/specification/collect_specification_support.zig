const support = @import("../../domain/specification_support.zig");
const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "collect-specification-support", .kind = .action, .requires = &.{ .required_authority_inputs, .specification_support_review, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .model_request_identity_ledger, .prepared_model_request, .model_input_packet, .model_payload_schema_result }, .produces = &.{}, .replaces = &.{.specification_support_review}, .side_effect = .none };
    pub fn execute(_: Action, comptime purpose: support.Purpose, allocator: std.mem.Allocator, inputs: @import("../../domain/required_authority.zig").Inputs, context: @import("../../domain/specification_provenance.zig").Context, packet: *const @import("../../domain/model_input_packet.zig").Packet, body: []const u8, origin: ?@import("../../domain/model_candidate_origin.zig").Origin) support.Contract(purpose).Error!support.Contract(purpose).Collection {
        const expected = try support.Contract(purpose).packet(allocator, inputs, context);
        defer @import("../../domain/model_input_packet.zig").release(expected);
        if (!std.mem.eql(u8, expected.body(), packet.body()) or !@import("../../domain/model_request_identity.zig").unitOwnerEql(expected.unit(), packet.unit()) or packet.purpose() != .semantic_review) return error.InvalidRequiredAuthority;
        return support.Contract(purpose).collect(allocator, inputs, context, body, origin);
    }
};
