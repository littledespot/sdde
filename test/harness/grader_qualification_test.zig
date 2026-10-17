const std = @import("std");
const c = @import("contracts.zig");
const q = @import("grader_qualification.zig");
const configuration = @import("configuration.zig");
const judgment = @import("judgment.zig");
const reports = @import("report.zig");

const paths: q.Paths = .{ .panel = "panel.json", .review = "review.json", .qualification = "qualification.json" };
const source = c.Document{ .id = "requirements", .text = "Show READY after startup." };
const specimen_ids = [_][]const u8{ "faithful-a", "faithful-b", "wrong-value" };
const specimen_paths = [_][]const u8{ "faithful-a.md", "faithful-b.md", "wrong-value.md" };
const report_paths = [_][]const u8{ "judge-a.json", "judge-b.json", "judge-wrong.json" };
const specimen_texts = [_][]const u8{ "After startup, the application shows READY.", "The startup outcome includes the displayed value READY.", "After startup, the application shows FINISHED." };
const config: configuration.Config = .{
    .schema = "evaluation-config/v1",
    .api = .bedrock_converse,
    .model = "openai.gpt-oss-20b-1:0",
    .region = .@"ap-southeast-2",
    .reasoning_effort = .low,
    .temperature = 0.1,
    .timeout_ms = 1000,
    .retry_limit = 0,
    .retry_delay_ms = 0,
    .total_token_budget = 1000,
};
const rubric_bytes =
    \\{"schema":"evaluation-rubric/v2","id":"startup-value","revision":1,"minimum_score":0,"maximum_score":4,"pass_threshold_percent":80,"criteria":[{"id":"value-fidelity","description":"Preserve the displayed startup value.","evidence":"Compare the original and specified behavior.","weight":1,"anchors":[{"score":0,"description":"Absent or contradicted"},{"score":1,"description":"Mostly lost"},{"score":2,"description":"Material omission"},{"score":3,"description":"Minor ambiguity"},{"score":4,"description":"Preserved"}],"allow_not_applicable":false,"minimum_acceptable_score":3}]}
;

/// These are isolated test-only declarations, not human approval of the actual
/// repository panels or evidence that a real provider request occurred.
const Fixture = struct {
    a: std.mem.Allocator,
    root: std.Io.Dir,
    selected: c.Case,
    panel: q.Panel,
    review: q.HumanReview,
    qualification: q.Qualification,
    results: []reports.Report,

    fn init(a: std.mem.Allocator, root: std.Io.Dir) !Fixture {
        const selected: c.Case = .{
            .schema = "evaluation-case/v2",
            .id = "startup-display",
            .sources = &.{.{ .id = source.id, .path = "references/startup.md" }},
            .rubric = "rubric.json",
            .grading_qualification = paths,
        };
        const specimens = try a.alloc(q.Specimen, specimen_ids.len);
        const report_records = try a.alloc(q.SpecimenReport, specimen_ids.len);
        const results = try a.alloc(reports.Report, specimen_ids.len);
        const rubric = try c.parseRubric(a, rubric_bytes);
        const case_bytes = try std.json.Stringify.valueAlloc(a, selected, .{});
        for (specimens, report_records, results, 0..) |*specimen, *report, *result, index| {
            specimen.* = .{ .id = specimen_ids[index], .path = specimen_paths[index], .sha256 = try q.sha256(a, specimen_texts[index]), .expected = if (index < 2) .passed else .failed };
            try root.writeFile(std.testing.io, .{ .sub_path = specimen.path, .data = specimen_texts[index] });
            const input: c.Capture = .{
                .evaluation_id = try std.fmt.allocPrint(a, "unit-evaluation-{d}", .{index}),
                .case = selected,
                .case_bytes = case_bytes,
                .rubric = rubric,
                .rubric_bytes = rubric_bytes,
                .sources = &.{source},
                .specification = specimen_texts[index],
                .generation = .{ .origin = .supplied, .workflow_status = .not_run, .execution_id = null, .models = &.{} },
            };
            const proposal: judgment.Proposal = .{ .results = &.{.{
                .criterion_id = "value-fidelity",
                .disposition = .scored,
                .score = if (index < 2) 4 else 0,
                .explanation = "Compare the original startup display with the specification.",
                .evidence = &.{ .{ .document_id = source.id, .quote = source.text }, .{ .document_id = "specification", .quote = specimen_texts[index] } },
                .missing_from_specification = false,
            }} };
            result.* = .{
                .schema = "evaluation-report/v3",
                .protocol_sha256 = try q.protocolSha256(a),
                .capture = input,
                .configuration = config,
                .attempts = try a.dupe(reports.Attempt, &.{.{ .ordinal = 1, .request_id = "unit-request", .identity = .{ .bedrock_target = .{ .model = config.model, .region = config.region.? } }, .usage = reports.Usage.init(1, 1, 2).?, .failure = null }}),
                .outcome = .{ .evaluated = try judgment.validate(a, null, input, try std.json.Stringify.valueAlloc(a, proposal, .{})) },
            };
            const bytes = try reports.json(a, result.*);
            try root.writeFile(std.testing.io, .{ .sub_path = report_paths[index], .data = bytes });
            report.* = .{ .id = specimen.id, .path = report_paths[index], .sha256 = try q.sha256(a, bytes) };
        }
        const panel: q.Panel = .{
            .schema = .@"grader-calibration-panel/v1",
            .case_id = selected.id,
            .sources = try a.dupe(q.Source, &.{.{ .id = source.id, .sha256 = try q.sha256(a, source.text) }}),
            .rubric_sha256 = try q.sha256(a, rubric_bytes),
            .specimens = specimens,
        };
        const panel_bytes = try std.json.Stringify.valueAlloc(a, panel, .{});
        const review: q.HumanReview = .{
            .schema = .@"grader-calibration-review/v1",
            .outcome = .{ .reviewed = .{ .reviewer = "unit-fixture-human", .reviewed_at_utc = "2026-10-17T00:00:00Z", .panel_sha256 = try q.sha256(a, panel_bytes) } },
        };
        const qualification: q.Qualification = .{
            .schema = .@"grader-qualification/v1",
            .outcome = .{ .qualified = .{
                .reviewer = "unit-fixture-human",
                .reviewed_at_utc = "2026-10-17T00:01:00Z",
                .panel_sha256 = try q.sha256(a, panel_bytes),
                .review_sha256 = try q.sha256(a, try std.json.Stringify.valueAlloc(a, review, .{})),
                .judge_config_sha256 = try q.configSha256(a, config),
                .protocol_sha256 = try q.protocolSha256(a),
                .reports = report_records,
            } },
        };
        var self: Fixture = .{ .a = a, .root = root, .selected = selected, .panel = panel, .review = review, .qualification = qualification, .results = results };
        try self.saveDeclarations();
        return self;
    }

    fn inspect(self: Fixture) !q.Evidence {
        return q.inspect(std.testing.io, self.a, self.root, paths, self.selected, rubric_bytes, &.{source}, config);
    }

    fn saveDeclarations(self: Fixture) !void {
        try self.root.writeFile(std.testing.io, .{ .sub_path = paths.panel, .data = try std.json.Stringify.valueAlloc(self.a, self.panel, .{}) });
        try self.root.writeFile(std.testing.io, .{ .sub_path = paths.review, .data = try std.json.Stringify.valueAlloc(self.a, self.review, .{}) });
        try self.root.writeFile(std.testing.io, .{ .sub_path = paths.qualification, .data = try std.json.Stringify.valueAlloc(self.a, self.qualification, .{}) });
    }

    fn saveReport(self: *Fixture, index: usize, value: reports.Report) !void {
        self.results[index] = value;
        const bytes = try reports.json(self.a, value);
        try self.root.writeFile(std.testing.io, .{ .sub_path = report_paths[index], .data = bytes });
        const records = try self.a.dupe(q.SpecimenReport, self.qualification.outcome.qualified.reports);
        records[index].sha256 = try q.sha256(self.a, bytes);
        self.qualification.outcome.qualified.reports = records;
        try self.saveDeclarations();
    }
};

fn unresolved(expected: q.Reason, actual: q.Evidence) !void {
    try std.testing.expectEqualDeep(q.Evidence{ .unresolved = expected }, actual);
}

test "grader qualification requires reviewed reports for every exact labeled specimen" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, tmp.dir);
    const evidence = try fixture.inspect();
    try std.testing.expect(evidence == .qualified);
    try std.testing.expectEqualStrings(try q.configSha256(a, config), evidence.qualified.judge_config_sha256);
    try std.testing.expectEqualStrings(try q.protocolSha256(a), evidence.qualified.protocol_sha256);

    // Semantically equal evidence with different bytes still has a new identity.
    const original = evidence.qualified.qualification_sha256;
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = paths.qualification, .data = try std.json.Stringify.valueAlloc(a, fixture.qualification, .{ .whitespace = .indent_2 }) });
    const reformatted = try fixture.inspect();
    try std.testing.expect(reformatted == .qualified);
    try std.testing.expect(!std.mem.eql(u8, original, reformatted.qualified.qualification_sha256));

    fixture.qualification.outcome = .pending;
    try fixture.saveDeclarations();
    try unresolved(.qualification_pending, try fixture.inspect());
    fixture.review.outcome = .pending;
    try fixture.saveDeclarations();
    try unresolved(.review_pending, try fixture.inspect());
}

test "missing and changed panel source rubric specimen and human evidence remain unresolved" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]struct { path: []const u8, reason: q.Reason }{
        .{ .path = paths.panel, .reason = .panel_missing },
        .{ .path = paths.review, .reason = .review_missing },
        .{ .path = paths.qualification, .reason = .qualification_missing },
        .{ .path = specimen_paths[0], .reason = .specimen_missing },
        .{ .path = report_paths[0], .reason = .report_missing },
    }) |scenario| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        const fixture = try Fixture.init(a, tmp.dir);
        try tmp.dir.deleteFile(std.testing.io, scenario.path);
        try unresolved(scenario.reason, try fixture.inspect());
    }
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(a, tmp.dir);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = specimen_paths[0], .data = "A changed specimen." });
    try unresolved(.specimen_stale, try fixture.inspect());
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = specimen_paths[0], .data = specimen_texts[0] });
    try unresolved(.panel_stale, try q.inspect(std.testing.io, a, tmp.dir, paths, fixture.selected, rubric_bytes, &.{.{ .id = source.id, .text = "Show READY after startup in UTC." }}, config));
    const changed_rubric = try std.mem.replaceOwned(u8, a, rubric_bytes, "\"revision\":1", "\"revision\":2");
    try unresolved(.panel_stale, try q.inspect(std.testing.io, a, tmp.dir, paths, fixture.selected, changed_rubric, &.{source}, config));
    fixture.panel.case_id = "another-case";
    try fixture.saveDeclarations();
    try unresolved(.panel_stale, try fixture.inspect());
    fixture.panel.case_id = fixture.selected.id;
    fixture.review.outcome.reviewed.panel_sha256 = try q.sha256(a, "old panel");
    try fixture.saveDeclarations();
    try unresolved(.review_stale, try fixture.inspect());
}

test "qualification binds review labels selected judge settings and judging protocol" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, tmp.dir);
    const fields = [_][]const u8{ "panel_sha256", "review_sha256", "judge_config_sha256", "protocol_sha256" };
    inline for (fields) |field| {
        const original = @field(fixture.qualification.outcome.qualified, field);
        @field(fixture.qualification.outcome.qualified, field) = try q.sha256(a, "obsolete evidence");
        try fixture.saveDeclarations();
        try unresolved(.qualification_stale, try fixture.inspect());
        @field(fixture.qualification.outcome.qualified, field) = original;
    }
    try fixture.saveDeclarations();
    var changed = config;
    changed.reasoning_effort = .high;
    try unresolved(.qualification_stale, try q.inspect(std.testing.io, a, tmp.dir, paths, fixture.selected, rubric_bytes, &.{source}, changed));
    const specimens = try a.dupe(q.Specimen, fixture.panel.specimens);
    specimens[0].expected = .failed;
    specimens[2].expected = .passed;
    fixture.panel.specimens = specimens;
    // Altering approved labels invalidates review before any report is consulted.
    try fixture.saveDeclarations();
    try unresolved(.review_stale, try fixture.inspect());
}

test "reports cannot qualify foreign captures forged arithmetic missing usage or uncertain judgments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for (std.enums.values(enum { case, rubric, source_bytes, specimen, config, protocol, protocol_bytes, missing_protocol, arithmetic, unknown_identity, no_attempts, no_usage, failed_attempt, uncertainty, incorrect_verdict })) |fault| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var fixture = try Fixture.init(a, tmp.dir);
        var value = fixture.results[0];
        var expected: q.Reason = .report_mismatch;
        switch (fault) {
            .case => value.capture.case.id = "foreign-case",
            .rubric => value.capture.rubric.revision += 1,
            .source_bytes => value.capture.sources = &.{.{ .id = source.id, .text = "A foreign source." }},
            .specimen => value.capture.specification = "Another readable specification.",
            .config => value.configuration.reasoning_effort = .high,
            .protocol => value.prompt_revision = "obsolete-grader-prompt",
            .protocol_bytes => value.protocol_sha256 = try q.sha256(a, "different prompt or result schema with unchanged revision labels"),
            .missing_protocol => value.protocol_sha256 = null,
            .arithmetic => value.outcome.evaluated.score_percent = 1,
            .unknown_identity, .no_usage, .failed_attempt => {
                const attempts = try a.dupe(reports.Attempt, value.attempts);
                switch (fault) {
                    .unknown_identity => attempts[0].identity = .unavailable,
                    .no_usage => attempts[0].usage = null,
                    .failed_attempt => attempts[0].failure = .refused,
                    else => unreachable,
                }
                value.attempts = attempts;
            },
            .no_attempts => value.attempts = &.{},
            .uncertainty, .incorrect_verdict => {
                const results = try a.dupe(judgment.CriterionResult, value.outcome.evaluated.results);
                results[0].score = if (fault == .uncertainty) null else 0;
                results[0].disposition = if (fault == .uncertainty) .uncertain else .scored;
                value.outcome = .{ .evaluated = try judgment.validate(a, null, value.capture, try std.json.Stringify.valueAlloc(a, judgment.Proposal{ .results = results }, .{})) };
                expected = if (fault == .uncertainty) .report_unresolved else .verdict_mismatch;
            },
        }
        try fixture.saveReport(0, value);
        if (fault == .protocol) {
            try std.testing.expectError(error.InvalidGraderQualification, fixture.inspect());
        } else {
            try unresolved(expected, try fixture.inspect());
        }
    }
}

test "malformed declarations and incomplete duplicate or foreign report accounting reject" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, tmp.dir);
    const panel_bytes = try std.json.Stringify.valueAlloc(a, fixture.panel, .{});
    for ([_][2][]const u8{
        .{ "grader-calibration-panel/v1", "grader-calibration-panel/v0" },
        .{ "\"case_id\":", "\"unexpected\":true,\"case_id\":" },
        .{ "faithful-a.md", "../faithful-a.md" },
        .{ "\"expected\":\"failed\"", "\"expected\":\"passed\"" },
        .{ "\"id\":\"faithful-b\"", "\"id\":\"faithful-a\"" },
    }) |replacement| try std.testing.expectError(error.InvalidGraderQualification, q.parsePanel(a, try std.mem.replaceOwned(u8, a, panel_bytes, replacement[0], replacement[1])));
    for ([_][]const u8{ "2026-02-30T00:00:00Z", "2026-10-17T00:00:60Z", "2026-10-17 00:00:00Z", "2026-10-17T00:00:00+10:00" }) |invalid_date| {
        var review = fixture.review;
        review.outcome.reviewed.reviewed_at_utc = invalid_date;
        try std.testing.expectError(error.InvalidGraderQualification, q.parseReview(a, try std.json.Stringify.valueAlloc(a, review, .{})));
    }
    const records = fixture.qualification.outcome.qualified.reports;
    fixture.qualification.outcome.qualified.reports = records[0..2];
    try fixture.saveDeclarations();
    try std.testing.expectError(error.InvalidGraderQualification, fixture.inspect());
    const duplicate = try a.dupe(q.SpecimenReport, records);
    duplicate[1].id = duplicate[0].id;
    fixture.qualification.outcome.qualified.reports = duplicate;
    try fixture.saveDeclarations();
    try std.testing.expectError(error.InvalidGraderQualification, fixture.inspect());
    duplicate[1] = records[1];
    duplicate[1].id = "foreign-specimen";
    try fixture.saveDeclarations();
    try std.testing.expectError(error.InvalidGraderQualification, fixture.inspect());
}

test "capture rejects unsafe proof paths and stale or malformed report bytes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, tmp.dir);
    var unsafe = paths;
    unsafe.panel = "../panel.json";
    try std.testing.expectError(error.InvalidGraderQualification, q.inspect(std.testing.io, a, tmp.dir, unsafe, fixture.selected, rubric_bytes, &.{source}, config));
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = report_paths[0], .data = "{}" });
    try unresolved(.report_stale, try fixture.inspect());
    const records = try a.dupe(q.SpecimenReport, fixture.qualification.outcome.qualified.reports);
    records[0].sha256 = try q.sha256(a, "{}");
    fixture.qualification.outcome.qualified.reports = records;
    try fixture.saveDeclarations();
    try std.testing.expectError(error.InvalidGraderQualification, fixture.inspect());
}

test "persisted grader reports cannot reconstruct omitted protocol and acceptance metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "schema", "prompt_revision", "judgment_schema", "protocol_sha256", "acceptance", "grader_qualification" }) |missing| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var fixture = try Fixture.init(a, tmp.dir);
        var tree = try std.json.parseFromSliceLeaky(std.json.Value, a, try reports.json(a, fixture.results[0]), .{});
        try std.testing.expect(tree.object.swapRemove(missing));
        const bytes = try std.json.Stringify.valueAlloc(a, tree, .{});
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = report_paths[0], .data = bytes });
        const records = try a.dupe(q.SpecimenReport, fixture.qualification.outcome.qualified.reports);
        records[0].sha256 = try q.sha256(a, bytes);
        fixture.qualification.outcome.qualified.reports = records;
        try fixture.saveDeclarations();
        try std.testing.expectError(error.InvalidGraderQualification, fixture.inspect());
    }
}
