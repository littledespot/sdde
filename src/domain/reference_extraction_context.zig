//! Facts read by extraction selection validation and its authorized repair.
const std = @import("std");
const extraction = @import("reference_extraction.zig");
pub const Facts = struct {
    inputs: @import("reference_evidence.zig").Inputs,
    candidates: extraction.tokens.Candidates,
    candidate: extraction.TextValidated,
};
pub fn snapshot(a: std.mem.Allocator, facts: Facts) std.mem.Allocator.Error!@import("atomic_repair.zig").Snapshot {
    return @import("atomic_repair.zig").snapshot(Facts, a, facts);
}
pub const TextFacts = struct {
    inputs: @import("reference_evidence.zig").Inputs,
    candidate: extraction.Parsed,
    policy_ids: []const []const u8,
    rules: []const @import("naming_policy.zig").BoundRule,
    reference_names: []const @import("path_token_grammar.zig").ReferenceName,
    passive_records: []const @import("passive_literals.zig").Record,
    passive_occurrences: []const @import("passive_literals.zig").Occurrence,
};
pub fn textFacts(inputs: @import("reference_evidence.zig").Inputs, registry: @import("passive_literals.zig").Registry, candidate: extraction.Parsed) TextFacts {
    return .{ .inputs = inputs, .candidate = candidate, .policy_ids = registry.grammar.policy.policy_ids, .rules = registry.grammar.policy.rules, .reference_names = registry.grammar.reference_names, .passive_records = registry.records, .passive_occurrences = registry.occurrences };
}
