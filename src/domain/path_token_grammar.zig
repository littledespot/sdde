//! A lexical detector only. Never authorizes a file, command, import or fetch.
const std = @import("std");
const naming = @import("naming_policy.zig");
const evidence = @import("reference_evidence.zig");
const safety = @import("toolchain_safety.zig");
const unicode = @import("../ports/unicode_normalizer.zig");
pub const Error = naming.Error || error{InvalidPathTokenGrammar};
pub const ReferenceName = struct { source_id: evidence.identity.SourceId, basename: []const u8 };
pub const Grammar = struct {
    contract: enum { path_token_grammar_v1 },
    policy: naming.Compiled,
    reference_state_id: evidence.identity.StateId,
    feature_id: @import("feature_identity.zig").FeatureId,
    reference_names: []const ReferenceName,
};

pub fn build(allocator: std.mem.Allocator, compiled: naming.Compiled, current: *const safety.ValidToolchain, inputs: evidence.Inputs, normalizer: unicode.Normalizer, folder: unicode.CaseFolder) Error!Grammar {
    try naming.validateBinding(allocator, compiled, current, normalizer, folder);
    if (!inputs.corpus.state_id.eql(inputs.chunks.state_id)) return error.InvalidPathTokenGrammar;
    const names = try allocator.alloc(ReferenceName, inputs.corpus.sources.len);
    for (inputs.corpus.sources, names) |source, *name| {
        const start = if (std.mem.lastIndexOfScalar(u8, source.path.bytes, '/')) |index| index + 1 else 0;
        name.* = .{ .source_id = source.id, .basename = try naming.normalize(allocator, source.path.bytes[start..], true, normalizer, folder) };
    }
    return .{
        .contract = .path_token_grammar_v1,
        .policy = compiled,
        .reference_state_id = .{ .bytes = try allocator.dupe(u8, inputs.corpus.state_id.bytes) },
        .feature_id = .{ .bytes = try allocator.dupe(u8, inputs.corpus.feature_id.bytes) },
        .reference_names = names,
    };
}

pub fn validateBinding(allocator: std.mem.Allocator, grammar: Grammar, current: *const safety.ValidToolchain, inputs: evidence.Inputs, normalizer: unicode.Normalizer, folder: unicode.CaseFolder) Error!void {
    try naming.validateBinding(allocator, grammar.policy, current, normalizer, folder);
    if (!grammar.reference_state_id.eql(inputs.corpus.state_id) or !grammar.reference_state_id.eql(inputs.chunks.state_id) or
        !std.mem.eql(u8, grammar.feature_id.bytes, inputs.corpus.feature_id.bytes) or grammar.reference_names.len != inputs.corpus.sources.len) return error.InvalidPathTokenGrammar;
    for (grammar.reference_names, inputs.corpus.sources) |name, source| {
        const start = if (std.mem.lastIndexOfScalar(u8, source.path.bytes, '/')) |index| index + 1 else 0;
        if (name.source_id.ordinal != source.id.ordinal or !std.mem.eql(u8, name.basename, source.path.bytes[start..])) return error.InvalidPathTokenGrammar;
    }
}
