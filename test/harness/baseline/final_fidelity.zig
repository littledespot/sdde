//! Supplied final-current-content fidelity after the correction/repair chain.
//! This component neither infers semantic labels nor claims useful publication.
const std = @import("std");
const contracts = @import("../contracts.zig");
pub const Workload = struct {
    feature_id: []const u8,
    well_posed: bool,
    attempted: bool,
    final_fidelity: ?bool,
};
pub const Feature = struct {
    feature_id: []const u8,
    well_posed_attempted: u32 = 0,
    well_posed_unattempted: u32 = 0,
    successes: u32 = 0,
    failures: u32 = 0,
    unknown: u32 = 0,
    rate: ?f64 = null,
    /// Bounds expose missing judgments without labelling them failures.
    lower_bound: ?f64 = null,
    upper_bound: ?f64 = null,
};
pub const Report = struct {
    scope: enum { diagnostic_final_current_content, native_published_useful_completion } = .diagnostic_final_current_content,
    features: []const Feature,
    independent_features_with_attempts: u32,
    well_posed_attempted: u32,
    well_posed_unattempted: u32,
    successes: u32,
    failures: u32,
    unknown: u32,
    rate: ?f64,
    lower_bound: ?f64,
    upper_bound: ?f64,
    evidence_complete: bool,
    useful_completion_claim: bool = false,
    workflow_authority: bool = false,

    /// Only the feature array is owned. Identifiers borrow the workload rows.
    pub fn deinit(self: Report, a: std.mem.Allocator) void {
        a.free(self.features);
    }
};

/// The native publication/rubric owner supplies each useful-completion verdict.
/// Only equal-feature accounting is shared with current-content fidelity here.
pub fn summarizeUseful(a: std.mem.Allocator, workloads: []const Workload) !Report {
    var report = try summarize(a, workloads);
    report.scope = .native_published_useful_completion;
    report.useful_completion_claim = true;
    return report;
}

pub fn summarize(a: std.mem.Allocator, workloads: []const Workload) !Report {
    if (workloads.len == 0 or workloads.len > std.math.maxInt(u32)) return error.InvalidFinalFidelity;
    var features: std.ArrayList(Feature) = .empty;
    errdefer features.deinit(a);
    for (workloads) |workload| {
        if (!contracts.id(workload.feature_id) or (!workload.well_posed or !workload.attempted) and workload.final_fidelity != null) return error.InvalidFinalFidelity;
        const feature: *Feature = selected: {
            for (features.items) |*feature| if (std.mem.eql(u8, feature.feature_id, workload.feature_id)) break :selected feature;
            try features.append(a, .{ .feature_id = workload.feature_id });
            break :selected &features.items[features.items.len - 1];
        };
        if (!workload.well_posed) continue;
        if (!workload.attempted) {
            feature.well_posed_unattempted += 1;
            continue;
        }
        feature.well_posed_attempted += 1;
        if (workload.final_fidelity) |faithful| {
            if (faithful) feature.successes += 1 else feature.failures += 1;
        } else feature.unknown += 1;
    }
    var result: Report = .{ .features = &.{}, .independent_features_with_attempts = 0, .well_posed_attempted = 0, .well_posed_unattempted = 0, .successes = 0, .failures = 0, .unknown = 0, .rate = null, .lower_bound = null, .upper_bound = null, .evidence_complete = false };
    var lower: f64 = 0;
    var upper: f64 = 0;
    for (features.items) |*feature| {
        result.well_posed_attempted += feature.well_posed_attempted;
        result.well_posed_unattempted += feature.well_posed_unattempted;
        result.successes += feature.successes;
        result.failures += feature.failures;
        result.unknown += feature.unknown;
        if (feature.well_posed_attempted == 0) continue;
        const n: f64 = @floatFromInt(feature.well_posed_attempted);
        feature.lower_bound = @as(f64, @floatFromInt(feature.successes)) / n;
        feature.upper_bound = @as(f64, @floatFromInt(feature.successes + feature.unknown)) / n;
        if (feature.unknown == 0 and feature.well_posed_unattempted == 0) feature.rate = feature.lower_bound;
        result.independent_features_with_attempts += 1;
        lower += feature.lower_bound.?;
        upper += feature.upper_bound.?;
    }
    if (result.independent_features_with_attempts != 0) {
        const count: f64 = @floatFromInt(result.independent_features_with_attempts);
        result.lower_bound = lower / count;
        result.upper_bound = upper / count;
        result.evidence_complete = result.unknown == 0 and result.well_posed_unattempted == 0;
        if (result.evidence_complete) result.rate = result.lower_bound;
    }
    result.features = try features.toOwnedSlice(a);
    return result;
}

test "final fidelity weights independent features equally after all well posed attempts" {
    const workloads = [_]Workload{
        .{ .feature_id = "reservation", .well_posed = true, .attempted = true, .final_fidelity = true },
        .{ .feature_id = "reservation", .well_posed = true, .attempted = true, .final_fidelity = true },
        .{ .feature_id = "reservation", .well_posed = true, .attempted = true, .final_fidelity = true },
        .{ .feature_id = "delivery", .well_posed = true, .attempted = true, .final_fidelity = false },
        .{ .feature_id = "missing-policy", .well_posed = false, .attempted = true, .final_fidelity = null },
    };
    const report = try summarize(std.testing.allocator, &workloads);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(?f64, 0.5), report.rate);
    try std.testing.expectEqual(@as(u32, 2), report.independent_features_with_attempts);
    try std.testing.expectEqual(@as(u32, 4), report.well_posed_attempted);
    try std.testing.expectEqual(@as(u32, 3), report.successes);
    try std.testing.expectEqual(@as(u32, 1), report.failures);
    try std.testing.expect(report.evidence_complete);
    try std.testing.expect(!report.useful_completion_claim and !report.workflow_authority);
}

test "unknown final judgments produce bounds and incomplete evidence without invented failures" {
    const workloads = [_]Workload{
        .{ .feature_id = "reservation", .well_posed = true, .attempted = true, .final_fidelity = true },
        .{ .feature_id = "reservation", .well_posed = true, .attempted = true, .final_fidelity = null },
        .{ .feature_id = "delivery", .well_posed = true, .attempted = true, .final_fidelity = false },
    };
    const report = try summarize(std.testing.allocator, &workloads);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.rate == null and !report.evidence_complete);
    try std.testing.expectEqual(@as(u32, 1), report.unknown);
    try std.testing.expectEqual(@as(u32, 1), report.failures);
    try std.testing.expectEqual(@as(?f64, 0.25), report.lower_bound);
    try std.testing.expectEqual(@as(?f64, 0.5), report.upper_bound);
    try std.testing.expect(report.features[0].rate == null);
}

test "unattempted final assessments stay explicit and genuine gaps cannot become completions" {
    const workloads = [_]Workload{
        .{ .feature_id = "reservation", .well_posed = true, .attempted = true, .final_fidelity = true },
        .{ .feature_id = "delivery", .well_posed = true, .attempted = false, .final_fidelity = null },
    };
    const report = try summarize(std.testing.allocator, &workloads);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.rate == null and !report.evidence_complete);
    try std.testing.expectEqual(@as(u32, 1), report.well_posed_unattempted);
    try std.testing.expectEqual(@as(u32, 0), report.failures);
    try std.testing.expectError(error.InvalidFinalFidelity, summarize(std.testing.allocator, &.{.{ .feature_id = "gap", .well_posed = false, .attempted = true, .final_fidelity = true }}));
    try std.testing.expectError(error.InvalidFinalFidelity, summarize(std.testing.allocator, &.{.{ .feature_id = "not-run", .well_posed = true, .attempted = false, .final_fidelity = false }}));
    try std.testing.expectError(error.InvalidFinalFidelity, summarize(std.testing.allocator, &.{}));
}
