//! One development quality policy over native rubric accounting. It grants no
//! workflow authority and supplies no threshold or critical-score defaults.
const std = @import("std");
const c = @import("contracts.zig");
const judgment = @import("judgment.zig");

pub const Failure = enum { critical_failed, threshold_failed };
pub const Unresolved = enum { missing_threshold, uncertainty, no_applicable };
pub const Quality = union(enum) { passed, failed: Failure, unresolved: Unresolved };

/// The rubric and judgment have already passed their closed validators. Known
/// failure remains failure when another criterion or the aggregate is unresolved.
pub fn quality(rubric: c.Rubric, result: judgment.Result) Quality {
    var critical_unresolved = false;
    for (rubric.criteria) |criterion| {
        const minimum = criterion.minimum_acceptable_score orelse continue;
        const observed = for (result.results) |candidate| {
            if (std.mem.eql(u8, criterion.id, candidate.criterion_id)) break candidate;
        } else {
            critical_unresolved = true;
            continue;
        };
        switch (observed.disposition) {
            .scored => if (observed.score) |score| {
                if (score < minimum) return .{ .failed = .critical_failed };
            } else {
                critical_unresolved = true;
            },
            .uncertain, .not_applicable => critical_unresolved = true,
        }
    }
    if (result.threshold == .not_met) return .{ .failed = .threshold_failed };
    if (rubric.pass_threshold_percent == null or result.threshold == .not_configured) return .{ .unresolved = .missing_threshold };
    if (critical_unresolved or result.assessment == .unresolved) return .{ .unresolved = .uncertainty };
    if (result.assessment == .no_applicable_criteria) return .{ .unresolved = .no_applicable };
    if (result.threshold != .met) return .{ .unresolved = .uncertainty };
    return .passed;
}
