const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "collect-reference-reconciliation-result", .kind = .action, .requires = &.{ .reference_reconciliation_input, .assembled_json, .validated_assembled_json }, .produces = &.{.raw_reference_reconciliation}, .invalidates = &.{ .assembled_json, .validated_assembled_json }, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, input: r.Input, candidate: *const @import("../../domain/json_composition_runtime.zig").Candidate) r.Error!r.Raw {
        const packet = candidate.base;
        const unit = packet.unit();
        if (unit != .reference_global or packet.purpose() != .initial_generation or !std.mem.eql(u8, unit.reference_global.reference_state_id.bytes, input.progress.plan.layout.items.state_id.bytes)) return error.InvalidReferenceReconciliation;
        const slot = try std.fmt.allocPrint(allocator, "reconciliation-{d}", .{input.partition.id.ordinal});
        if (!std.mem.eql(u8, unit.reference_global.unit_slot_id.bytes, slot)) return error.InvalidReferenceReconciliation;
        var source: r.diagnostic.Source = .{ .origin = candidate.producer(&.{}) };
        const collections: []const struct { path: []const u8, unit: r.diagnostic.Unit } = switch (input.purpose) {
            .summary => &.{.{ .path = "statements", .unit = .summary }},
            .global => &.{ .{ .path = "claim_dispositions", .unit = .dispositions }, .{ .path = "signals", .unit = .signals }, .{ .path = "conflicts", .unit = .conflicts } },
        };
        const fields = try allocator.alloc(r.diagnostic.FieldOrigin, collections.len);
        for (collections, fields) |collection, *field| field.* = .{
            .unit = collection.unit,
            .field = .record,
            .origin = candidate.producer(&.{collection.path}) orelse return error.InvalidReferenceReconciliation,
        };
        source.fields = fields;
        return .{ .source = source, .input = input, .bytes = try allocator.dupe(u8, candidate.body) };
    }
};
