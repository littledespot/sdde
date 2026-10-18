const std = @import("std");
const gate = @import("acceptance_gate.zig");
const acceptance = @import("acceptance.zig");
const independence = @import("judge_independence.zig");
const c = @import("contracts.zig");
const judgment = @import("judgment.zig");
const reports = @import("report.zig");

const generation: c.GenerationModel = .{ .slot = "spec_generation", .provider = "aws-bedrock", .model = "openai.gpt-oss-20b-1:0" };
const digest = "0" ** 64;

fn rubric() c.Rubric {
    return .{
        .schema = "evaluation-rubric/v2",
        .id = "test-human-acceptance",
        .revision = 1,
        .minimum_score = 0,
        .maximum_score = 4,
        .pass_threshold_percent = 80,
        .criteria = &.{.{
            .id = "faithfulness",
            .description = "Preserve the stated behavior.",
            .evidence = "Compare the required and specified behavior.",
            .weight = 1,
            .anchors = &.{
                .{ .score = 0, .description = "Absent" },
                .{ .score = 1, .description = "Mostly absent" },
                .{ .score = 2, .description = "Material omission" },
                .{ .score = 3, .description = "Preserved" },
                .{ .score = 4, .description = "Clearly preserved" },
            },
            .allow_not_applicable = false,
            .minimum_acceptable_score = 3,
        }},
    };
}

fn result() judgment.Result {
    return .{
        .results = &.{.{
            .criterion_id = "faithfulness",
            .disposition = .scored,
            .score = 4,
            .explanation = "The required behavior is preserved.",
            .evidence = &.{
                .{ .document_id = "source", .first_line = 1, .last_line = 1 },
                .{ .document_id = "specification", .first_line = 1, .last_line = 1 },
            },
            .missing_from_specification = false,
        }},
        .assessment = .scored,
        .score_percent = 100,
        .threshold = .met,
    };
}

fn report() reports.Report {
    return .{
        .capture = .{
            .evaluation_id = "human-acceptance-example",
            .case = .{
                .schema = "evaluation-case/v2",
                .id = "message-case",
                .sources = &.{.{ .id = "source", .path = "source.md" }},
                .rubric = "rubric.json",
                .grading_qualification = .{ .panel = "panel.json", .review = "review.json", .qualification = "qualification.json" },
            },
            .case_bytes = "captured-case",
            .rubric = rubric(),
            .rubric_bytes = "captured-rubric",
            .sources = &.{.{ .id = "source", .text = "Show a message." }},
            .specification = "The user sees a message.",
            .generation = .{ .origin = .live_generation, .workflow_status = .completed, .execution_id = "execution-example", .models = &.{generation} },
        },
        .configuration = .{
            .schema = "evaluation-config/v1",
            .api = .bedrock_converse,
            .model = generation.model,
            .region = .@"ap-southeast-2",
            .reasoning_effort = .low,
            .temperature = 0.1,
            .timeout_ms = 120000,
            .retry_limit = 0,
            .retry_delay_ms = 0,
            .total_token_budget = 150000,
        },
        // An evaluated outcome is its successful final attempt's.
        .attempts = &.{.{ .ordinal = 1, .purpose = .judgment, .request_id = null, .identity = .unavailable, .usage = .{ .input_tokens = 1, .output_tokens = 1, .total_tokens = 2 }, .failure = null }},
        .outcome = .{ .evaluated = result() },
        .acceptance = gate.from(rubric(), result(), .{ .self_grading = generation }, .unresolved),
        .grader_qualification = .{ .unresolved = .review_pending },
        .protocol_sha256 = digest,
    };
}

test "every model score and provenance combination requires human adjudication" {
    for ([_]acceptance.Quality{
        .passed,
        .{ .failed = .critical_failed },
        .{ .failed = .threshold_failed },
        .{ .unresolved = .missing_threshold },
        .{ .unresolved = .uncertainty },
        .{ .unresolved = .no_applicable },
    }) |quality| {
        for ([_]independence.Result{ .independent, .{ .self_grading = generation }, .unknown_generation }) |identity| {
            for ([_]gate.Qualification{ .qualified, .unresolved }) |qualification| {
                try std.testing.expectEqualDeep(gate.Decision{ .unresolved = .human_adjudication_required }, gate.decide(quality, identity, qualification));
            }
        }
    }
}

test "acceptance evidence retains advisory quality without model acceptance authority" {
    const evidence = gate.from(rubric(), result(), .{ .self_grading = generation }, .unresolved);
    try std.testing.expectEqualDeep(acceptance.Quality{ .passed = {} }, evidence.quality.?);
    try std.testing.expectEqual(.self_grading, evidence.independence);
    try std.testing.expectEqual(.unresolved, evidence.qualification);
    try std.testing.expectEqualDeep(gate.Decision{ .unresolved = .human_adjudication_required }, evidence.decision);
    const pending: gate.Evidence = .{};
    try std.testing.expect(pending.quality == null);
    try std.testing.expectEqualDeep(gate.Decision{ .unresolved = .not_evaluated }, pending.decision);
}

test "evaluation reports render human gate critical minima and qualification reasons" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const rendered = try reports.markdown(arena.allocator(), report());
    for ([_][]const u8{
        "Development acceptance: unresolved (human_adjudication_required)",
        "Judge independence: self_grading; qualification: unresolved",
        "Grader qualification evidence: unresolved (review_pending)",
        "critical minimum: 3",
        "Score: 100.00%",
    }) |expected| try std.testing.expect(std.mem.indexOf(u8, rendered, expected) != null);
}

test "persisted evaluation reports require explicit acceptance and protocol identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try reports.json(a, report());
    const parsed = try reports.parse(a, bytes);
    try std.testing.expectEqualStrings("evaluation-report/v5", parsed.schema);
    try std.testing.expectEqualDeep(report().acceptance, parsed.acceptance);
    for ([_][]const u8{ "schema", "prompt_revision", "judgment_schema", "protocol_sha256", "acceptance", "grader_qualification" }) |key| {
        var tree = try @import("../../src/domain/strict_json.zig").parse(a, bytes, c.json_limits, false, null);
        defer tree.deinit();
        try std.testing.expect(tree.value.object.swapRemove(key));
        try std.testing.expectError(error.InvalidEvaluationContract, reports.parse(a, try std.json.Stringify.valueAlloc(a, tree.value, .{})));
    }
    for ([_][2][]const u8{
        .{ "evaluation-report/v5", "evaluation-report/v4" },
        .{ @import("packet.zig").revision, "old-prompt" },
        .{ judgment.schema_revision, "old-judgment" },
        .{ digest, "bad-digest" },
    }) |replacement| {
        try std.testing.expectError(error.InvalidEvaluationContract, reports.parse(a, try std.mem.replaceOwned(u8, a, bytes, replacement[0], replacement[1])));
    }
}
