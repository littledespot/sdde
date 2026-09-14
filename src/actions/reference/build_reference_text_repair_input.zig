const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/reference_extraction_text_repair.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-reference-text-repair-input", .kind = .action, .requires = &.{ .valid_toolchain, .citable_reference_inputs, .reference_passive_literals, .parsed_reference_extraction, .structured_token_candidates, .reference_text_repair_authorization }, .produces = &.{.model_input_packet}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, facts: repair.Facts, registry: @import("../../domain/passive_literals.zig").Registry, current: *const @import("../../domain/toolchain_safety.zig").ValidToolchain, candidates: @import("../../domain/structured_tokens.zig").Candidates, authorization: repair.Authorization) repair.Error!*@import("../../domain/model_input_packet.zig").Packet {
        return repair.packet(a, facts, registry, current, candidates, authorization);
    }
};
