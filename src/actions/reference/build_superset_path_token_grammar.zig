const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const grammar = @import("../../domain/path_token_grammar.zig");
const unicode = @import("../../ports/unicode_normalizer.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "build-superset-path-token-grammar@1",
        .kind = .action,
        .requires = &.{ .compiled_naming_policy, .valid_toolchain, .citable_reference_inputs },
        .produces = &.{.path_token_grammar},
        .side_effect = .none,
    };
    normalizer: unicode.Normalizer,
    folder: unicode.CaseFolder,
    pub fn execute(self: Action, allocator: std.mem.Allocator, policy: @import("../../domain/naming_policy.zig").Compiled, current: *const @import("../../domain/toolchain_safety.zig").ValidToolchain, inputs: @import("../../domain/reference_evidence.zig").Inputs) grammar.Error!grammar.Grammar {
        return grammar.build(allocator, policy, current, inputs, self.normalizer, self.folder);
    }
};
