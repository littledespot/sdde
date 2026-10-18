const std = @import("std");
const c = @import("contracts.zig");
const gate = @import("acceptance.zig");
const grading = @import("../contracts.zig");
const judgment = @import("../judgment.zig");

const source = "The application displays a receipt.";
const models = [_]grading.GenerationModel{.{ .slot = "MOCK-generation", .provider = "aws-bedrock", .model = "MOCK-generator" }};
const rubric_bytes =
    \\{"schema":"evaluation-rubric/v2","id":"MOCK-rubric","revision":1,"minimum_score":0,"maximum_score":4,"pass_threshold_percent":80,"criteria":[{"id":"coverage","description":"Preserve receipt display.","evidence":"Compare source and specification.","weight":1,"anchors":[{"score":0,"description":"Absent"},{"score":1,"description":"Mostly absent"},{"score":2,"description":"Materially incomplete"},{"score":3,"description":"Preserved with minor ambiguity"},{"score":4,"description":"Clearly preserved"}],"allow_not_applicable":false,"minimum_acceptable_score":3},{"id":"clarity","description":"Describe clear behavior.","evidence":"Compare source and specification.","weight":9,"anchors":[{"score":0,"description":"Absent"},{"score":1,"description":"Mostly absent"},{"score":2,"description":"Materially incomplete"},{"score":3,"description":"Preserved with minor ambiguity"},{"score":4,"description":"Clearly preserved"}],"allow_not_applicable":false,"minimum_acceptable_score":null}]}
;

/// Synthetic offline evidence for gate tests; never a real qualification record.
pub fn completed(a: std.mem.Allocator) !c.Report {
    var input: grading.Capture = .{
        .evaluation_id = "MOCK-evaluation-1",
        .case = .{
            .schema = "evaluation-case/v2",
            .id = "MOCK-evaluation",
            .sources = &.{.{ .id = "requirements", .path = "source.md" }},
            .rubric = "rubric.json",
            .grading_qualification = .{ .panel = "panel.json", .review = "review.json", .qualification = "qualification.json" },
        },
        .case_bytes = "MOCK-case-capture",
        .rubric = try grading.parseRubric(a, rubric_bytes),
        .rubric_bytes = rubric_bytes,
        .sources = &.{.{ .id = "requirements", .text = source }},
        .specification = source,
        .generation = .{ .origin = .live_generation, .workflow_status = .completed, .execution_id = "MOCK-run", .models = &models },
    };
    input.case_bytes = try std.json.Stringify.valueAlloc(a, input.case, .{});
    const observed = [_]judgment.CriterionResult{ criterion("coverage", 4), criterion("clarity", 4) };
    const result = try judgment.validate(a, null, input, try std.json.Stringify.valueAlloc(a, judgment.Proposal{ .results = &observed }, .{}));
    const proof: @import("../grading_evidence.zig").Proof = .{
        .panel_sha256 = "0" ** 64,
        .review_sha256 = "1" ** 64,
        .qualification_sha256 = "2" ** 64,
        .judge_config_sha256 = "3" ** 64,
        .protocol_sha256 = "4" ** 64,
    };
    const config: @import("../configuration.zig").Config = .{
        .schema = "evaluation-config/v1",
        .api = .openai_responses,
        .model = "MOCK-independent-judge",
        .region = null,
        .reasoning_effort = null,
        .temperature = null,
        .timeout_ms = 1000,
        .retry_limit = 0,
        .retry_delay_ms = 0,
        .total_token_budget = 1000,
    };
    return .{
        .schema = .@"spec-e2e-report/v6",
        .started_at_utc = "2026-10-17T00:00:00Z",
        .execution_id = "MOCK-run",
        .case_id = "MOCK-workflow-case",
        .evaluation_case_id = input.case.id,
        .expected_outcome = .publication,
        .status = .evaluated,
        .workflow_outcome = .ok,
        .publication_check = .passed,
        .specification = "specs/mock/spec.md",
        .models = &models,
        .admission_audit = .{ .sources = &.{.{ .source_id = .{ .ordinal = 1 }, .path = "references/mock/source.md", .bytes = source }}, .checks = &.{}, .complete = true },
        .admission_escape = .{ .status = .measured },
        .semantic_quality = .scored,
        .evaluation_inputs = input,
        .evaluation_configuration = config,
        .grader_qualification = .{ .qualified = proof },
        .evaluation = .{
            .capture = input,
            .configuration = config,
            .attempts = &.{.{ .ordinal = 1, .request_id = "MOCK-request", .identity = .{ .openai_response = .{ .response_id = "MOCK-response", .actual_model = config.model } }, .usage = .{ .input_tokens = 10, .output_tokens = 10, .total_tokens = 20 }, .failure = null }},
            .outcome = .{ .evaluated = result },
            .acceptance = .{ .independence = .independent, .qualification = .qualified, .quality = .passed, .decision = .passed },
        },
    };
}

fn criterion(id: []const u8, score: u16) judgment.CriterionResult {
    return .{
        .criterion_id = id,
        .disposition = .scored,
        .score = score,
        .explanation = "MOCK source and candidate support this assessment.",
        .evidence = &.{ .{ .document_id = "requirements", .first_line = 1, .last_line = 1 }, .{ .document_id = "specification", .first_line = 1, .last_line = 1 } },
        .missing_from_specification = false,
    };
}

pub fn pause(a: std.mem.Allocator) !c.Report {
    var report = try completed(a);
    report.expected_outcome = .clarification;
    report.status = .awaiting_clarification;
    report.workflow_outcome = .needs_user;
    report.semantic_quality = .not_run;
    report.evaluation = null;
    report.evaluation_inputs = null;
    report.clarifications = &.{.{ .id = .{ .stage = .spec, .ordinal = 2 }, .path = .{ .root = .specs, .root_relative = "mock/clarify/S02.md", .project_relative = "specs/mock/clarify/S02.md" } }};
    return report;
}

test "E2E model evaluation stays advisory and status or stored pass never accepts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var complete = try completed(a);
    try std.testing.expect(!try gate.commandSucceeded(a, complete));
    try std.testing.expectEqual(.human_adjudication_required, (try gate.evaluate(a, complete)).unresolved);
    try std.testing.expectEqual(.passed, try gate.evaluateHuman(a, complete, complete.evaluation.?.outcome.evaluated));
    try gate.apply(a, &complete);
    try std.testing.expectEqual(.human_adjudication_required, complete.acceptance.unresolved);
    for (std.meta.tags(c.Status)) |status| {
        const asserted: c.Report = .{ .schema = .@"spec-e2e-report/v6", .started_at_utc = "", .status = status, .expected_outcome = .publication, .acceptance = .passed };
        try std.testing.expect(!try gate.commandSucceeded(a, asserted));
    }
    complete.expected_outcome = null;
    try std.testing.expectEqual(.missing_expected_outcome, (try gate.evaluate(a, complete)).unresolved);
}

test "E2E publication and clarification have distinct explicit expected outcomes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var report = try pause(a);
    try std.testing.expect(try gate.commandSucceeded(a, report));
    report.expected_outcome = .publication;
    try std.testing.expectEqual(.unexpected_outcome, (try gate.evaluate(a, report)).failed);
    report = try completed(a);
    report.expected_outcome = .clarification;
    try std.testing.expectEqual(.unexpected_outcome, (try gate.evaluate(a, report)).failed);
    report = try pause(a);
    report.clarifications = &.{};
    try std.testing.expectEqual(.invalid_clarifications, (try gate.evaluate(a, report)).unresolved);
    report = try pause(a);
    report.clarifications = &.{ report.clarifications[0], report.clarifications[0] };
    try std.testing.expectEqual(.invalid_clarifications, (try gate.evaluate(a, report)).unresolved);
    report = try pause(a);
    report.clarifications = &.{.{ .id = .{ .stage = .spec, .ordinal = 2 }, .path = .{ .root = .specs, .root_relative = "other/clarify/S02.md", .project_relative = "specs/other/clarify/S02.md" } }};
    try std.testing.expectEqual(.invalid_clarifications, (try gate.evaluate(a, report)).unresolved);
}

test "E2E acceptance replays complete admission evidence and requires measured zero" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var report = try completed(a);
    report.admission_audit = null;
    try std.testing.expectEqual(.missing_admission_evidence, (try gate.evaluate(a, report)).unresolved);
    report = try completed(a);
    report.admission_escape = null;
    try std.testing.expectEqual(.missing_admission_evidence, (try gate.evaluate(a, report)).unresolved);
    report = try completed(a);
    report.admission_audit.?.complete = false;
    report.admission_escape.?.status = .unavailable;
    try std.testing.expectEqual(.missing_admission_evidence, (try gate.evaluate(a, report)).unresolved);
    report = try completed(a);
    report.admission_escape.?.admitted_values = 1;
    try std.testing.expectEqual(.admission_evidence_invalid, (try gate.evaluate(a, report)).failed);
    report = try completed(a);
    report.admission_audit.?.sources = &.{.{ .source_id = .{ .ordinal = 1 }, .path = "../source.md", .bytes = source }};
    try std.testing.expectEqual(.admission_evidence_invalid, (try gate.evaluate(a, report)).failed);
}

test "E2E acceptance rejects a native admission escape and forged violation bookkeeping" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const audit = @import("../baseline/admission.zig");
    var report = try completed(a);
    const value: audit.Value = .{ .business = .{ .segments = &.{.{ .exact_copy = .{ .claim_id = .{ .ordinal = 1 } } }} } };
    const origin: @import("../../../src/domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(try std.json.Stringify.valueAlloc(a, value, .{}), &digest, .{});
    const checks = try a.alloc(audit.Check, 1);
    checks[0] = .{
        .sequence = 1,
        .after_call = 1,
        .producer = .{ .model = origin },
        .subject = .{ .specification = .{ .unit = .primary_user_story, .field = .{ .target = .{ .value = .{ .subject = .story, .field = .value } } } } },
        .field = .spec_story,
        .value = value,
        .value_sha256 = try a.dupe(u8, &std.fmt.bytesToHex(digest, .lower)),
        .violation = try audit.check(a, report.admission_audit.?.sources, .spec_story, value),
    };
    try std.testing.expect(checks[0].violation != null);
    report.admission_audit.?.checks = checks;
    report.admission_exchanges = &.{.{ .call = 1, .origin = origin, .usage = null }};
    report.admission_escape = try audit.measure(report.admission_audit, report.admission_exchanges);
    try std.testing.expectEqual(.admission_escape, (try gate.evaluate(a, report)).failed);
    checks[0].violation = null;
    try std.testing.expectEqual(.admission_evidence_invalid, (try gate.evaluate(a, report)).failed);
}

test "human quality cannot override native failure missing publication or artifacts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]@import("../../../src/domain/workflow.zig").OutcomeTag{ .failed, .invalid, .blocked, .cancelled, .more }) |outcome| {
        var report = try completed(a);
        report.workflow_outcome = outcome;
        try std.testing.expectEqual(.native_workflow_failed, (try gate.evaluateHuman(a, report, report.evaluation.?.outcome.evaluated)).failed);
    }
    var report = try completed(a);
    report.publication_check = .not_run;
    try std.testing.expectEqual(.publication_failed, (try gate.evaluateHuman(a, report, report.evaluation.?.outcome.evaluated)).failed);
    report = try completed(a);
    report.missing_artifact = .workflow_state;
    try std.testing.expectEqual(.artifact_failed, (try gate.evaluateHuman(a, report, report.evaluation.?.outcome.evaluated)).failed);
}

test "E2E advisory failure uncertainty or provider error cannot replace human quality judgment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var report = try completed(a);
    const human = report.evaluation.?.outcome.evaluated;
    report.evaluation.?.outcome.evaluated.threshold = .not_met;
    report.evaluation.?.acceptance.quality = .{ .failed = .threshold_failed };
    try std.testing.expectEqual(.human_adjudication_required, (try gate.evaluate(a, report)).unresolved);
    try std.testing.expectEqual(.passed, try gate.evaluateHuman(a, report, human));
    report.status = .quality_unresolved;
    report.semantic_quality = .unresolved;
    report.evaluation.?.outcome.evaluated.assessment = .unresolved;
    report.evaluation.?.outcome.evaluated.threshold = .undetermined;
    report.evaluation.?.outcome.evaluated.score_percent = null;
    try std.testing.expectEqual(.human_adjudication_required, (try gate.evaluate(a, report)).unresolved);
    try std.testing.expectEqual(.passed, try gate.evaluateHuman(a, report, human));
    report.status = .evaluator_failed;
    report.semantic_quality = .evaluator_error;
    report.evaluation = null;
    try std.testing.expectEqual(.human_adjudication_required, (try gate.evaluate(a, report)).unresolved);
    try std.testing.expectEqual(.passed, try gate.evaluateHuman(a, report, human));
}

test "E2E human adjudication recomputes critical threshold and uncertainty from source-bound scores" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const report = try completed(a);
    var results = try a.dupe(judgment.CriterionResult, report.evaluation.?.outcome.evaluated.results);
    results[0].score = 2;
    var human = report.evaluation.?.outcome.evaluated;
    human.results = results;
    // The claimed aggregate remains 100%; canonical accounting finds a critical failure.
    try std.testing.expectEqual(.critical_failed, (try gate.evaluateHuman(a, report, human)).failed);
    results[0].score = 4;
    results[1].score = 3;
    try std.testing.expectEqual(.threshold_failed, (try gate.evaluateHuman(a, report, human)).failed);
    results[0].disposition = .uncertain;
    results[0].score = null;
    try std.testing.expectEqual(.grading_unresolved, (try gate.evaluateHuman(a, report, human)).unresolved);
    results[0] = criterion("coverage", 4);
    results[1] = criterion("clarity", 4);
    results[0].evidence = &.{.{ .document_id = "requirements", .first_line = 9, .last_line = 9 }};
    try std.testing.expectEqual(.grading_mismatch, (try gate.evaluateHuman(a, report, human)).failed);
}

test "E2E acceptance binds human grading inputs to current case generation and native sources" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var report = try completed(a);
    report.evaluation_inputs.?.generation.execution_id = "MOCK-other-run";
    try std.testing.expectEqual(.grading_mismatch, (try gate.evaluate(a, report)).failed);
    report = try completed(a);
    report.evaluation_inputs.?.generation.origin = .supplied;
    try std.testing.expectEqual(.grading_mismatch, (try gate.evaluate(a, report)).failed);
    report = try completed(a);
    report.evaluation_case_id = "MOCK-other-case";
    try std.testing.expectEqual(.grading_mismatch, (try gate.evaluate(a, report)).failed);
    report = try completed(a);
    report.evaluation_inputs.?.sources = &.{.{ .id = "requirements", .text = "Different source bytes." }};
    try std.testing.expectEqual(.grading_mismatch, (try gate.evaluate(a, report)).failed);
    report = try completed(a);
    report.evaluation_inputs.?.generation.models = &.{.{ .slot = "MOCK-generation", .provider = "aws-bedrock", .model = "MOCK-other-generator" }};
    try std.testing.expectEqual(.grading_mismatch, (try gate.evaluate(a, report)).failed);
}

test "E2E rendering separates evaluated status from unresolved human acceptance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const report = try completed(a);
    const rendered = try @import("report.zig").terminal(a, report, "MOCK-runs", "MOCK-run");
    try std.testing.expect(std.mem.indexOf(u8, rendered, "E2E result: evaluated") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "development acceptance: unresolved (human_adjudication_required)") != null);
}
