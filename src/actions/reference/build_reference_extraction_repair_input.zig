const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const extraction = @import("../../domain/reference_extraction.zig");
const repair = @import("../../domain/reference_extraction_repair.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-reference-extraction-repair-input", .kind = .action, .requires = &.{ .citable_reference_inputs, .reference_passive_literals, .structured_token_candidates, .text_validated_reference_extraction, .reference_extraction_repair_authorization }, .produces = &.{.model_input_packet}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: @import("../../domain/reference_evidence.zig").Inputs, literals: @import("../../domain/passive_literals.zig").Registry, candidates: extraction.tokens.Candidates, current: extraction.TextValidated, authorization: repair.Authorization) repair.Error!*@import("../../domain/model_input_packet.zig").Packet {
        return repair.packet(allocator, inputs, literals, candidates, current, authorization);
    }
};
