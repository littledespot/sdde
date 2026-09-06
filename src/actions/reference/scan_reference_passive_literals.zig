const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const literals = @import("../../domain/passive_literals.zig");
const unicode = @import("../../ports/unicode_normalizer.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "scan-reference-passive-literals@1", .kind = .action, .requires = &.{ .path_token_grammar, .valid_toolchain, .citable_reference_inputs }, .produces = &.{.passive_literal_candidates}, .side_effect = .none };
    normalizer: unicode.Normalizer,
    folder: unicode.CaseFolder,
    classifier: unicode.LexicalClassifier,
    pub fn execute(self: Action, allocator: std.mem.Allocator, grammar: @import("../../domain/path_token_grammar.zig").Grammar, current: *const @import("../../domain/toolchain_safety.zig").ValidToolchain, inputs: @import("../../domain/reference_evidence.zig").Inputs) literals.Error!literals.Candidates {
        return literals.collect(allocator, grammar, current, inputs, self.normalizer, self.folder, self.classifier);
    }
};
