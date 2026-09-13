const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const extraction = @import("../../domain/reference_extraction.zig");
const repair = @import("../../domain/reference_extraction_repair.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "authorize-reference-extraction-repair", .kind = .action, .requires = &.{ .text_validated_reference_extraction, .validated_reference_selections }, .produces = &.{.reference_extraction_repair_authorization}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, current: extraction.TextValidated, rejection: repair.Rejection) repair.Error!repair.Authorization {
        return repair.authorize(allocator, current, rejection);
    }
};
