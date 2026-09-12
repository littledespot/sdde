const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const extraction = @import("../../domain/reference_extraction.zig");
const tokens = extraction.tokens;
const evidence = @import("../../domain/reference_evidence.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-selections", .kind = .action, .requires = &.{ .citable_reference_inputs, .structured_token_candidates, .text_validated_reference_extraction }, .produces = &.{.validated_reference_selections}, .side_effect = .none };
    /// Validate every model selection against the current captured allowlists.
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: evidence.Inputs, candidates: tokens.Candidates, parsed: extraction.TextValidated) extraction.Error!@import("../../domain/reference_selection_validation.zig").Result {
        return @import("../../domain/reference_selection_validation.zig").validate(allocator, inputs, candidates, parsed);
    }
};
