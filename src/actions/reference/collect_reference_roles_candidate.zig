const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const stage = @import("../../domain/reference_reconciliation_stage.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "collect-reference-roles-candidate", .kind = .action, .requires = &.{ .validated_reference_signals, .model_request_identity_ledger, .prepared_model_request, .model_input_packet, .model_payload_schema_result }, .produces = &.{}, .replaces = &.{.parsed_reference_reconciliation}, .invalidates = &.{ .validated_reference_dispositions, .validated_reference_signals }, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, prior: stage.Prior, bound: *const @import("../../domain/model_input_packet.zig").Packet, body: []const u8, origin: @import("../../domain/model_candidate_origin.zig").Origin) r.Error!r.Parsed {
        if (prior != .roles) return error.InvalidReferenceReconciliation;
        return stage.collect(a, prior, bound, body, origin);
    }
};
