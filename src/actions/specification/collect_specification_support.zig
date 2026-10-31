const support = @import("../../domain/specification_support.zig");
const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const retention = @import("../../domain/specification_review_retention.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "collect-specification-support", .kind = .action, .requires = &.{ .required_authority_inputs, .specification_support_review, .specification_review_history, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .model_request_identity_ledger, .prepared_model_request, .model_input_packet, .model_payload_schema_result, .packet_guidance }, .produces = &.{}, .replaces = &.{ .specification_support_review, .specification_review_history }, .side_effect = .none };
    pub fn execute(_: Action, comptime purpose: support.Purpose, allocator: std.mem.Allocator, inputs: @import("../../domain/required_authority.zig").Inputs, context: @import("../../domain/specification_provenance.zig").Context, guidance: *const @import("../../domain/packet_guidance.zig").Guidance, prior: ?support.Contract(purpose).Collection, packet: *const @import("../../domain/model_input_packet.zig").Packet, body: []const u8, origin: ?@import("../../domain/model_candidate_origin.zig").Origin, history: retention.History, request: *const @import("../../domain/model_request_handoff.zig").Request, proof: *const @import("../../domain/model_payload_schema.zig").Evidence, ledger: *const @import("../../domain/model_request_identity.zig").ModelRequestIdentityLedger) retention.Error!struct { collection: support.Contract(purpose).Collection, history: retention.History } {
        const collection = try support.Contract(purpose).collectFocused(allocator, inputs, context, guidance, prior, packet, body, origin);
        return .{ .collection = collection, .history = if (purpose == .source) try retention.record(allocator, history, inputs, context, guidance, collection, request, proof, ledger) else history };
    }
};
