const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const support = @import("../../domain/specification_support.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "collect-specification-support", .kind = .action, .requires = &.{ .required_authority_inputs, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .model_request_identity_ledger, .prepared_model_request, .model_input_packet, .model_payload_schema_result }, .produces = &.{}, .replaces = &.{.required_authority_inputs}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: @import("../../domain/required_authority.zig").Inputs, context: @import("../../domain/specification_provenance.zig").Context, packet: *const @import("../../domain/model_input_packet.zig").Packet, body: []const u8) support.Error!@import("../../domain/required_authority.zig").Inputs {
        const expected = try support.packet(allocator, inputs, context);
        defer @import("../../domain/model_input_packet.zig").release(expected);
        if (!std.mem.eql(u8, expected.body(), packet.body()) or !@import("../../domain/model_request_identity.zig").unitOwnerEql(expected.unit(), packet.unit()) or packet.purpose() != .semantic_review) return error.InvalidRequiredAuthority;
        return support.collect(allocator, inputs, context, body);
    }
};
