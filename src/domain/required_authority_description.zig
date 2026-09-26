//! Shared presentation of registered requirements; no requiredness or routing policy.
const std = @import("std");
const a = @import("required_authority.zig");
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
            .display_name => "A name identifying the feature's purpose.",
            .description => "A description of intended user-visible behavior.",
            .primary_goal => "The intended user benefit.",
            .primary_user_story => "The actor, action and intended result.",
            .acceptance_criteria => "Observable pass/fail outcomes.",
            .functional_requirements => "Required application behavior.",
            .scenario_coverage => "Source-required triggers, outcomes and exact copy.",
            .entities => "Whether the specified behavior requires business entities. Judge source meaning, not an entity heading or explicit declaration of absence; displayed values alone do not establish entities.",
            else => error.InvalidRequiredAuthority,
        },
        .record => |id_record| std.fmt.allocPrint(allocator, "Source support for {s} {d}, field {s}, member {d}.", .{ @tagName(id_record.kind), id_record.ordinal, @tagName(id.slot), id.member }),
        .signal => |signal| std.fmt.allocPrint(allocator, "Source meaning preserved by signal {d}.", .{signal.ordinal}),
        .conflict => |conflict| std.fmt.allocPrint(allocator, "Source evidence and unresolved meaning of conflict {d}.", .{conflict.ordinal}),
        .token => |token| std.fmt.allocPrint(allocator, "Exact token {d} and its source-required use.", .{token.ordinal}),
        .decision => |decision| std.fmt.allocPrint(allocator, "{s} decision {d}.", .{ @tagName(id.kind), decision.ordinal }),
    };
}
