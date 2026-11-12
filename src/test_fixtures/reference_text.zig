const std = @import("std");
const unicode = @import("unicode_normalization");
pub const safety = @import("../domain/toolchain_safety.zig");
pub const literals = @import("../domain/passive_literals.zig");
pub const normalizer: @import("../ports/unicode_normalizer.zig").Normalizer = .{ .normalize_fn = unicode.nfc };
pub const folder: @import("../ports/unicode_normalizer.zig").CaseFolder = .{ .fold_fn = unicode.caseFold };
pub const classifier: @import("../ports/unicode_normalizer.zig").LexicalClassifier = .{ .boundary_fn = unicode.lexicalBoundary };
pub const validator: @import("../domain/typed_text.zig").Validator = .{ .normalizer = normalizer, .folder = folder };
/// The reference token stage's internal steps, called directly: test setup runs the same functions
/// the stage does.
pub const stage = @import("../actions/reference/prepare_reference_tokens.zig").steps;
pub const validate_text = @import("../actions/reference/validate_reference_extraction_text.zig").Action{ .validator = validator };
pub const Prepared = struct {
    owner: *safety.Owner,
    candidates: literals.Candidates,
    assigned: literals.Assigned,
    registry: literals.Registry,
    pub fn check(self: Prepared, allocator: std.mem.Allocator, inputs: @import("../domain/reference_evidence.zig").Inputs, parsed: @import("../domain/reference_extraction.zig").Parsed) !@import("../domain/reference_extraction.zig").TextValidated {
        return switch (try validate_text.execute(allocator, self.registry, safety.value(self.owner), inputs, parsed)) {
            .valid => |value| value,
            .invalid => |rejection| rejection.issue.failure(),
        };
    }
    pub fn deinit(self: Prepared) void {
        safety.deinitOwner(self.owner);
    }
};
/// Test setup only; every candidate comes from the same native action used by YAML.
pub fn prepare(allocator: std.mem.Allocator, inputs: @import("../domain/reference_evidence.zig").Inputs) !Prepared {
    const owner = safety.validate(allocator, .{ .packages = &.{}, .policies = &.{"project.zig@1"} }, @import("../composition/toolchain_policy_registry.zig").registry) catch return error.OutOfMemory;
    errdefer safety.deinitOwner(owner);
    const policy = try (@import("../actions/toolchain/compile_naming_policy.zig").Action{ .normalizer = normalizer, .folder = folder }).execute(allocator, safety.value(owner));
    const grammar = try stage.buildGrammar(normalizer, folder, allocator, policy, safety.value(owner), inputs);
    const candidates = try stage.scanLiterals(normalizer, folder, classifier, allocator, grammar, safety.value(owner), inputs);
    const assigned = try stage.assignLiterals(allocator, candidates);
    return .{ .owner = owner, .candidates = candidates, .assigned = assigned, .registry = try stage.validateLiterals(normalizer, folder, classifier, allocator, assigned, safety.value(owner), inputs) };
}
pub fn check(allocator: std.mem.Allocator, inputs: @import("../domain/reference_evidence.zig").Inputs, parsed: @import("../domain/reference_extraction.zig").Parsed) !@import("../domain/reference_extraction.zig").TextValidated {
    const prepared = try prepare(allocator, inputs);
    defer prepared.deinit();
    return prepared.check(allocator, inputs, parsed);
}
