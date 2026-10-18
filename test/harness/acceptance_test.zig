const std = @import("std");
const c = @import("contracts.zig");
const judgment = @import("judgment.zig");
const acceptance = @import("acceptance.zig");

const rubric_bytes =
    \\{"schema":"evaluation-rubric/v2","id":"acceptance-example","revision":1,"minimum_score":0,"maximum_score":4,"pass_threshold_percent":80,"criteria":[{"id":"safety","description":"Preserve the stated limit.","evidence":"Compare the stated and specified limit.","weight":1,"anchors":[{"score":0,"description":"Absent"},{"score":1,"description":"Mostly absent"},{"score":2,"description":"Materially incomplete"},{"score":3,"description":"Preserved with minor ambiguity"},{"score":4,"description":"Clearly preserved"}],"allow_not_applicable":false,"minimum_acceptable_score":3},{"id":"readability","description":"Present understandable requirements.","evidence":"Compare readable source and specification statements.","weight":9,"anchors":[{"score":0,"description":"Absent"},{"score":1,"description":"Mostly absent"},{"score":2,"description":"Materially incomplete"},{"score":3,"description":"Preserved with minor ambiguity"},{"score":4,"description":"Clearly preserved"}],"allow_not_applicable":true,"minimum_acceptable_score":null}]}
;

fn capture(a: std.mem.Allocator) !c.Capture {
    const rubric = try c.parseRubric(a, rubric_bytes);
    return .{
        .evaluation_id = "acceptance-example-1",
        .case = .{ .schema = "evaluation-case/v2", .id = "bounded-storage", .sources = &.{.{ .id = "requirements", .path = "references/storage.md" }}, .rubric = "rubric.json", .grading_qualification = .{ .panel = "panel.json", .review = "review.json", .qualification = "qualification.json" } },
        .case_bytes = "captured-case",
        .rubric = rubric,
        .rubric_bytes = rubric_bytes,
        .sources = &.{.{ .id = "requirements", .text = "Keep at most ten messages." }},
        .specification = "The application keeps at most ten messages.",
        .generation = .{ .origin = .supplied, .workflow_status = .not_run, .execution_id = null, .models = &.{} },
    };
}

fn criterion(id: []const u8, score: ?u16) judgment.CriterionResult {
    return .{
        .criterion_id = id,
        .disposition = if (score == null) .uncertain else .scored,
        .score = score,
        .explanation = "The evidence supports this criterion assessment.",
        .evidence = &.{ .{ .document_id = "requirements", .first_line = 1, .last_line = 1 }, .{ .document_id = "specification", .first_line = 1, .last_line = 1 } },
        .missing_from_specification = false,
    };
}

fn assess(a: std.mem.Allocator, input: c.Capture, results: []const judgment.CriterionResult) !judgment.Result {
    return judgment.validate(a, null, input, try std.json.Stringify.valueAlloc(a, judgment.Proposal{ .results = results }, .{}));
}

test "critical failure vetoes a passing aggregate and unresolved sibling" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var input = try capture(a);
    const high = try assess(a, input, &.{ criterion("safety", 2), criterion("readability", 4) });
    try std.testing.expectEqual(@as(f64, 95), high.score_percent.?);
    try std.testing.expectEqual(.met, high.threshold);
    try std.testing.expectEqualDeep(acceptance.Quality{ .failed = .critical_failed }, acceptance.quality(input.rubric, high));

    const uncertain = try assess(a, input, &.{ criterion("safety", 2), criterion("readability", null) });
    try std.testing.expectEqual(.unresolved, uncertain.assessment);
    try std.testing.expectEqualDeep(acceptance.Quality{ .failed = .critical_failed }, acceptance.quality(input.rubric, uncertain));

    input.rubric.pass_threshold_percent = null;
    const missing_threshold = try assess(a, input, &.{ criterion("safety", 2), criterion("readability", 4) });
    try std.testing.expectEqualDeep(acceptance.Quality{ .failed = .critical_failed }, acceptance.quality(input.rubric, missing_threshold));
}

test "aggregate threshold still rejects when every critical minimum is met" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const input = try capture(a);
    const low = try assess(a, input, &.{ criterion("safety", 3), criterion("readability", 0) });
    try std.testing.expectEqual(.not_met, low.threshold);
    try std.testing.expectEqualDeep(acceptance.Quality{ .failed = .threshold_failed }, acceptance.quality(input.rubric, low));
}

test "critical and aggregate boundaries are inclusive and quality is separate from accounting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var input = try capture(a);
    input.rubric.pass_threshold_percent = 75;
    const boundary = try assess(a, input, &.{ criterion("safety", 3), criterion("readability", 3) });
    try std.testing.expectEqual(@as(f64, 75), boundary.score_percent.?);
    try std.testing.expectEqualDeep(acceptance.Quality{ .passed = {} }, acceptance.quality(input.rubric, boundary));

    input.rubric.pass_threshold_percent = null;
    const unconfigured = try assess(a, input, &.{ criterion("safety", 4), criterion("readability", 4) });
    try std.testing.expectEqual(@as(f64, 100), unconfigured.score_percent.?);
    try std.testing.expectEqual(.scored, unconfigured.assessment);
    try std.testing.expectEqualDeep(acceptance.Quality{ .unresolved = .missing_threshold }, acceptance.quality(input.rubric, unconfigured));
}

test "uncertainty in critical or noncritical criteria prevents acceptance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const input = try capture(a);
    for ([_][2]?u16{ .{ null, 4 }, .{ 4, null } }) |scores| {
        const result = try assess(a, input, &.{ criterion("safety", scores[0]), criterion("readability", scores[1]) });
        try std.testing.expectEqualDeep(acceptance.Quality{ .unresolved = .uncertainty }, acceptance.quality(input.rubric, result));
    }
}

test "permitted noncritical exclusion cannot waive critical coverage or invent an aggregate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var input = try capture(a);
    var results = [_]judgment.CriterionResult{ criterion("safety", 4), criterion("readability", null) };
    results[1].disposition = .not_applicable;
    const remaining = try assess(a, input, &results);
    try std.testing.expectEqual(@as(f64, 100), remaining.score_percent.?);
    try std.testing.expectEqualDeep(acceptance.Quality{ .passed = {} }, acceptance.quality(input.rubric, remaining));

    results[0].disposition = .not_applicable;
    results[0].score = null;
    try std.testing.expectError(error.InvalidEvaluationContract, assess(a, input, &results));

    const criteria = try a.dupe(c.Criterion, input.rubric.criteria);
    criteria[0].minimum_acceptable_score = null;
    criteria[0].allow_not_applicable = true;
    input.rubric = try c.parseRubric(a, try std.json.Stringify.valueAlloc(a, c.Rubric{
        .schema = input.rubric.schema,
        .id = input.rubric.id,
        .revision = input.rubric.revision,
        .minimum_score = input.rubric.minimum_score,
        .maximum_score = input.rubric.maximum_score,
        .pass_threshold_percent = input.rubric.pass_threshold_percent,
        .criteria = criteria,
    }, .{}));
    const none = try assess(a, input, &results);
    try std.testing.expectEqual(.no_applicable_criteria, none.assessment);
    try std.testing.expectEqualDeep(acceptance.Quality{ .unresolved = .no_applicable }, acceptance.quality(input.rubric, none));
}

test "rubric v2 requires explicit valid criticality and rejects superseded or waived contracts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    _ = try c.parseRubric(a, rubric_bytes);
    for ([_][2][]const u8{
        .{ "evaluation-rubric/v2", "evaluation-rubric/v1" },
        .{ ",\"minimum_acceptable_score\":3", "" },
        .{ ",\"minimum_acceptable_score\":null", "" },
        .{ "\"minimum_acceptable_score\":3", "\"minimum_acceptable_score\":5" },
        .{ "\"minimum_acceptable_score\":3", "\"minimum_acceptable_score\":-1" },
        .{ "\"minimum_acceptable_score\":3", "\"minimum_acceptable_score\":\"3\"" },
        .{ "\"allow_not_applicable\":false", "\"allow_not_applicable\":true" },
        .{ "\"minimum_acceptable_score\":3", "\"minimum_acceptable_score\":3,\"minimum_acceptable_score\":4" },
        .{ "\"minimum_acceptable_score\":3", "\"minimum_acceptable_score\":3,\"critical\":true" },
    }) |replacement| {
        const invalid = try std.mem.replaceOwned(u8, a, rubric_bytes, replacement[0], replacement[1]);
        try std.testing.expectError(error.InvalidEvaluationContract, c.parseRubric(a, invalid));
    }
    var shifted = try c.parseRubric(a, rubric_bytes);
    shifted.minimum_score = 1;
    const criteria = try a.dupe(c.Criterion, shifted.criteria);
    for (criteria) |*item| item.anchors = item.anchors[1..];
    shifted.criteria = criteria;
    _ = try c.parseRubric(a, try std.json.Stringify.valueAlloc(a, shifted, .{}));
    criteria[0].minimum_acceptable_score = 0;
    try std.testing.expectError(error.InvalidEvaluationContract, c.parseRubric(a, try std.json.Stringify.valueAlloc(a, shifted, .{})));
}
