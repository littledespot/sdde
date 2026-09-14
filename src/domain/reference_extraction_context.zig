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
    candidate: extraction.Parsed,
    text: extraction.text.Dependencies,
};
pub fn textFacts(inputs: @import("reference_evidence.zig").Inputs, registry: @import("passive_literals.zig").Registry, current: *const @import("toolchain_safety.zig").ValidToolchain, candidate: extraction.Parsed) extraction.Error!TextFacts {
    return .{ .candidate = candidate, .text = try extraction.text.dependencies(inputs, registry, current) };
}
