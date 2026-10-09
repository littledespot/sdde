//! Shared role-membership admission. Semantic support remains a model judgment.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
pub const Group = struct { signal_id: r.SignalSelectionId, value: r.ValidatedSignal };
pub const Facts = struct {
    dispositions: []const r.ClaimDisposition,
    signals: []const Group,
    conflict_groups: []const @import("reference_conflict_groups.zig").CatalogueEntry,
};

pub fn groups(a: std.mem.Allocator, source: r.diagnostic.Source, signals: []const r.ValidatedSignal) r.Error![]const Group {
    const result = try a.alloc(Group, signals.len);
    errdefer a.free(result);
    for (signals, result, 0..) |signal, *group, index| group.* = .{
        .signal_id = .{ .ordinal = (source.signals.at(index, signals.len) catch return error.InvalidReferenceReconciliation).ordinal },
        .value = signal,
    };
    return result;
}

pub fn check(dispositions: []const r.ClaimDisposition, offered: []const Group, assignments: []const r.RoleAssignment) r.Error!?r.diagnostic.Issue {
    for (assignments, 0..) |assignment, assignment_index| {
        const invalid: r.diagnostic.Issue = .{ .rule = .role_assignment, .observed = .{ .count = assignment.signal_id.ordinal }, .expected = .{ .constraint = .supported_role_assignment } };
        const selected = for (offered) |group| {
            if (group.signal_id.ordinal == assignment.signal_id.ordinal) break group;
        } else return invalid;
        if (assignment.generation_roles.len == 0 or !try @import("reference_support.zig").eligibleSelection(dispositions, selected.value.claim_ids)) return invalid;
        for (assignments[0..assignment_index]) |earlier| if (earlier.signal_id.ordinal == assignment.signal_id.ordinal) return invalid;
        for (assignment.generation_roles, 0..) |role, index| for (assignment.generation_roles[0..index]) |earlier| {
            if (role == earlier) return invalid;
        };
    }
    return null;
}
