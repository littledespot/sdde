const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const support = @import("../../domain/specification_support.zig");
const retention = @import("../../domain/specification_review_retention.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "collect-specification-support-loss", .kind = .action, .requires = &.{ .required_authority_inputs, .specification_support_review, .specification_review_history, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .model_request_identity_ledger, .prepared_model_request, .model_input_packet, .model_payload_schema_result, .packet_guidance }, .produces = &.{}, .replaces = &.{ .specification_support_review, .specification_review_history }, .side_effect = .none };

    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: @import("../../domain/required_authority.zig").Inputs, context: @import("../../domain/specification_provenance.zig").Context, guidance: *const @import("../../domain/packet_guidance.zig").Guidance, collection: support.Source.Collection, packet: *const @import("../../domain/model_input_packet.zig").Packet, bytes: []const u8, origin: ?@import("../../domain/model_candidate_origin.zig").Origin, history: retention.History, ledger: *const @import("../../domain/model_request_identity.zig").ModelRequestIdentityLedger) retention.Error!struct { collection: support.Source.Collection, history: retention.History } {
        const result = try support.Source.collectLoss(allocator, inputs, context, guidance, collection, packet, bytes, origin);
        return .{ .collection = result, .history = try retention.observe(allocator, history, inputs, context, result, ledger) };
    }
};
