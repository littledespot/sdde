const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const extraction = @import("../../domain/reference_extraction.zig");
const tokens = extraction.tokens;
const evidence = @import("../../domain/reference_evidence.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-preserved-token-classifications", .kind = .action, .requires = &.{ .citable_reference_inputs, .structured_token_candidates, .text_validated_reference_extraction }, .produces = &.{.classified_reference_tokens}, .side_effect = .none };
    /// Complete classification of exactly the current chunk/candidate allowlists.
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: evidence.Inputs, candidates: tokens.Candidates, parsed: extraction.TextValidated) extraction.Error!@import("../../domain/token_classification_validation.zig").Result {
        return @import("../../domain/token_classification_validation.zig").validate(allocator, inputs, candidates, parsed);
    }
};
