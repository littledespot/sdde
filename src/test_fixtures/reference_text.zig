const std = @import("std");
const unicode = @import("unicode_normalization");
pub const safety = @import("../domain/toolchain_safety.zig");
pub const literals = @import("../domain/passive_literals.zig");
pub const normalizer: @import("../ports/unicode_normalizer.zig").Normalizer = .{ .normalize_fn = unicode.nfc };
pub const folder: @import("../ports/unicode_normalizer.zig").CaseFolder = .{ .fold_fn = unicode.caseFold };
pub const classifier: @import("../ports/unicode_normalizer.zig").LexicalClassifier = .{ .boundary_fn = unicode.lexicalBoundary };
pub const validator: @import("../domain/typed_text.zig").Validator = .{ .normalizer = normalizer, .folder = folder, .classifier = classifier };
pub const scan = @import("../actions/reference/scan_reference_passive_literals.zig").Action{ .normalizer = normalizer, .folder = folder, .classifier = classifier };
pub const assign = @import("../actions/reference/assign_passive_literal_identities.zig").Action{};
pub const validate = @import("../actions/reference/validate_reference_passive_literals.zig").Action{ .normalizer = normalizer, .folder = folder, .classifier = classifier };
pub const validate_text = @import("../actions/reference/validate_reference_extraction_text.zig").Action{ .validator = validator };
pub const Prepared = struct {
    owner: *safety.Owner,
    candidates: literals.Candidates,
    assigned: literals.Assigned,
    registry: literals.Registry,
    pub fn deinit(self: Prepared) void {
        safety.deinitOwner(self.owner);
    }
};
/// Test setup only; every candidate comes from the same native action used by YAML.
pub fn prepare(allocator: std.mem.Allocator, inputs: @import("../domain/reference_evidence.zig").Inputs) !Prepared {
    const owner = safety.validate(allocator, .{ .packages = &.{}, .policies = &.{"project.zig@1"} }, @import("../composition/toolchain_policy_registry.zig").registry) catch return error.OutOfMemory;
    errdefer safety.deinitOwner(owner);
    const policy = try (@import("../actions/toolchain/compile_naming_policy.zig").Action{ .normalizer = normalizer, .folder = folder }).execute(allocator, safety.value(owner));
    const grammar = try (@import("../actions/reference/build_superset_path_token_grammar.zig").Action{ .normalizer = normalizer, .folder = folder }).execute(allocator, policy, safety.value(owner), inputs);
    const candidates = try scan.execute(allocator, grammar, safety.value(owner), inputs);
    const assigned = try assign.execute(allocator, candidates);
    return .{ .owner = owner, .candidates = candidates, .assigned = assigned, .registry = try validate.execute(allocator, assigned, safety.value(owner), inputs) };
}
pub fn check(allocator: std.mem.Allocator, inputs: @import("../domain/reference_evidence.zig").Inputs, parsed: @import("../domain/reference_extraction.zig").Parsed) !@import("../domain/reference_extraction.zig").TextValidated {
    const prepared = try prepare(allocator, inputs);
    defer prepared.deinit();
    return validate_text.execute(allocator, prepared.registry, safety.value(prepared.owner), inputs, parsed);
}
