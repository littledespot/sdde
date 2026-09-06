const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
const inputs = @import("../../domain/reference_model_input.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "collect-reference-reconciliation-result", .kind = .action, .requires = &.{ .reference_reconciliation_input, .model_request_identity_ledger, .prepared_model_request, .model_input_packet, .model_payload_schema_result }, .produces = &.{.raw_reference_reconciliation}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, input: r.Input, packet: *const @import("../../domain/model_input_packet.zig").Packet, bytes: []const u8) (r.Error || inputs.Error)!r.Raw {
        const unit = packet.unit();
        if (unit != .reference_global or packet.purpose() != .initial_generation or !std.mem.eql(u8, unit.reference_global.reference_state_id.bytes, input.progress.plan.layout.items.state_id.bytes)) return error.InvalidReferenceReconciliation;
        const slot = try std.fmt.allocPrint(allocator, "reconciliation-{d}", .{input.partition.id.ordinal});
        if (!std.mem.eql(u8, unit.reference_global.unit_slot_id.bytes, slot)) return error.InvalidReferenceReconciliation;
        return .{ .input = input, .bytes = try allocator.dupe(u8, bytes) };
    }
};
