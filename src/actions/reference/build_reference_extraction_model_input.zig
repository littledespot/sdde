const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const inputs = @import("../../domain/reference_model_input.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-reference-extraction-model-input", .kind = .action, .requires = &.{ .citable_reference_inputs, .reference_passive_literals, .structured_token_candidates, .reference_extraction_progress }, .produces = &.{.model_input_packet}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, source: @import("../../domain/reference_evidence.zig").Inputs, registry: @import("../../domain/passive_literals.zig").Registry, tokens: @import("../../domain/structured_tokens.zig").Candidates, progress: @import("../../domain/reference_model_iteration.zig").Progress) inputs.Error!*@import("../../domain/model_input_packet.zig").Packet {
        return inputs.extractionPacket(allocator, source, registry, tokens, @import("../../domain/reference_model_iteration.zig").current(progress) orelse return error.InvalidReferenceExtraction);
    }
};
