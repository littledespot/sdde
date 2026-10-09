//! Conditional semantic counts; unusable candidates remain a separate outcome.
const std = @import("std");
const c = @import("contracts.zig");
const r = @import("../../../src/domain/reference_reconciliation.zig");
const roles = @import("../../../src/domain/reference_role_assignment.zig");
const debug = @import("../../../src/domain/request_debugger.zig");
pub const Counts = struct {
    required_roles: u32 = 0,
    missing_supported_roles: u32 = 0,
    assigned_pairs: u32 = 0,
    unsupported_pairs: u32 = 0,
};
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
    const bytes = try std.json.Stringify.valueAlloc(a, validation.parsed orelse return .protocol_rejected, .{});
    const decoded = @import("../../../src/domain/model_candidate_json.zig").decodeSelected(@import("../../../src/domain/reference_reconciliation_stage.zig").Response, a, .roles, bytes) catch |err| return if (err == error.OutOfMemory) err else Outcome.protocol_rejected;
    const assignments = decoded.roles.role_assignments;
    if (try roles.check(facts.dispositions, facts.signals, assignments)) |issue| return .{ .native_rejected = issue };
    var counts: Counts = .{};
    for (labels) |label| {
        var supported = false;
        if (label.required) counts.required_roles += 1;
        for (assignments) |assignment| for (assignment.generation_roles) |role| {
            if (role != label.role) continue;
            counts.assigned_pairs += 1;
            if (r.contains(r.SignalSelectionId, label.allowed_signal_ids, assignment.signal_id)) supported = true else counts.unsupported_pairs += 1;
        };
        if (label.required and !supported) counts.missing_supported_roles += 1;
    }
    return .{ .scored = counts };
}
