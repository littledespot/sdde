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

pub fn projectFor(allocator: std.mem.Allocator, feature: @import("feature_identity.zig").FeatureId, references: reference.Accounted, pass: authority.Pass) authority.Error!authority.Inputs {
    return projectRecords(allocator, feature, @import("reference_support.zig").records(references), pass);
}
/// Source readiness before generation: the feature requirements the sources must
/// support, and the reference obligations. No candidate exists yet. The story isn't
/// one: the engine composes it from the sources' business claims (ADR 0047). Nor is the
/// display name, which the engine takes from the sources' heading (ADR 0048).
///
/// A first pass over a reconciliation that holds a conflict record projects those records
/// and their forced gaps alone. One conflict has one decision, owned by the conflict
/// record's subject and answered by its `select_one` form; feature-requirement subjects
/// raised competing free-text forms for the same contradiction (ADR 0025 subject rule).
/// A dependent pass validates a pending source repair. A repair whose change cannot be
/// bounded may have touched any claim, so that pass, and a first pass over a reconciliation
/// without a conflict, project every seed. A `decided` pass follows a repair that decided
/// named claims again, and projects the conflict records and the signals holding those claims,
/// all that repair created or changed (ADR 0023, amended 27 November 2026). The builder and
/// the gate share this rule.
pub fn projectRecords(allocator: std.mem.Allocator, feature: @import("feature_identity.zig").FeatureId, references: @import("reference_support.zig").Records, pass: authority.Pass) authority.Error!authority.Inputs {
    const items = references.items;
    const sources = try allocator.alloc(authority.Authority, 1);
    sources[0] = .{ .reference = items.state_id };
    var seeds: std.ArrayList(authority.Seed) = .empty;
    var gaps: std.ArrayList(authority.ForcedGap) = .empty;
    const complete = switch (pass) {
        .first => references.conflicts.len == 0,
        .dependent => true,
        .decided => false,
    };
    if (pass == .decided) for (references.signals) |signal| {
        const changed = for (signal.value.claim_ids) |claim| {
            if (@import("reference_reconciliation.zig").contains(@import("reference_reconciliation.zig").ClaimId, pass.decided, claim)) break true;
        } else false;
        if (changed) try seeds.append(allocator, .{
            .id = .{ .kind = .reference_meaning, .unit = .{ .signal = signal.id }, .slot = .disposition },
            .requiredness = .{ .obligation = .reference_accounting },
            .input_authorities = sources,
        });
    };
    if (complete) {
        for ([_]authority.Slot{ .description, .primary_goal, .entities, .acceptance_criteria, .functional_requirements, .scenario_coverage }) |slot| {
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
    }
    for (references.conflicts) |conflict| {
        const id = authority.conflictDisposition(conflict.id);
        try seeds.append(allocator, .{ .id = id, .requiredness = .{ .obligation = .reference_accounting }, .input_authorities = sources });
        // A reconciliation label is a candidate assertion. Source review
        // establishes whether the gap needs user authority or candidate repair.
        try gaps.append(allocator, .{ .requirement = id, .reason = .conflicting, .subject = .candidate });
    }
    if (complete) {
        for (items.entries) |item| {
            if (item.claim.content != .preserved_token) continue;
            try seeds.append(allocator, .{
                .id = .{ .kind = .preservation, .unit = .{ .token = item.claim.content.preserved_token.value.id }, .slot = .value },
                .requiredness = .{ .obligation = .exact_preservation },
                .input_authorities = sources,
            });
        }
    }
    return .{ .feature = feature, .projection = .source_readiness, .pass = pass, .detected_at = .spec, .authorities = sources, .seeds = try seeds.toOwnedSlice(allocator), .evidence = &.{}, .forced_gaps = try gaps.toOwnedSlice(allocator), .references = references };
}
