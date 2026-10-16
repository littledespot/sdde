const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/reference_extraction_text_repair.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "merge-reference-text-repair", .kind = .action, .requires = &.{ .valid_toolchain, .citable_reference_inputs, .reference_passive_literals, .parsed_reference_extraction, .reference_text_repair_authorization, .reference_text_repair_result }, .produces = &.{}, .replaces = &.{.parsed_reference_extraction}, .invalidates = &.{ .text_validated_reference_extraction, .reference_text_repair_authorization, .reference_text_repair_result }, .side_effect = .none };
    normalizer: @import("../../ports/unicode_normalizer.zig").Normalizer,
    pub fn execute(self: Action, a: std.mem.Allocator, facts: repair.Facts, authorization: repair.Authorization, replacement: repair.Replacement, origin: ?@import("../../domain/model_candidate_origin.zig").Origin) repair.Error!@import("../../domain/reference_extraction.zig").Parsed {
        var canonical = try @import("../../domain/typed_text.zig").CanonicalText.fromInputs(a, self.normalizer, facts.text.inputs);
        defer canonical.deinit(a);
        return repair.merge(a, canonical, facts, authorization, replacement, origin);
    }
};
