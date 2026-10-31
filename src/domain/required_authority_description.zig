//! Shared presentation of registered requirements; no requiredness or routing policy.
const std = @import("std");
const a = @import("required_authority.zig");
const spec = @import("specification.zig");
const guidance = @import("packet_guidance.zig");
/// Purposes are workflow-owned packet guidance; this module composes them with
/// native identities and frames.
const Guidance = guidance.Guidance;

/// Presentation of an already-bound source-review assignment, not a new
/// ownership, eligibility or finding policy. Business purposes remain shared
/// with authoring and principle review; these evidence roles are source-only.
pub const SourceReviewScope = struct {
    original_sources: []const u8,
    derived_evidence: []const u8,
    instruction: []const u8,
};

pub fn sourceReviewScope(g: *const Guidance, subject: @import("specification_review_subject.zig").Subject) SourceReviewScope {
    const scope = g.review_scope;
    return .{ .original_sources = scope.original_sources, .derived_evidence = scope.derived_evidence, .instruction = switch (subject) {
        .candidate_field => |field| scope.candidate_field.get(if (field.record != null) .in_record else .standalone),
        .collection => scope.collection,
        .entity_applicability => scope.entity_applicability,
        .source_preservation => scope.source_preservation,
        .reference => |reference| scope.reference.get(std.meta.activeTag(reference)),
    } };
}

/// Business meanings shared by authoring and review; no applicability or verdict.
pub fn recordFamily(g: *const Guidance, kind: spec.Kind) []const u8 {
    return g.record_families.get(kind);
}

pub fn recordField(g: *const Guidance, kind: spec.Kind, slot: a.Slot) a.Error![]const u8 {
    if (!a.recordField(kind, slot)) return error.InvalidRequiredAuthority;
    if (slot == .text) return recordFamily(g, kind);
    return g.record_fields.get(guidance.recordField(slot) orelse return error.InvalidRequiredAuthority);
}

pub fn recordTask(allocator: std.mem.Allocator, g: *const Guidance, kind: spec.Kind, slot: a.Slot) a.Error![]const u8 {
    const field = try recordField(g, kind, slot);
    if (slot == .text) return std.fmt.allocPrint(allocator, "{s}.{s}: {s}", .{ @tagName(kind), @tagName(slot), field });
    return std.fmt.allocPrint(allocator, "{s}: {s} {s}: {s}", .{ @tagName(kind), recordFamily(g, kind), @tagName(slot), field });
}

/// Present a whole family for generation or a whole-record replacement.
pub fn record(allocator: std.mem.Allocator, g: *const Guidance, kind: spec.Kind) a.Error![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);
    try result.appendSlice(allocator, @tagName(kind));
    try result.appendSlice(allocator, ": ");
    try result.appendSlice(allocator, recordFamily(g, kind));
    inline for (comptime std.meta.tags(spec.Kind)) |family| {
        if (kind == family) {
            inline for (@typeInfo(@FieldType(spec.Content(spec.BusinessValue), @tagName(family))).@"struct".fields) |field| {
                const slot: a.Slot = @field(a.Slot, if (std.mem.eql(u8, field.name, "relationships")) "relationship" else field.name);
                // A text-only family's definition already describes its sole field.
                if (slot != .text) {
                    try result.appendSlice(allocator, " ");
                    try result.appendSlice(allocator, field.name);
                    try result.appendSlice(allocator, ": ");
                    try result.appendSlice(allocator, try recordField(g, kind, slot));
                }
            }
        }
    }
    return result.toOwnedSlice(allocator);
}

pub fn records(allocator: std.mem.Allocator, g: *const Guidance) a.Error![]const u8 {
    return recordsFor(allocator, g, std.meta.tags(spec.Kind));
}

pub fn recordsFor(allocator: std.mem.Allocator, g: *const Guidance, kinds: []const spec.Kind) a.Error![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);
    for (kinds) |kind| {
        const description = try record(allocator, g, kind);
        defer allocator.free(description);
        if (result.items.len != 0) try result.appendSlice(allocator, "\n");
        try result.appendSlice(allocator, description);
    }
    return result.toOwnedSlice(allocator);
}

pub fn question(allocator: std.mem.Allocator, g: *const Guidance, id: a.Id) a.Error![]const u8 {
    if (a.policy(id) == null) return error.InvalidRequiredAuthority;
    if (id.unit == .feature) return switch (id.slot) {
        .display_name => "What name should identify this feature's purpose?",
        .description => "What user-visible behavior is missing or undecided in the current source evidence?",
        .primary_goal => "What benefit should this feature provide to its users?",
        .primary_user_story => "Who uses this feature, what do they do, and what result do they need? Supply only the elements missing from the current evidence.",
        .acceptance_criteria => "Which pass/fail outcome is still undecided? Describe when it applies and what the user should observe.",
        .functional_requirements => "What required behavior is missing or undecided? State its trigger and expected result without repeating behavior already established in the source.",
        .scenario_coverage => "Which source-required situation still needs a trigger or outcome clarified? Identify the situation and any exact output it requires.",
        .entities => "Which required business information is still undecided? Name it and the behavior that depends on it.",
        else => error.InvalidRequiredAuthority,
    };
    const description = try task(allocator, g, id);
    defer allocator.free(description);
    return std.fmt.allocPrint(allocator, "What decision resolves the following requirement? {s} Identify the missing choice or reconcile the conflicting evidence.", .{description});
}
/// Presentation of the native subject, not another requirement or routing policy.
/// A feature task is a workflow-owned purpose and is not allocated; every other
/// task is allocated by `allocator`.
pub fn task(allocator: std.mem.Allocator, g: *const Guidance, id: a.Id) a.Error![]const u8 {
    return switch (id.unit) {
        .feature => if (@import("specification_authority.zig").collectionFamily(id.slot)) |family|
            recordFamily(g, family)
        else
            g.feature_purposes.get(guidance.featurePurpose(id.slot) orelse return error.InvalidRequiredAuthority),
        .record => |id_record| recordTask(allocator, g, id_record.kind, id.slot),
        inline .source, .signal, .conflict, .token => |unit, tag| reference: {
            const fragments = g.reference_tasks.get(@field(guidance.ReferenceUnit, @tagName(tag)));
            break :reference std.fmt.allocPrint(allocator, "{s}{d}{s}", .{ fragments.before, unit.ordinal, fragments.after });
        },
        .decision => |decision| std.fmt.allocPrint(allocator, "{s} decision {d}.", .{ @tagName(id.kind), decision.ordinal }),
    };
}
