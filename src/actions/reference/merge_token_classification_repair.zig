const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const extraction = @import("../../domain/reference_extraction.zig");
const repair = @import("../../domain/token_classification_repair.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "merge-token-classification-repair", .kind = .action, .requires = &.{ .text_validated_reference_extraction, .token_classification_repair_authorization, .token_classification_repair_result }, .produces = &.{}, .replaces = &.{.text_validated_reference_extraction}, .invalidates = &.{ .classified_reference_tokens, .token_classification_repair_authorization, .token_classification_repair_result }, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, current: extraction.TextValidated, authorization: repair.Authorization, replacement: repair.Replacement) repair.Error!extraction.TextValidated {
        return repair.merge(allocator, current, authorization, replacement);
    }
};
