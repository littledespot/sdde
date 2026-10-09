//! Conditional semantic counts; unusable candidates remain a separate outcome.
const std = @import("std");
const c = @import("contracts.zig");
const r = @import("../../../src/domain/reference_reconciliation.zig");
const roles = @import("../../../src/domain/reference_role_assignment.zig");
const debug = @import("../../../src/domain/request_debugger.zig");
pub const RoleCounts = struct {
    role: r.GenerationRole,
    required_roles: u32 = 0,
    missing_supported_roles: u32 = 0,
    false_unsupported_roles: u32 = 0,
    assigned_pairs: u32 = 0,
    unsupported_pairs: u32 = 0,
    wrong_basis_pairs: u32 = 0,
};
fn emptyRoles() [std.meta.tags(r.GenerationRole).len]RoleCounts {
    var result: [std.meta.tags(r.GenerationRole).len]RoleCounts = undefined;
    for (std.meta.tags(r.GenerationRole), &result) |role, *entry| entry.* = .{ .role = role };
    return result;
}
pub const Counts = struct {
    required_roles: u32 = 0,
    missing_supported_roles: u32 = 0,
    /// Admitted negative decisions on roles labelled as requiring support.
    /// Optional labels do not contribute, even when they permit positive support.
    false_unsupported_roles: u32 = 0,
    assigned_pairs: u32 = 0,
    unsupported_pairs: u32 = 0,
    /// Unsupported pairs whose role has at least one labelled allowed group.
    /// Empty allowed sets describe unsupported roles, not a wrong selected basis.
    wrong_basis_pairs: u32 = 0,
    by_role: [std.meta.tags(r.GenerationRole).len]RoleCounts = emptyRoles(),
};
pub const DecisionCoverage = struct {
    required_decisions: u32,
    missing_decisions: u32,
};
/// Structural observation only. Invalid JSON has unknown coverage; a present
/// decision does not establish that its branch or semantic judgment is valid.
pub fn decisionCoverage(validation: debug.Validation) ?DecisionCoverage {
    if (validation.json != .valid) return null;
    const parsed = validation.parsed orelse return null;
    if (parsed != .object) return null;
    const Role = r.GenerationRole;
    var result: DecisionCoverage = .{ .required_decisions = std.meta.tags(Role).len, .missing_decisions = 0 };
    const decisions = parsed.object.get("role_decisions");
    inline for (std.meta.tags(Role)) |role| {
        if (decisions == null or decisions.? != .object or !decisions.?.object.contains(@tagName(role))) result.missing_decisions += 1;
    }
    return result;
}
pub const Outcome = union(enum) {
    protocol_rejected,
    native_rejected: r.diagnostic.Issue,
    scored: Counts,
};
pub fn validateLabels(facts: roles.Facts, labels: []const c.Label) !void {
    for (labels) |label| for (label.allowed_signal_ids) |id| {
        const group = for (facts.signals) |value| {
            if (value.signal_id.ordinal == id.ordinal) break value;
        } else return error.InvalidEvaluationContract;
        if (!try @import("../../../src/domain/reference_support.zig").eligibleSelection(facts.dispositions, group.value.claim_ids)) return error.InvalidEvaluationContract;
    };
}
pub fn assess(a: std.mem.Allocator, facts: roles.Facts, labels: []const c.Label, validation: debug.Validation) !Outcome {
    try validateLabels(facts, labels);
    if (validation.extraction != .valid or validation.json != .valid or validation.schema != .valid) return .protocol_rejected;
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const bytes = try std.json.Stringify.valueAlloc(scratch, validation.parsed orelse return .protocol_rejected, .{});
    const decoded = @import("../../../src/domain/model_candidate_json.zig").decodeSelected(@import("../../../src/domain/reference_reconciliation_stage.zig").Response, scratch, .roles, bytes) catch |err| return if (err == error.OutOfMemory) err else Outcome.protocol_rejected;
    const decisions = decoded.roles.role_decisions;
    const assignments = switch (try roles.admit(scratch, facts.dispositions, facts.signals, decisions)) {
        .invalid => |issue| return .{ .native_rejected = issue },
        .valid => |value| value,
    };
    var counts: Counts = .{};
    for (labels) |label| {
        const detail = &counts.by_role[@intFromEnum(label.role)];
        var supported = false;
        if (label.required) {
            counts.required_roles += 1;
            detail.required_roles += 1;
            inline for (@typeInfo(r.GenerationRole).@"enum".fields) |role| {
                if (@intFromEnum(label.role) == role.value and @field(decisions, role.name) == .unsupported) {
                    counts.false_unsupported_roles += 1;
                    detail.false_unsupported_roles += 1;
                }
            }
        }
        for (assignments) |assignment| for (assignment.generation_roles) |role| {
            if (role != label.role) continue;
            counts.assigned_pairs += 1;
            detail.assigned_pairs += 1;
            if (r.contains(r.SignalSelectionId, label.allowed_signal_ids, assignment.signal_id)) {
                supported = true;
            } else {
                counts.unsupported_pairs += 1;
                detail.unsupported_pairs += 1;
                if (label.allowed_signal_ids.len != 0) {
                    counts.wrong_basis_pairs += 1;
                    detail.wrong_basis_pairs += 1;
                }
            }
        };
        if (label.required and !supported) {
            counts.missing_supported_roles += 1;
            detail.missing_supported_roles += 1;
        }
    }
    return .{ .scored = counts };
}
