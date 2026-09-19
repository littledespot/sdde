const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const iteration = @import("../../domain/reference_model_iteration.zig");
const packets = @import("../../domain/model_input_packet.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "collect-reference-extraction-result", .kind = .action, .requires = &.{ .reference_extraction_progress, .assembled_json, .validated_assembled_json }, .replaces = &.{.reference_extraction_progress}, .produces = &.{}, .invalidates = &.{ .assembled_json, .validated_assembled_json }, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, progress: iteration.Progress, packet: *const packets.Packet, body: []const u8, origin: @import("../../domain/model_candidate_origin.zig").Origin, producers: @import("../../domain/reference_extraction.zig").ProducerOrigins) @import("../../domain/reference_extraction.zig").Error!iteration.Progress {
        const unit = packet.unit();
        if (unit != .reference_chunk or packet.purpose() != .initial_generation) return error.InvalidReferenceExtraction;
        return iteration.append(allocator, progress, .{ .state_id = .{ .bytes = unit.reference_chunk.reference_state_id.bytes }, .chunk_id = .{ .bytes = unit.reference_chunk.chunk_id.bytes } }, body, origin, producers);
    }
};
