//! Specify contributes structural requirements, not its own success policy.
const std = @import("std");
const authority = @import("required_authority.zig");
const spec = @import("specification.zig");
const reference = @import("reference_reconciliation.zig");

pub fn project(allocator: std.mem.Allocator, feature: @import("feature_identity.zig").FeatureId, references: reference.Accounted, content: ?spec.IdentifiedContent, brief: ?spec.Brief) authority.Error!authority.Inputs {
    const items = references.records.assignments.checked.prior.prior.input.progress.plan.layout.items;
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
        // Missing mandatory families are an engine-observed gap. A model's
        // positive review cannot authorize an empty successful specification.
        if (content) |candidate| {
            const kind: ?spec.Kind = switch (slot) {
                .acceptance_criteria => .acceptance_criterion,
                .functional_requirements => .functional_requirement,
                else => null,
            };
            if (kind) |required| {
                if (!spec.hasRecords(candidate, required)) try gaps.append(allocator, .{ .requirement = seeds.items[seeds.items.len - 1].id, .reason = .missing });
            }
        }
    }
    if (content) |candidate| for (candidate.records) |record| {
        switch (record.proposal.content) {
            inline else => |fields| inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                const slot: authority.Slot = @field(authority.Slot, if (std.mem.eql(u8, field.name, "relationships")) "relationship" else field.name);
                const count = if (comptime field.type == spec.BusinessValue) 1 else @field(fields, field.name).len;
                for (0..count) |index| try seeds.append(allocator, .{
                    .id = .{ .kind = .feature_intent, .unit = .{ .record = record.id }, .slot = slot, .member = if (slot == .relationship) std.math.cast(u32, index + 1) orelse return error.InvalidRequiredAuthority else 0 },
                    .requiredness = .{ .schema = .specification },
                    .input_authorities = sources,
                });
            },
        }
    };
    // Complete reference accounting remains owned by the preceding reference
    // validators. Keep the exact IDs; do not infer field support from a signal.
    for (references.records.signals) |signal| try seeds.append(allocator, .{
        .id = .{ .kind = .reference_meaning, .unit = .{ .signal = signal.id }, .slot = .disposition },
        .requiredness = .{ .obligation = .reference_accounting },
        .input_authorities = sources,
    });
    for (references.records.conflicts) |conflict| {
        const id: authority.Id = .{ .kind = .reference_meaning, .unit = .{ .conflict = conflict.id }, .slot = .disposition };
        try seeds.append(allocator, .{ .id = id, .requiredness = .{ .obligation = .reference_accounting }, .input_authorities = sources });
        try gaps.append(allocator, .{ .requirement = id, .reason = .conflicting });
    }
    for (items.entries) |item| {
        if (item.claim.content != .preserved_token) continue;
        try seeds.append(allocator, .{
            .id = .{ .kind = .preservation, .unit = .{ .token = item.claim.content.preserved_token.value.id }, .slot = .value },
            .requiredness = .{ .obligation = .exact_preservation },
            .input_authorities = sources,
        });
    }
    return .{ .feature = feature, .projection = .specification, .specification = content, .brief = brief, .detected_at = .spec, .authorities = sources, .seeds = try seeds.toOwnedSlice(allocator), .evidence = &.{}, .forced_gaps = try gaps.toOwnedSlice(allocator), .references = references };
}
