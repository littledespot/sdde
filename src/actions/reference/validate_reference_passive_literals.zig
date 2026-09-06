const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const literals = @import("../../domain/passive_literals.zig");
const unicode = @import("../../ports/unicode_normalizer.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-passive-literals@1", .kind = .action, .requires = &.{ .passive_literal_identities, .valid_toolchain, .citable_reference_inputs }, .produces = &.{.reference_passive_literals}, .side_effect = .none };
    normalizer: unicode.Normalizer,
    folder: unicode.CaseFolder,
    classifier: unicode.LexicalClassifier,
    pub fn execute(self: Action, allocator: std.mem.Allocator, assigned: literals.Assigned, current: *const @import("../../domain/toolchain_safety.zig").ValidToolchain, inputs: @import("../../domain/reference_evidence.zig").Inputs) literals.Error!literals.Registry {
        return literals.validate(allocator, assigned, current, inputs, self.normalizer, self.folder, self.classifier);
    }
};
