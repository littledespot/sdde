const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const loss = @import("../../domain/source_omission.zig");
const ex = @import("../../domain/reference_extraction_repair.zig").Omission;
const rec = @import("../../domain/reference_reconciliation_repair.zig").Omission;
const r = @import("../../domain/reference_reconciliation.zig");
const Context = @import("../../domain/reference_reconciliation_validation.zig").TextContext;
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "parse-source-omission-repair", .kind = .action, .requires = &.{ .source_omission_repair, .model_input_packet, .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .model_payload_schema_result }, .produces = &.{}, .replaces = &.{.source_omission_repair}, .invalidates = &.{}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, repair: loss.Repair, packet: *const @import("../../domain/model_input_packet.zig").Packet, body: []const u8, origin: @import("../../domain/model_candidate_origin.zig").Origin) (ex.Error || rec.Error)!loss.Repair {
        return .{ .authorization = repair.authorization, .response = .{ .origin = origin, .value = switch (repair.authorization) {
            .extraction => |auth| .{ .extraction = try ex.parse(a, auth, packet, body) },
            .reconciliation => |auth| .{ .reconciliation = try rec.parse(a, auth, packet, body) },
        } } };
    }
};
