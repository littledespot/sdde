//! Development labels are never model-visible or workflow authority.
const std = @import("std");
const c = @import("../contracts.zig");
const r = @import("../../../src/domain/reference_reconciliation.zig");
pub const Label = struct {
    role: r.GenerationRole,
    required: bool,
    allowed_signal_ids: []const r.SignalSelectionId,
};
pub const Source = struct { text: []const u8, kind: ?r.extraction.Kind };
pub const Capture = struct { feature: []const u8, run: []const u8, call: []const u8 };
pub const Case = struct {
    id: []const u8,
    family: []const u8,
    split: enum { development, held_out },
    input: union(enum) { controlled: []const Source, captured: Capture },
    labels: []const Label,
    rationale: []const u8,
};
pub const Cohort = struct {
    schema: enum { @"role-calibration/v1" },
    label_status: enum { proposed, reviewed },
    reviewer: ?[]const u8,
    cases: []const Case,
};
pub fn parse(a: std.mem.Allocator, bytes: []const u8) c.Error!Cohort {
    const value = try c.decode(Cohort, a, bytes);
    if (value.cases.len == 0 or (value.label_status == .reviewed) != (value.reviewer != null)) return error.InvalidEvaluationContract;
    if (value.reviewer) |reviewer| if (!c.text(reviewer)) return error.InvalidEvaluationContract;
    for (value.cases, 0..) |entry, index| {
        if (!c.id(entry.id) or !c.id(entry.family) or entry.rationale.len == 0 or entry.labels.len != std.meta.tags(r.GenerationRole).len) return error.InvalidEvaluationContract;
        for (value.cases[0..index]) |prior| {
            if (std.mem.eql(u8, prior.id, entry.id) or (std.mem.eql(u8, prior.family, entry.family) and prior.split != entry.split)) return error.InvalidEvaluationContract;
        }
        switch (entry.input) {
            .controlled => |sources| {
                if (sources.len == 0) return error.InvalidEvaluationContract;
                for (sources) |source| if (source.text.len == 0) return error.InvalidEvaluationContract;
            },
            .captured => |selected| try capture(selected),
        }
        for (entry.labels, 0..) |label, label_index| {
            if (label.required and label.allowed_signal_ids.len == 0) return error.InvalidEvaluationContract;
            for (entry.labels[0..label_index]) |prior| if (prior.role == label.role) return error.InvalidEvaluationContract;
            r.unique(r.SignalSelectionId, label.allowed_signal_ids) catch return error.InvalidEvaluationContract;
        }
    }
    return value;
}
fn capture(value: Capture) c.Error!void {
    try c.path(value.feature);
    if (!c.id(value.run) or !c.id(value.call)) return error.InvalidEvaluationContract;
}
