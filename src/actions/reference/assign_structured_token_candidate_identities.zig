const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const tokens = @import("../../domain/structured_tokens.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "assign-structured-token-candidate-identities", .kind = .action, .requires = &.{ .citable_reference_inputs, .structured_reference_facts }, .produces = &.{.structured_token_candidates}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: @import("../../domain/reference_evidence.zig").Inputs, facts: tokens.Facts) tokens.Error!tokens.Candidates {
        return tokens.assign(allocator, inputs, facts);
    }
};
