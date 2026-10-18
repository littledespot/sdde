const std = @import("std");
const human = @import("human_adjudication.zig");
const judgment = @import("judgment.zig");
const native = @import("e2e/contracts.zig");
const fixture = @import("e2e/acceptance_test.zig");

fn reviewed(a: std.mem.Allocator, original: []const u8, proposal: judgment.Proposal) ![]const u8 {
    const value: human.Review = .{
        .schema = .@"human-spec-adjudication/v2",
        .outcome = .{ .reviewed = .{
            .reviewer = "unit-fixture-human",
            .reviewed_at_utc = "2026-10-17T01:00:00Z",
            .report_sha256 = try @import("grader_qualification.zig").sha256(a, original),
            .proposal = proposal,
        } },
    };
    return std.json.Stringify.valueAlloc(a, value, .{});
}

fn bytes(a: std.mem.Allocator, report: native.Report) ![]const u8 {
    return std.json.Stringify.valueAlloc(a, report, .{});
}

test "pending human adjudication records exact identity without fabricating a review" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const report = try fixture.completed(a);
    const original = try bytes(a, report);
    const review = "{\"schema\":\"human-spec-adjudication/v2\",\"outcome\":{\"pending\":{}}}";
    const result = try human.evaluate(a, review, original);
    try std.testing.expectEqual(.human_adjudication_required, result.acceptance.unresolved);
    try std.testing.expect(result.reviewer == null);
    try std.testing.expect(result.reviewed_at_utc == null);
    try std.testing.expect(result.human_judgment == null);
    try std.testing.expectEqualStrings(try @import("grader_qualification.zig").sha256(a, original), result.original_report_sha256);
    try std.testing.expectEqualStrings(try @import("grader_qualification.zig").sha256(a, review), result.review_sha256);
}

test "pending human review preserves known native blocked and unexpected clarification failures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const pending = "{\"schema\":\"human-spec-adjudication/v2\",\"outcome\":{\"pending\":{}}}";
    var report = try fixture.completed(a);
    report.status = .workflow_blocked;
    report.workflow_outcome = .blocked;
    const blocked = try human.evaluate(a, pending, try bytes(a, report));
    try std.testing.expectEqual(.native_workflow_failed, blocked.acceptance.failed);
    report.status = .awaiting_clarification;
    report.workflow_outcome = .needs_user;
    const clarification = try human.evaluate(a, pending, try bytes(a, report));
    try std.testing.expectEqual(.unexpected_outcome, clarification.acceptance.failed);
    report = .{ .schema = .@"spec-e2e-report/v6", .started_at_utc = "2026-10-17T00:00:00Z", .status = .generated };
    const ungraded = try human.evaluate(a, pending, try bytes(a, report));
    try std.testing.expectEqual(.missing_expected_outcome, ungraded.acceptance.unresolved);
}

test "human final authority validates captured publication even when advisory evaluation failed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var report = try fixture.completed(a);
    const proposal: judgment.Proposal = .{ .results = report.evaluation.?.outcome.evaluated.results };
    report.evaluation = null;
    report.status = .evaluator_failed;
    report.semantic_quality = .evaluator_error;
    const original = try bytes(a, report);
    const result = try human.evaluate(a, try reviewed(a, original, proposal), original);
    try std.testing.expectEqual(.passed, result.acceptance);
    try std.testing.expectEqual(@as(f64, 100), result.human_judgment.?.score_percent.?);
    try std.testing.expectEqualStrings("unit-fixture-human", result.reviewer.?);
    // The native report is immutable; adjudication is a separate projection.
    try std.testing.expectEqualStrings(original, try bytes(a, report));
}

test "human scores retain critical aggregate and uncertainty decisions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const report = try fixture.completed(a);
    const original = try bytes(a, report);
    const results = try a.dupe(judgment.CriterionResult, report.evaluation.?.outcome.evaluated.results);
    results[0].score = 2;
    const critical = try human.evaluate(a, try reviewed(a, original, .{ .results = results }), original);
    try std.testing.expectEqual(@as(f64, 95), critical.human_judgment.?.score_percent.?);
    try std.testing.expectEqual(.critical_failed, critical.acceptance.failed);
    results[0].score = 3;
    results[1].score = 3;
    const aggregate = try human.evaluate(a, try reviewed(a, original, .{ .results = results }), original);
    try std.testing.expectEqual(@as(f64, 75), aggregate.human_judgment.?.score_percent.?);
    try std.testing.expectEqual(.threshold_failed, aggregate.acceptance.failed);
    results[0].score = 4;
    results[1].score = null;
    results[1].disposition = .uncertain;
    const uncertain = try human.evaluate(a, try reviewed(a, original, .{ .results = results }), original);
    try std.testing.expectEqual(.grading_unresolved, uncertain.acceptance.unresolved);
}

test "human review cannot override native failure publication or admission evidence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for (std.enums.values(enum { workflow, publication, admission, evidence })) |fault| {
        var report = try fixture.completed(a);
        const proposal: judgment.Proposal = .{ .results = report.evaluation.?.outcome.evaluated.results };
        switch (fault) {
            .workflow => report.workflow_outcome = .failed,
            .publication => report.publication_check = .failed,
            .admission => report.admission_audit = null,
            .evidence => report.evidence_error = "EvidenceCaptureFailed",
        }
        const original = try bytes(a, report);
        const result = try human.evaluate(a, try reviewed(a, original, proposal), original);
        switch (fault) {
            .workflow => try std.testing.expectEqual(.native_workflow_failed, result.acceptance.failed),
            .publication => try std.testing.expectEqual(.publication_failed, result.acceptance.failed),
            .admission => try std.testing.expectEqual(.missing_admission_evidence, result.acceptance.unresolved),
            .evidence => try std.testing.expectEqual(.harness_failed, result.acceptance.failed),
        }
    }
}

test "human adjudication rejects stale report foreign criteria and missing native capture" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var report = try fixture.completed(a);
    const proposal: judgment.Proposal = .{ .results = report.evaluation.?.outcome.evaluated.results };
    const original = try bytes(a, report);
    const review = try reviewed(a, original, proposal);
    const changed = try std.mem.concat(a, u8, &.{ original, "\n" });
    try std.testing.expectError(error.InvalidHumanAdjudication, human.evaluate(a, review, changed));
    const results = try a.dupe(judgment.CriterionResult, proposal.results);
    results[0].criterion_id = "foreign-criterion";
    try std.testing.expectError(error.InvalidHumanAdjudication, human.evaluate(a, try reviewed(a, original, .{ .results = results }), original));
    report.evaluation_inputs = null;
    const no_capture = try bytes(a, report);
    try std.testing.expectError(error.InvalidHumanAdjudication, human.evaluate(a, try reviewed(a, no_capture, proposal), no_capture));
    report = try fixture.completed(a);
    report.evaluation_inputs.?.rubric.revision += 1;
    const forged_capture = try bytes(a, report);
    try std.testing.expectError(error.InvalidHumanAdjudication, human.evaluate(a, try reviewed(a, forged_capture, proposal), forged_capture));
}

test "human declaration and original E2E report are closed explicitly versioned contracts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const report = try fixture.completed(a);
    const original = try bytes(a, report);
    const review = try reviewed(a, original, .{ .results = report.evaluation.?.outcome.evaluated.results });
    for ([_][2][]const u8{
        .{ "human-spec-adjudication/v2", "human-spec-adjudication/v1" },
        .{ "\"reviewer\":", "\"approved\":true,\"reviewer\":" },
        .{ "unit-fixture-human", "" },
        .{ "2026-10-17T01:00:00Z", "2026-02-30T01:00:00Z" },
    }) |replacement| {
        const invalid = try std.mem.replaceOwned(u8, a, review, replacement[0], replacement[1]);
        try std.testing.expectError(error.InvalidHumanAdjudication, human.evaluate(a, invalid, original));
    }
    const pending = "{\"schema\":\"human-spec-adjudication/v2\",\"outcome\":{\"pending\":{}}}";
    for ([_][2][]const u8{
        .{ "spec-e2e-report/v6", "spec-e2e-report/v5" },
        .{ "\"origin\":\"live\",", "" },
        .{ "\"schema\":\"spec-e2e-report/v6\",", "" },
        .{ "\"status\":", "\"untrusted_pass\":true,\"status\":" },
    }) |replacement| {
        const invalid = try std.mem.replaceOwned(u8, a, original, replacement[0], replacement[1]);
        try std.testing.expectError(error.InvalidHumanAdjudication, human.evaluate(a, pending, invalid));
    }
}
