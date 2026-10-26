const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const extraction = @import("../../domain/reference_extraction.zig");
const tokens = extraction.tokens;
const evidence = @import("../../domain/reference_evidence.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-selections", .kind = .action, .requires = &.{ .citable_reference_inputs, .structured_token_candidates, .text_validated_reference_extraction }, .produces = &.{.validated_reference_selections}, .side_effect = .none };
    /// Classify exact values against quoted claims; admission already bound
    /// every citation to a supplied source line (ADR 0036).
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: evidence.Inputs, candidates: tokens.Candidates, parsed: extraction.TextValidated) extraction.Error!@import("../../domain/token_classification_validation.zig").Result {
        return @import("../../domain/token_classification_validation.zig").validate(allocator, inputs, candidates, parsed);
    }
};
