//! Specify contributes structural requirements, not its own success policy.
const std = @import("std");
const authority = @import("required_authority.zig");
const spec = @import("specification.zig");
const reference = @import("reference_reconciliation.zig");

/// The record family a feature collection requirement names.
pub fn collectionFamily(slot: authority.Slot) ?spec.Kind {
    return switch (slot) {
        .acceptance_criteria => .acceptance_criterion,
        .functional_requirements => .functional_requirement,
        else => null,
    };
}

pub fn project(allocator: std.mem.Allocator, feature: @import("feature_identity.zig").FeatureId, references: reference.Accounted) authority.Error!authority.Inputs {
    return projectRecords(allocator, feature, @import("reference_support.zig").records(references));
}
/// Source readiness before generation: the feature requirements the sources must
/// support, and the reference obligations. No candidate exists yet.
pub fn projectRecords(allocator: std.mem.Allocator, feature: @import("feature_identity.zig").FeatureId, references: @import("reference_support.zig").Records) authority.Error!authority.Inputs {
    const items = references.items;
    const sources = try allocator.alloc(authority.Authority, 1);
    sources[0] = .{ .reference = items.state_id };
    var seeds: std.ArrayList(authority.Seed) = .empty;
    var gaps: std.ArrayList(authority.ForcedGap) = .empty;
    for ([_]authority.Slot{ .display_name, .description, .primary_goal, .primary_user_story, .entities, .acceptance_criteria, .functional_requirements, .scenario_coverage }) |slot| {
        try seeds.append(allocator, .{
            .id = .{ .kind = if (slot == .entities) .entity_applicability else .feature_intent, .unit = .{ .feature = .singleton }, .slot = slot },
            .requiredness = .{ .schema = .specification },
            .input_authorities = sources,
        });
    }
    // Complete reference accounting remains owned by the preceding reference
    // validators. Keep the exact IDs; do not infer field support from a signal.
    for (references.signals) |signal| try seeds.append(allocator, .{
        .id = .{ .kind = .reference_meaning, .unit = .{ .signal = signal.id }, .slot = .disposition },
        .requiredness = .{ .obligation = .reference_accounting },
        .input_authorities = sources,
    });
    for (references.conflicts) |conflict| {
        const id: authority.Id = .{ .kind = .reference_meaning, .unit = .{ .conflict = conflict.id }, .slot = .disposition };
        try seeds.append(allocator, .{ .id = id, .requiredness = .{ .obligation = .reference_accounting }, .input_authorities = sources });
        // A reconciliation label is a candidate assertion. Source review
        // establishes whether the gap needs user authority or candidate repair.
        try gaps.append(allocator, .{ .requirement = id, .reason = .conflicting, .subject = .candidate });
    }
    for (items.entries) |item| {
        if (item.claim.content != .preserved_token) continue;
        try seeds.append(allocator, .{
            .id = .{ .kind = .preservation, .unit = .{ .token = item.claim.content.preserved_token.value.id }, .slot = .value },
            .requiredness = .{ .obligation = .exact_preservation },
            .input_authorities = sources,
        });
    }
    return .{ .feature = feature, .projection = .source_readiness, .detected_at = .spec, .authorities = sources, .seeds = try seeds.toOwnedSlice(allocator), .evidence = &.{}, .forced_gaps = try gaps.toOwnedSlice(allocator), .references = references };
}
