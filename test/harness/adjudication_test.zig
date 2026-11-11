const std = @import("std");
const adjudication = @import("adjudication.zig");
const judgment = @import("judgment.zig");
const native = @import("e2e/contracts.zig");
const fixture = @import("e2e/acceptance_test.zig");

fn record(a: std.mem.Allocator, proposal: judgment.Proposal) ![]const u8 {
    const value: adjudication.Record = .{
        .schema = .@"spec-adjudication-record/v1",
        .reviewer = "unit-fixture-reviewer",
        .reviewed_at_utc = "2026-10-17T01:00:00Z",
        .proposal = proposal,
    };
    return std.json.Stringify.valueAlloc(a, value, .{});
}

fn bytes(a: std.mem.Allocator, report: native.Report) ![]const u8 {
    return std.json.Stringify.valueAlloc(a, report, .{});
}

test "a record's judgment decides acceptance and the decision carries no hash" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const report = try fixture.completed(a);
    const proposal: judgment.Proposal = .{ .results = &fixture.passing };
    const original = try bytes(a, report);
    const result = try adjudication.evaluate(a, try record(a, proposal), original);
    try std.testing.expectEqual(.passed, result.acceptance);
    try std.testing.expectEqual(@as(f64, 100), result.judgment.score_percent.?);
    try std.testing.expectEqualStrings("unit-fixture-reviewer", result.reviewer);
    // The native report is immutable; adjudication is a separate projection.
    try std.testing.expectEqualStrings(original, try bytes(a, report));
    // The adjudication directory keeps copies of the report and the record instead.
    const decision = try std.json.Stringify.valueAlloc(a, result, .{});
    try std.testing.expect(std.mem.startsWith(u8, decision, "{\"schema\":\"spec-adjudication/v3\","));
    try std.testing.expect(std.mem.indexOf(u8, decision, "sha256") == null);
}

test "scores retain critical aggregate and uncertainty decisions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const report = try fixture.completed(a);
    const original = try bytes(a, report);
    const results = try a.dupe(judgment.CriterionResult, &fixture.passing);
    results[0].score = 2;
    const critical = try adjudication.evaluate(a, try record(a, .{ .results = results }), original);
    try std.testing.expectEqual(@as(f64, 95), critical.judgment.score_percent.?);
    try std.testing.expectEqual(.critical_failed, critical.acceptance.failed);
    results[0].score = 3;
    results[1].score = 3;
    const aggregate = try adjudication.evaluate(a, try record(a, .{ .results = results }), original);
    try std.testing.expectEqual(@as(f64, 75), aggregate.judgment.score_percent.?);
    try std.testing.expectEqual(.threshold_failed, aggregate.acceptance.failed);
    results[0].score = 4;
    results[1].score = null;
    results[1].disposition = .uncertain;
    const uncertain = try adjudication.evaluate(a, try record(a, .{ .results = results }), original);
    try std.testing.expectEqual(.grading_unresolved, uncertain.acceptance.unresolved);
}

test "a record cannot override native failure clarification publication or admission evidence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for (std.enums.values(enum { workflow, blocked, clarification, publication, admission, evidence })) |fault| {
        var report = try fixture.completed(a);
        const proposal: judgment.Proposal = .{ .results = &fixture.passing };
        switch (fault) {
            .workflow => report.workflow_outcome = .failed,
            .blocked => {
                report.status = .workflow_blocked;
                report.workflow_outcome = .blocked;
            },
            .clarification => {
                report.status = .awaiting_clarification;
                report.workflow_outcome = .needs_user;
            },
            .publication => report.publication_check = .failed,
            .admission => report.admission_audit = null,
            .evidence => report.evidence_error = "EvidenceCaptureFailed",
        }
        const original = try bytes(a, report);
        const result = try adjudication.evaluate(a, try record(a, proposal), original);
        switch (fault) {
            .workflow, .blocked => try std.testing.expectEqual(.native_workflow_failed, result.acceptance.failed),
            .clarification => try std.testing.expectEqual(.unexpected_outcome, result.acceptance.failed),
            .publication => try std.testing.expectEqual(.publication_failed, result.acceptance.failed),
            .admission => try std.testing.expectEqual(.missing_admission_evidence, result.acceptance.unresolved),
            .evidence => try std.testing.expectEqual(.harness_failed, result.acceptance.failed),
        }
    }
}

test "adjudication rejects foreign criteria and missing or forged native capture" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var report = try fixture.completed(a);
    const proposal: judgment.Proposal = .{ .results = &fixture.passing };
    const original = try bytes(a, report);
    const results = try a.dupe(judgment.CriterionResult, proposal.results);
    results[0].criterion_id = "foreign-criterion";
    try std.testing.expectError(error.InvalidAdjudication, adjudication.evaluate(a, try record(a, .{ .results = results }), original));
    report.evaluation_inputs = null;
    const no_capture = try bytes(a, report);
    try std.testing.expectError(error.InvalidAdjudication, adjudication.evaluate(a, try record(a, proposal), no_capture));
    report = try fixture.completed(a);
    report.evaluation_inputs.?.rubric.revision += 1;
    const forged_capture = try bytes(a, report);
    try std.testing.expectError(error.InvalidAdjudication, adjudication.evaluate(a, try record(a, proposal), forged_capture));
}

test "adjudication record and original E2E report are closed explicitly versioned contracts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const report = try fixture.completed(a);
    const original = try bytes(a, report);
    const valid = try record(a, .{ .results = &fixture.passing });
    for ([_][2][]const u8{
        // The retired schema name and an unknown version are rejected.
        .{ "spec-adjudication-record/v1", "human-spec-adjudication/v2" },
        .{ "spec-adjudication-record/v1", "spec-adjudication-record/v2" },
        .{ "\"reviewer\":", "\"approved\":true,\"reviewer\":" },
        .{ "unit-fixture-reviewer", "" },
        .{ "2026-10-17T01:00:00Z", "2026-02-30T01:00:00Z" },
        // The record carries no report hash; the run is named by --report.
        .{ "\"reviewer\":", "\"report_sha256\":\"0\",\"reviewer\":" },
        // The retired pending/reviewed wrapper is not readable record content.
        .{ "\"reviewer\":", "\"outcome\":{\"pending\":{}},\"reviewer\":" },
    }) |replacement| {
        const invalid = try std.mem.replaceOwned(u8, a, valid, replacement[0], replacement[1]);
        try std.testing.expectError(error.InvalidAdjudication, adjudication.evaluate(a, invalid, original));
    }
    for ([_][2][]const u8{
        .{ "spec-e2e-report/v16", "spec-e2e-report/v15" },
        .{ "\"origin\":\"live\",", "" },
        .{ "\"schema\":\"spec-e2e-report/v16\",", "" },
        .{ "\"status\":", "\"untrusted_pass\":true,\"status\":" },
        // Retired advisory-grader fields are not readable report content.
        .{ "\"status\":", "\"evaluation\":null,\"status\":" },
        .{ "\"status\":", "\"semantic_quality\":\"not_run\",\"status\":" },
        .{ "\"status\":", "\"evaluation_configuration\":null,\"status\":" },
        .{ "\"status\":", "\"grader_qualification\":null,\"status\":" },
        // Retired advisory-grader statuses are not readable report content.
        .{ "\"status\":\"generated\"", "\"status\":\"evaluated\"" },
        .{ "\"status\":\"generated\"", "\"status\":\"evaluator_failed\"" },
        .{ "\"status\":\"generated\"", "\"status\":\"quality_unresolved\"" },
    }) |replacement| {
        const invalid = try std.mem.replaceOwned(u8, a, original, replacement[0], replacement[1]);
        try std.testing.expectError(error.InvalidAdjudication, adjudication.evaluate(a, valid, invalid));
    }
}
