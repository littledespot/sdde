//! Pure accounting for source-backed expected finding kinds. Native admission
//! is not correctness; unknown labels/coverage never become true positives.
const std = @import("std");
const assessment = @import("assessment.zig");
const reviews = @import("reviews.zig");
const kind_count = std.meta.tags(@FieldType(reviews.Kind, "source")).len + std.meta.tags(@FieldType(reviews.Kind, "principles")).len + std.meta.tags(@FieldType(reviews.Kind, "preservation")).len;

pub const Workload = struct { findings: []const assessment.FindingResult, coverage: []const assessment.ReviewCoverage };
pub const Counts = struct { correct: u64 = 0, incorrect: u64 = 0, unknown: u64 = 0 };
pub const KindAccuracy = struct {
    kind: reviews.Kind,
    predicted: u64 = 0,
    expected: u64 = 0,
    true_positive: u64 = 0,
    false_positive: u64 = 0,
    false_negative: u64 = 0,
    unknown_predicted: u64 = 0,
    unknown_expected: u64 = 0,
    coverage_complete: bool = true,
    precision_numerator: u64 = 0,
    precision_denominator: u64 = 0,
    precision: ?f64 = null,
    recall_numerator: u64 = 0,
    recall_denominator: u64 = 0,
    recall: ?f64 = null,
};
pub const Window = struct {
    counts: Counts = .{},
    by_kind: [kind_count]KindAccuracy,
    /// Rows are predicted kinds, columns expected kinds, in by_kind order.
    confusion: [kind_count][kind_count]u64 = @splat(@splat(0)),
    evidence_complete: bool = true,
};
pub const Report = struct {
    status: enum { complete, incomplete, unmeasured },
    scope: enum { typed_native_review_findings } = .typed_native_review_findings,
    native_review_bearing_sends: u64 = 0,
    captured_review_outputs: u64 = 0,
    unmeasured_review_responses: u64 = 0,
    typed_findings: u64 = 0,
    all: Window,
    /// First/latest finding per native subject, independently within each trial.
    original: Window,
    final: Window,
    corrective: Window,
    workflow_authority: bool = false,
};

fn emptyWindow() Window {
    var result: Window = .{ .by_kind = undefined };
    var at: usize = 0;
    inline for (.{ "source", "principles", "preservation" }) |domain| {
        for (std.meta.tags(@FieldType(reviews.Kind, domain))) |kind| {
            result.by_kind[at] = .{ .kind = @unionInit(reviews.Kind, domain, kind) };
            at += 1;
        }
    }
    return result;
}
fn kindIndex(kind: reviews.Kind) usize {
    const kinds = emptyWindow().by_kind;
    for (kinds, 0..) |value, index| if (std.meta.eql(value.kind, kind)) return index;
    unreachable; // Every value of the closed union was enumerated above.
}
fn sameSubject(left: reviews.Finding, right: reviews.Finding) bool {
    if (std.meta.activeTag(left.kind) != std.meta.activeTag(right.kind) or !std.meta.eql(left.requirement, right.requirement)) return false;
    return left.kind != .preservation or left.ordinal == right.ordinal;
}
fn increment(value: *u64) !void {
    value.* = std.math.add(u64, value.*, 1) catch return error.AccountingOverflow;
}
fn unknownCoverage(window: *Window, review: ?reviews.Review) void {
    window.evidence_complete = false;
    for (&window.by_kind) |*kind| if (review == null or std.meta.activeTag(kind.kind) == review.?) {
        kind.coverage_complete = false;
    };
}
fn count(window: *Window, finding: assessment.FindingResult) !void {
    const predicted = kindIndex(finding.native.kind);
    try increment(&window.by_kind[predicted].predicted);
    const expected = if (!finding.disputed) finding.expected_kind else null;
    const correct = if (!finding.disputed) finding.correct else null;
    if (correct == null or expected == null) {
        try increment(&window.counts.unknown);
        try increment(&window.by_kind[predicted].unknown_predicted);
        const domain = std.meta.activeTag(finding.native.kind);
        for (&window.by_kind) |*kind| if (std.meta.activeTag(kind.kind) == domain) {
            try increment(&kind.unknown_expected);
        };
        window.evidence_complete = false;
        return;
    }
    if (std.meta.activeTag(expected.?) != std.meta.activeTag(finding.native.kind) or correct.? != std.meta.eql(expected.?, finding.native.kind)) return error.InvalidFindingAccuracy;
    const target = kindIndex(expected.?);
    try increment(&window.by_kind[target].expected);
    try increment(&window.confusion[predicted][target]);
    if (correct.?) {
        try increment(&window.counts.correct);
        try increment(&window.by_kind[predicted].true_positive);
    } else {
        try increment(&window.counts.incorrect);
        try increment(&window.by_kind[predicted].false_positive);
        try increment(&window.by_kind[target].false_negative);
    }
}
fn finish(window: *Window) void {
    for (&window.by_kind) |*kind| {
        kind.precision_numerator = kind.true_positive;
        kind.precision_denominator = kind.predicted;
        kind.recall_numerator = kind.true_positive;
        kind.recall_denominator = kind.expected;
        if (kind.coverage_complete and kind.unknown_predicted == 0 and kind.predicted != 0) kind.precision = @as(f64, @floatFromInt(kind.true_positive)) / @as(f64, @floatFromInt(kind.predicted));
        if (kind.coverage_complete and kind.unknown_expected == 0 and kind.expected != 0) kind.recall = @as(f64, @floatFromInt(kind.true_positive)) / @as(f64, @floatFromInt(kind.expected));
    }
}

/// No output borrows workload data: kinds, counts and the confusion matrix are
/// fixed closed values. The allocator argument matches other report reducers.
pub fn summarize(a: std.mem.Allocator, workloads: []const Workload) !Report {
    _ = a;
    var result: Report = .{ .status = .unmeasured, .all = emptyWindow(), .original = emptyWindow(), .final = emptyWindow(), .corrective = emptyWindow() };
    for (workloads) |workload| {
        for (workload.coverage) |coverage| {
            try increment(&result.native_review_bearing_sends);
            if (coverage.output_id != null) try increment(&result.captured_review_outputs);
            if (!coverage.projected or coverage.output_id == null) {
                try increment(&result.unmeasured_review_responses);
                unknownCoverage(&result.all, coverage.review);
                unknownCoverage(&result.original, coverage.review);
                unknownCoverage(&result.final, coverage.review);
                unknownCoverage(&result.corrective, coverage.review);
            }
        }
        for (workload.findings, 0..) |finding, index| {
            try increment(&result.typed_findings);
            var matched = false;
            for (workload.coverage) |coverage| if (std.meta.eql(coverage.origin, finding.native.origin) and coverage.projected and coverage.output_id != null and coverage.review != null and coverage.review.? == std.meta.activeTag(finding.native.kind)) {
                matched = true;
            };
            if (!matched) {
                unknownCoverage(&result.all, std.meta.activeTag(finding.native.kind));
                unknownCoverage(&result.original, std.meta.activeTag(finding.native.kind));
                unknownCoverage(&result.final, std.meta.activeTag(finding.native.kind));
                unknownCoverage(&result.corrective, std.meta.activeTag(finding.native.kind));
            }
            try count(&result.all, finding);
            if (finding.corrective) try count(&result.corrective, finding);
            const first = for (workload.findings[0..index]) |prior| {
                if (sameSubject(prior.native, finding.native)) break false;
            } else true;
            const last = for (workload.findings[index + 1 ..]) |next| {
                if (sameSubject(next.native, finding.native)) break false;
            } else true;
            if (first) try count(&result.original, finding);
            if (last) try count(&result.final, finding);
        }
    }
    finish(&result.all);
    finish(&result.original);
    finish(&result.final);
    finish(&result.corrective);
    if (result.native_review_bearing_sends != 0 or result.typed_findings != 0) result.status = if (result.all.evidence_complete) .complete else .incomplete;
    return result;
}

fn testFinding(request: usize, predicted: reviews.Kind, expected: ?reviews.Kind) assessment.FindingResult {
    return .{
        .native = .{ .ordinal = 1, .origin = .{ .request = .{ .value = request }, .attempt = .{ .value = 1 } }, .requirement = .{ .kind = .reference_meaning, .unit = .{ .source = .{ .ordinal = 1 } }, .slot = .disposition }, .kind = predicted, .detail = "Typed native finding.", .source_ids = &.{.{ .ordinal = 1 }}, .principle_citations = &.{}, .missing_obligation = null, .question = null, .authority_gap = null, .admission = .accepted },
        .corrective = request != 1,
        .correct = if (expected) |value| std.meta.eql(predicted, value) else null,
        .expected_kind = expected,
        .provenance = null,
        .disputed = false,
    };
}
fn testCoverage(request: usize, review: reviews.Review) assessment.ReviewCoverage {
    return .{ .origin = .{ .request = .{ .value = request }, .attempt = .{ .value = 1 } }, .output_id = "native-output", .review = review, .projected = true };
}

test "finding precision recall and confusion retain wrong routing and corrected subject windows" {
    const findings = [_]assessment.FindingResult{
        testFinding(1, .{ .source = .candidate_omission }, .{ .source = .candidate_invalid }),
        testFinding(2, .{ .source = .candidate_invalid }, .{ .source = .candidate_invalid }),
    };
    const report = try summarize(std.testing.allocator, &.{.{ .findings = &findings, .coverage = &.{ testCoverage(1, .source), testCoverage(2, .source) } }});
    try std.testing.expectEqual(.complete, report.status);
    try std.testing.expectEqual(@as(u64, 1), report.original.counts.incorrect);
    try std.testing.expectEqual(@as(u64, 1), report.final.counts.correct);
    try std.testing.expectEqual(@as(u64, 1), report.corrective.counts.correct);
    const omission = kindIndex(.{ .source = .candidate_omission });
    const invalid = kindIndex(.{ .source = .candidate_invalid });
    try std.testing.expectEqual(@as(?f64, 0), report.all.by_kind[omission].precision);
    try std.testing.expectEqual(@as(?f64, 0.5), report.all.by_kind[invalid].recall);
    try std.testing.expectEqual(@as(u64, 1), report.all.confusion[omission][invalid]);
    try std.testing.expectEqual(@as(u64, 1), report.all.confusion[invalid][invalid]);
    try std.testing.expect(!report.workflow_authority);
}

test "finding windows never join unrelated trials or distinct preservation comparisons" {
    var first = testFinding(1, .{ .preservation = .lost }, .{ .preservation = .preserved });
    var second = testFinding(1, .{ .preservation = .preserved }, .{ .preservation = .preserved });
    first.native.ordinal = 1;
    second.native.ordinal = 2;
    const report = try summarize(std.testing.allocator, &.{
        .{ .findings = &.{ first, second }, .coverage = &.{testCoverage(1, .preservation)} },
        .{ .findings = &.{first}, .coverage = &.{testCoverage(1, .preservation)} },
    });
    try std.testing.expectEqual(@as(u64, 2), report.original.counts.incorrect);
    try std.testing.expectEqual(@as(u64, 1), report.original.counts.correct);
    try std.testing.expectEqual(report.original.counts, report.final.counts);
}

test "unprojected and unlabelled finding evidence cannot invent recall or zero denominator success" {
    const finding = testFinding(1, .{ .source = .supported }, null);
    var missing = testCoverage(2, .source);
    missing.projected = false;
    const report = try summarize(std.testing.allocator, &.{.{ .findings = &.{finding}, .coverage = &.{ testCoverage(1, .source), missing } }});
    try std.testing.expectEqual(.incomplete, report.status);
    try std.testing.expectEqual(@as(u64, 1), report.all.counts.unknown);
    for (report.all.by_kind) |kind| if (kind.kind == .source) {
        try std.testing.expect(kind.recall == null and kind.precision == null);
    };
    const empty = try summarize(std.testing.allocator, &.{.{ .findings = &.{}, .coverage = &.{testCoverage(1, .preservation)} }});
    try std.testing.expectEqual(.complete, empty.status);
    for (empty.all.by_kind) |kind| try std.testing.expect(kind.precision == null and kind.recall == null);
    try std.testing.expectEqual(.unmeasured, (try summarize(std.testing.allocator, &.{})).status);
}
