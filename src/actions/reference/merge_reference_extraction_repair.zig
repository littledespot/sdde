const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const extraction = @import("../../domain/reference_extraction.zig");
const repair = @import("../../domain/reference_extraction_repair.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "merge-reference-extraction-repair", .kind = .action, .requires = &.{ .citable_reference_inputs, .structured_token_candidates, .text_validated_reference_extraction, .reference_extraction_repair_authorization, .reference_extraction_repair_result }, .produces = &.{}, .replaces = &.{.text_validated_reference_extraction}, .invalidates = &.{ .validated_reference_selections, .reference_extraction_repair_authorization, .reference_extraction_repair_result }, .side_effect = .none };
    normalizer: @import("../../ports/unicode_normalizer.zig").Normalizer,
    pub fn execute(self: Action, allocator: std.mem.Allocator, facts: repair.Facts, authorization: repair.Authorization, replacement: repair.Replacement, origin: ?@import("../../domain/model_candidate_origin.zig").Origin) repair.Error!extraction.TextValidated {
        var canonical = try @import("../../domain/typed_text.zig").CanonicalText.fromInputs(allocator, self.normalizer, facts.inputs);
        defer canonical.deinit(allocator);
        return repair.merge(allocator, canonical, facts, authorization, replacement, origin);
    }
};
