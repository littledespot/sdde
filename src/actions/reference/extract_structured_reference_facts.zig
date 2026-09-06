const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const tokens = @import("../../domain/structured_tokens.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "extract-structured-reference-facts", .kind = .action, .requires = &.{.citable_reference_inputs}, .produces = &.{.structured_reference_facts}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: @import("../../domain/reference_evidence.zig").Inputs) tokens.Error!tokens.Facts {
        return tokens.extract(allocator, inputs);
    }
};
