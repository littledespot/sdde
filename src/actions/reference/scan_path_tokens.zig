const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const grammar = @import("../../domain/path_token_grammar.zig");
const scan = @import("../../domain/path_token_scan.zig");
const unicode = @import("../../ports/unicode_normalizer.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "scan-path-tokens",
        .kind = .action,
        .requires = &.{ .path_token_grammar, .valid_toolchain, .citable_reference_inputs },
        .produces = &.{.path_token_scan},
        .side_effect = .none,
    };
    normalizer: unicode.Normalizer,
    folder: unicode.CaseFolder,
    classifier: unicode.LexicalClassifier,
    pub fn execute(self: Action, allocator: std.mem.Allocator, compiled: grammar.Grammar, current: *const @import("../../domain/toolchain_safety.zig").ValidToolchain, inputs: @import("../../domain/reference_evidence.zig").Inputs, text: []const u8) scan.Error!*scan.Owner {
        var scratch: std.heap.ArenaAllocator = .init(allocator);
        defer scratch.deinit();
        try grammar.validateBinding(scratch.allocator(), compiled, current, inputs, self.normalizer, self.folder);
        return scan.scan(allocator, compiled, text, self.normalizer, self.folder, self.classifier);
    }
};
