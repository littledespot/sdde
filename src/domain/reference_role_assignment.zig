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

/// Admit the complete assessment before deriving sparse positive source bindings.
/// The caller owns the assignment slice and each generation_roles slice.
pub fn admit(a: std.mem.Allocator, dispositions: []const r.ClaimDisposition, offered: []const Group, decisions: r.RoleDecisions) r.Error!r.diagnostic.Check([]const r.RoleAssignment) {
    for (offered, 0..) |group, index| {
        if (group.signal_id.ordinal == 0) return error.InvalidReferenceReconciliation;
        for (offered[0..index]) |earlier| if (earlier.signal_id.ordinal == group.signal_id.ordinal) return error.InvalidReferenceReconciliation;
    }
    inline for (@typeInfo(r.GenerationRole).@"enum".fields) |role| {
        switch (@field(decisions, role.name)) {
            .unsupported => {},
            .supported => |selection| {
                if (selection.signal_ids.len == 0) return .{ .invalid = invalidSelection(0) };
                for (selection.signal_ids, 0..) |id, index| {
                    if (id.ordinal == 0 or r.contains(r.SignalSelectionId, selection.signal_ids[0..index], id)) return .{ .invalid = invalidSelection(id.ordinal) };
                    const present = for (offered) |group| {
                        if (group.signal_id.ordinal == id.ordinal) break true;
                    } else false;
                    if (!present) return .{ .invalid = invalidSelection(id.ordinal) };
                }
            },
        }
    }
    var result: std.ArrayList(r.RoleAssignment) = .empty;
    defer result.deinit(a);
    var transferred = false;
    defer if (!transferred) for (result.items) |assignment| a.free(assignment.generation_roles);
    for (offered) |group| {
        var selected: std.ArrayList(r.GenerationRole) = .empty;
        defer selected.deinit(a);
        inline for (@typeInfo(r.GenerationRole).@"enum".fields) |role| {
            if (@field(decisions, role.name) == .supported and r.contains(r.SignalSelectionId, @field(decisions, role.name).supported.signal_ids, group.signal_id)) try selected.append(a, @enumFromInt(role.value));
        }
        if (selected.items.len == 0) continue;
        const generation_roles = try selected.toOwnedSlice(a);
        errdefer a.free(generation_roles);
        try result.append(a, .{ .signal_id = group.signal_id, .generation_roles = generation_roles });
    }
    if (try check(dispositions, offered, result.items)) |issue| return .{ .invalid = issue };
    const assignments = try result.toOwnedSlice(a);
    transferred = true;
    return .{ .valid = assignments };
}

fn invalidSelection(id: u32) r.diagnostic.Issue {
    return .{ .rule = .role_assignment, .observed = .{ .count = id }, .expected = .{ .constraint = .supported_role_assignment } };
}
