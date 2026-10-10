const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const support = @import("../../domain/specification_support.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "collect-specification-support-loss", .kind = .action, .requires = &.{ .required_authority_inputs, .specification_support_review, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .model_request_identity_ledger, .prepared_model_request, .model_input_packet, .model_payload_schema_result }, .produces = &.{}, .replaces = &.{.specification_support_review}, .side_effect = .none };

    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: @import("../../domain/required_authority.zig").Inputs, context: @import("../../domain/specification_provenance.zig").Context, collection: support.Source.Collection, packet: *const @import("../../domain/model_input_packet.zig").Packet, bytes: []const u8, origin: ?@import("../../domain/model_candidate_origin.zig").Origin) support.Source.Error!support.Source.Collection {
        return support.Source.collectLoss(allocator, inputs, context, collection, packet, bytes, origin);
    }
};
