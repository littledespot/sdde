const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/reference_extraction_text_repair.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "authorize-reference-text-repair", .kind = .action, .requires = &.{ .valid_toolchain, .citable_reference_inputs, .reference_passive_literals, .parsed_reference_extraction, .text_validated_reference_extraction }, .produces = &.{.reference_text_repair_authorization}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, facts: repair.Facts, rejection: @import("../../domain/reference_extraction.zig").TextRejection) repair.Error!repair.Authorization {
        return repair.authorize(a, facts, rejection);
    }
};
