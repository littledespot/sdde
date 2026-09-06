const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const iteration = @import("../../domain/reference_model_iteration.zig");
const packets = @import("../../domain/model_input_packet.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "collect-reference-extraction-result", .kind = .action, .requires = &.{ .reference_extraction_progress, .model_request_identity_ledger, .prepared_model_request, .model_input_packet, .model_payload_schema_result }, .replaces = &.{.reference_extraction_progress}, .produces = &.{}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, progress: iteration.Progress, packet: *const packets.Packet, body: []const u8) @import("../../domain/reference_extraction.zig").Error!iteration.Progress {
        const unit = packet.unit();
        if (unit != .reference_chunk or packet.purpose() != .initial_generation) return error.InvalidReferenceExtraction;
        return iteration.append(allocator, progress, .{ .state_id = .{ .bytes = unit.reference_chunk.reference_state_id.bytes }, .chunk_id = .{ .bytes = unit.reference_chunk.chunk_id.bytes } }, body);
    }
};
