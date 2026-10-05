//! Original-source obligations for the shared semantic review and repair gate.
//! Accounting covers the captured corpus, including sources with no claims.
const std = @import("std");
const a = @import("required_authority.zig");
const r = @import("reference_reconciliation.zig");

pub fn project(allocator: std.mem.Allocator, feature: @import("feature_identity.zig").FeatureId, references: @import("reference_support.zig").Records, sources: r.evidence.Inputs) a.Error!a.Inputs {
    if (!sources.corpus.state_id.eql(references.items.state_id) or !sources.chunks.state_id.eql(references.items.state_id) or !std.mem.eql(u8, feature.bytes, sources.corpus.feature_id.bytes)) return error.InvalidRequiredAuthority;
    const authorities = try allocator.alloc(a.Authority, 1);
    errdefer allocator.free(authorities);
    authorities[0] = .{ .reference = references.items.state_id };
    const seeds = try allocator.alloc(a.Seed, sources.corpus.sources.len);
    errdefer allocator.free(seeds);
    if (seeds.len == 0) return error.InvalidRequiredAuthority;
    for (sources.corpus.sources, seeds, 1..) |source, *seed, ordinal| {
        if (source.id.ordinal != ordinal) return error.InvalidRequiredAuthority;
        seed.* = .{
            .id = .{ .kind = .reference_meaning, .unit = .{ .source = source.id }, .slot = .disposition },
            .requiredness = .{ .obligation = .reference_accounting },
            .input_authorities = authorities,
        };
    }
    return .{ .feature = feature, .projection = .source_preservation, .detected_at = .spec, .authorities = authorities, .seeds = seeds, .evidence = &.{}, .references = references, .source_inputs = sources };
}

/// Source identity survives producer rebuilding; generated claim/signal IDs do not.
pub fn permits(finding: a.Finding) bool {
    return switch (finding) {
        .supported, .candidate_omission, .inconclusive => true,
        .ambiguous, .conflicting, .unsupported => false,
    };
}
