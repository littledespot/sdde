const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const extraction = @import("../../domain/reference_extraction.zig");
const repair = @import("../../domain/reference_extraction_repair.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "merge-reference-extraction-repair", .kind = .action, .requires = &.{ .text_validated_reference_extraction, .reference_extraction_repair_authorization, .reference_extraction_repair_result }, .produces = &.{}, .replaces = &.{.text_validated_reference_extraction}, .invalidates = &.{ .validated_reference_selections, .reference_extraction_repair_authorization, .reference_extraction_repair_result }, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, current: extraction.TextValidated, authorization: repair.Authorization, replacement: repair.Replacement, origin: ?@import("../../domain/model_candidate_origin.zig").Origin) repair.Error!extraction.TextValidated {
        return repair.merge(allocator, current, authorization, replacement, origin);
    }
};
