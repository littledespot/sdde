//! Shared presentation of registered requirements; no requiredness or routing policy.
const std = @import("std");
const a = @import("required_authority.zig");
const spec = @import("specification.zig");

/// Business meanings shared by authoring and review; no applicability or verdict.
pub fn recordFamily(kind: spec.Kind) []const u8 {
    return switch (kind) {
        .acceptance_criterion => "An observable pass/fail flow with a precondition, trigger and expected result.",
        .user_visible_outcome => "A result, confirmation or response directly observable by the user.",
        .edge_case => "A boundary or exceptional condition and its expected outcome.",
        .functional_requirement => "Required application behavior, preserving its trigger, conditions and obligation strength.",
        .business_rule => "A rule or constraint governing business decisions or outcomes.",
        .assumption => "A supported premise on which the described behavior depends.",
        .non_goal => "Behavior explicitly excluded from the feature's scope.",
        .prohibited_behavior => "An action or behavior that must not occur.",
        .entity => "A business data concept with its meaning and relationships.",
    };
}

pub fn recordField(kind: spec.Kind, slot: a.Slot) a.Error![]const u8 {
    if (!a.recordField(kind, slot)) return error.InvalidRequiredAuthority;
    return switch (slot) {
        .text => recordFamily(kind),
        .given => "The precondition under which the behavior applies.",
        .when => "The triggering action or event.",
        .then, .expected_outcome => "The observable result, preserving conditions and obligations.",
        .condition => "The boundary or exceptional condition.",
        .name => "The business entity's name.",
        .business_meaning => "The entity's business purpose.",
        .relationship => "The business relationship to another entity, including its meaning.",
        else => unreachable,
    };
}

pub fn recordTask(allocator: std.mem.Allocator, kind: spec.Kind, slot: a.Slot) a.Error![]const u8 {
    const field = try recordField(kind, slot);
    if (slot == .text) return std.fmt.allocPrint(allocator, "{s}.{s}: {s}", .{ @tagName(kind), @tagName(slot), field });
    return std.fmt.allocPrint(allocator, "{s}: {s} {s}: {s}", .{ @tagName(kind), recordFamily(kind), @tagName(slot), field });
}

/// Present a whole family for generation or a whole-record replacement.
pub fn record(allocator: std.mem.Allocator, kind: spec.Kind) a.Error![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);
    try result.appendSlice(allocator, @tagName(kind));
    try result.appendSlice(allocator, ": ");
    try result.appendSlice(allocator, recordFamily(kind));
    inline for (comptime std.meta.tags(spec.Kind)) |family| {
        if (kind == family) {
            inline for (@typeInfo(@FieldType(spec.Content(spec.BusinessValue), @tagName(family))).@"struct".fields) |field| {
                const slot: a.Slot = @field(a.Slot, if (std.mem.eql(u8, field.name, "relationships")) "relationship" else field.name);
                // A text-only family's definition already describes its sole field.
                if (slot != .text) {
                    try result.appendSlice(allocator, " ");
                    try result.appendSlice(allocator, field.name);
                    try result.appendSlice(allocator, ": ");
                    try result.appendSlice(allocator, try recordField(kind, slot));
                }
            }
        }
    }
    return result.toOwnedSlice(allocator);
}

pub fn records(allocator: std.mem.Allocator) a.Error![]const u8 {
    return recordsFor(allocator, std.meta.tags(spec.Kind));
}

pub fn recordsFor(allocator: std.mem.Allocator, kinds: []const spec.Kind) a.Error![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);
    for (kinds) |kind| {
        const description = try record(allocator, kind);
        defer allocator.free(description);
        if (result.items.len != 0) try result.appendSlice(allocator, "\n");
        try result.appendSlice(allocator, description);
    }
    return result.toOwnedSlice(allocator);
}

pub fn question(allocator: std.mem.Allocator, id: a.Id) a.Error![]const u8 {
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
    const description = try task(allocator, id);
    defer allocator.free(description);
    return std.fmt.allocPrint(allocator, "What decision resolves the following requirement? {s} Identify the missing choice or reconcile the conflicting evidence.", .{description});
}
/// Presentation of the native subject, not another requirement or routing policy.
pub fn task(allocator: std.mem.Allocator, id: a.Id) a.Error![]const u8 {
    return switch (id.unit) {
        .feature => switch (id.slot) {
            .display_name => "A concise name derived from the feature's source-backed purpose. The source need not supply a title.",
            .description => "A description of intended user-visible behavior.",
            .primary_goal => "The intended user benefit derived from the source-backed behavior and outcome.",
            .primary_user_story => "One narrative describing the actor or system identified by the source, its action and intended result. Preserve conditions and obligations; do not invent a persona or benefit or require a prewritten story.",
            .acceptance_criteria => recordFamily(.acceptance_criterion),
            .functional_requirements => recordFamily(.functional_requirement),
            .scenario_coverage => "Source-required triggers, outcomes and exact copy.",
            .entities => "Whether source-backed behavior requires business entities or relationships. Behavior can support required or not_applicable without an explicit declaration of absence; displayed values alone do not establish entities.",
            else => error.InvalidRequiredAuthority,
        },
        .record => |id_record| recordTask(allocator, id_record.kind, id.slot),
        .source => |source| std.fmt.allocPrint(allocator, "All meaningful facts in source {d} survive extraction and reconciliation, including identity, obligations, conditions and constraints. Preserve source uncertainty; assess loss, not whether specification fields can be generated.", .{source.ordinal}),
        .signal => |signal| std.fmt.allocPrint(allocator, "Source meaning preserved by signal {d}.", .{signal.ordinal}),
        .conflict => |conflict| std.fmt.allocPrint(allocator, "Source evidence and unresolved meaning of conflict {d}.", .{conflict.ordinal}),
        .token => |token| std.fmt.allocPrint(allocator, "Exact token {d} and its source-required use.", .{token.ordinal}),
        .decision => |decision| std.fmt.allocPrint(allocator, "{s} decision {d}.", .{ @tagName(id.kind), decision.ordinal }),
    };
}
