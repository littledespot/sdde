const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "collect-reference-reconciliation-result", .kind = .action, .requires = &.{ .reference_reconciliation_input, .model_request_identity_ledger, .prepared_model_request, .model_input_packet, .model_payload_schema_result }, .produces = &.{.raw_reference_reconciliation}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, input: r.Input, packet: *const @import("../../domain/model_input_packet.zig").Packet, body: []const u8, origin: @import("../../domain/model_candidate_origin.zig").Origin) r.Error!r.Raw {
        if (input.purpose != .summary) return error.InvalidReferenceReconciliation;
        const unit = packet.unit();
        if (unit != .reference_global or packet.purpose() != .initial_generation or !std.mem.eql(u8, unit.reference_global.reference_state_id.bytes, input.progress.plan.layout.items.state_id.bytes)) return error.InvalidReferenceReconciliation;
        const slot = try std.fmt.allocPrint(allocator, "reconciliation-{d}", .{input.partition.id.ordinal});
        if (!std.mem.eql(u8, unit.reference_global.unit_slot_id.bytes, slot)) return error.InvalidReferenceReconciliation;
        // The whole body is one accepted response, so every field of it has that response's origin.
        var source: r.diagnostic.Source = .{ .origin = origin };
        const fields = try allocator.alloc(r.diagnostic.FieldOrigin, 1);
        fields[0] = .{ .unit = .summary, .field = .record, .origin = origin };
        source.fields = fields;
        return .{ .source = source, .input = input, .bytes = try allocator.dupe(u8, body) };
    }
};
