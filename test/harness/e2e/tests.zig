const std = @import("std");
const c = @import("contracts.zig");
const fixture = @import("fixture.zig");
const oracle = @import("oracle.zig");
const run_directory = @import("run_directory.zig");
const artifacts = @import("../../../src/domain/workflow_artifact_registry.zig");
const expected = [_]c.Artifact{ .specification, .reference_context, .clarification_state, .workflow_state };
const selected: c.Case = .{
    .schema = "spec-e2e-case/v1",
    .id = "one-reference",
    .workflow_id = "spec-generation",
    .feature = "chosen",
    .reference = "first",
    .config = "config.json",
    .evaluation_case = "evaluation.case.json",
    .evaluation_config = "evaluation.json",
    .directories = &.{"empty"},
    .files = &.{.{ .source = "source.md", .destination = "references/first/source.md" }},
    .expected_artifacts = &expected,
};

test "E2E command selects one live case and rejects mock modes and extra cases" {
    const parse = @import("cli.zig").parse;
    try std.testing.expectEqualStrings("case.json", try parse(&.{ "--case", "case.json" }));
    for ([_][]const []const u8{ &.{}, &.{"case.json"}, &.{ "--case", "one.json", "--case", "two.json" }, &.{ "--case", "case.json", "--mock" }, &.{ "--case", "case.json", "--scripted" }, &.{ "--suite", "suite.json" }, &.{ "--case", "../case.json" }, &.{ "--case", "/case.json" } }) |arguments| {
        if (parse(arguments)) |_| return error.AcceptedInvalidE2EArguments else |err| switch (err) {
            error.InvalidArguments, error.InvalidEvaluationContract => {},
            else => return err,
        }
    }
}

test "E2E case is closed and cannot preseed arbitrary destination collisions" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const valid = try std.json.Stringify.valueAlloc(a, selected, .{});
    _ = try c.parse(a, valid);
    for ([_][2][]const u8{
        .{ "\"spec-e2e-case/v1\"", "\"spec-e2e-case/v2\"" },
        .{ "\"id\":", "\"unknown\":true,\"id\":" },
        .{ "\"id\":", "\"provider_script\":\"script.json\",\"id\":" },
        .{ "\"id\":", "\"expected_specification\":\"expected.md\",\"id\":" },
        .{ "\"id\":", "\"id\":\"duplicate\",\"id\":" },
        .{ "references/first/source.md", "../spec.md" },
        .{ "references/first/source.md", ".sddtoolkit.json" },
        .{ "source.md\",\"destination", "/source.md\",\"destination" },
        .{ "\"reference_context\"", "\"specification\"" },
    }) |change| {
        const invalid = try std.mem.replaceOwned(u8, a, valid, change[0], change[1]);
        try std.testing.expect(!std.mem.eql(u8, valid, invalid));
        if (c.parse(a, invalid)) |_| return error.AcceptedInvalidE2ECase else |err| switch (err) {
            error.InvalidE2ECase, error.InvalidEvaluationContract => {},
            else => return err,
        }
    }
    var collision = selected;
    collision.files = &.{
        .{ .source = "one.md", .destination = "refs/Source.md" },
        .{ .source = "two.md", .destination = "refs/source.md/child" },
    };
    try std.testing.expectError(error.InvalidE2ECase, c.parse(a, try std.json.Stringify.valueAlloc(a, collision, .{})));
}

fn writeEvaluation(io: std.Io, repository: std.Io.Dir) !void {
    try repository.writeFile(io, .{ .sub_path = "evaluation.case.json", .data =
        \\{"schema":"evaluation-case/v1","id":"one-reference","sources":[{"id":"source","path":"source.md"}],"rubric":"rubric.json"}
    });
    try repository.writeFile(io, .{ .sub_path = "rubric.json", .data = @embedFile("../../e2e/wf-001-hello-world/node-vitest/rubric/spec.json") });
    try repository.writeFile(io, .{ .sub_path = "evaluation.json", .data = @embedFile("../../e2e/config/evaluation.json") });
}

fn preparedOutput(allocator: std.mem.Allocator, paths: artifacts.FeaturePaths) !@import("../../../src/domain/workflow_output.zig").Prepared {
    const output = @import("../../../src/domain/workflow_output.zig");
    const files = try allocator.alloc(output.File, expected.len);
    inline for (expected, 0..) |artifact, index| files[index] = .{
        .target = .{ .artifact = @field(@FieldType(output.Target, "artifact"), @tagName(artifact)) },
        .bytes = "published bytes\n",
    };
    return .{
        .feature = .{ .selector = paths.feature, .root_observation = .absent, .observation = .absent },
        .paths = paths,
        .prior = .{ .state = null, .forms = &.{} },
        .prior_workflow_state = .{ .captured = null },
        .files = files,
    };
}

test "production E2E binding honors configured models and cannot succeed without real credentials" {
    const io = std.testing.io;
    for (0..2) |example| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const choice = try c.parse(a, @embedFile("../../e2e/wf-001-hello-world/node-vitest/workflow.case.json"));
        const captured = try fixture.capture(io, a, .cwd(), choice);
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try fixture.materialize(io, project.dir, captured);
        const model = if (example == 0) "openai.gpt-oss-20b-1:0" else "anthropic.claude-3-5-haiku-20241022-v1:0";
        if (example == 1) {
            const model_config = try std.mem.replaceOwned(u8, a, captured.config, "openai.gpt-oss-20b-1:0", model);
            // Claude has no registered reasoning-effort control.
            try project.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = try std.mem.replaceOwned(u8, a, model_config, "\"reasoningEffort\": \"low\"", "\"reasoningEffort\": null") });
            const catalogue = try @import("../files.zig").read(io, a, project.dir, ".sddtoolkit/providers/.sddproviders.json");
            const replaced = try std.mem.replaceOwned(u8, a, catalogue, "openai.gpt-oss-20b-1:0", model);
            try project.dir.writeFile(io, .{ .sub_path = ".sddtoolkit/providers/.sddproviders.json", .data = try std.mem.replaceOwned(u8, a, replaced, "ap-southeast-2", "us-west-2") });
            try project.dir.writeFile(io, .{ .sub_path = "references/hello-world/stories.md", .data = "A library user renews a loan and sees its new due date.\n" });
        }
        var report: c.Report = .{ .started_at_utc = "2026-09-11T00:00:00Z", .status = .input_invalid };
        var evidence_run = std.testing.tmpDir(.{});
        defer evidence_run.cleanup();
        const store: @import("../evidence.zig").Store = .{ .io = io, .allocator = a, .run = evidence_run.dir, .secrets = &.{} };
        const output = try @import("invoke.zig").run(io, a, project.dir, choice, captured, null, store, &report);
        try std.testing.expect(output == null);
        try std.testing.expectEqual(.live, report.origin);
        try std.testing.expectEqual(.workflow_failed, report.status);
        try std.testing.expectEqual(.failed, report.workflow_outcome.?);
        try std.testing.expectEqualStrings("failed", report.diagnostic.?);
        try std.testing.expectEqualStrings("authentication_failed", report.provider_diagnostic.?);
        try std.testing.expectEqual(@as(usize, 0), report.model_calls);
        try std.testing.expectEqualStrings(model, report.models[0].model);
        try std.testing.expectEqualStrings("aws-bedrock", report.models[0].provider);
        try std.testing.expectEqual(.not_evaluated, report.semantic_quality);
        const events = try @import("../files.zig").read(io, a, evidence_run.dir, report.events_file.?);
        try std.testing.expect(std.mem.indexOf(u8, events, "authentication_failed") != null);
        try std.testing.expect(report.last_model_call == null);
        try std.testing.expect(report.evaluation == null);
        try std.testing.expectError(error.FileNotFound, project.dir.access(io, "specs/hello-world/spec.md", .{}));
        try fixture.verifySources(io, a, .cwd(), captured);
    }
}

test "evaluation source capture accounts every selected reference and remains immutable" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var repository = std.testing.tmpDir(.{});
    defer repository.cleanup();
    try repository.dir.writeFile(io, .{ .sub_path = "config.json", .data = "config" });
    try repository.dir.writeFile(io, .{ .sub_path = "source.md", .data = "New UTC requirement.\n" });
    try writeEvaluation(io, repository.dir);
    const captured = try fixture.capture(io, a, repository.dir, selected);
    try std.testing.expectEqualStrings("New UTC requirement.\n", captured.evaluation.sources[0].text);
    try fixture.validateEvaluationSources(a, captured, "references/", "first");
    try std.testing.expectError(error.EvaluationSourceMismatch, fixture.validateEvaluationSources(a, captured, "references", "other"));
    var extra = captured;
    extra.files = &.{ captured.files[0], .{ .mapping = .{ .source = "extra.md", .destination = "references/first/extra.md" }, .bytes = "Unrepresented requirement." } };
    try std.testing.expectError(error.EvaluationSourceMismatch, fixture.validateEvaluationSources(a, extra, "references", "first"));
    // Equal counts must not hide one source duplicated and another omitted.
    extra.evaluation.case.sources = &.{ .{ .id = "source", .path = "source.md" }, .{ .id = "other", .path = "other.md" } };
    extra.evaluation.sources = &.{ captured.evaluation.sources[0], .{ .id = "other", .text = "Other requirement." } };
    extra.files = &.{ captured.files[0], .{ .mapping = .{ .source = "source.md", .destination = "references/first/duplicate.md" }, .bytes = captured.files[0].bytes } };
    try std.testing.expectError(error.EvaluationSourceMismatch, fixture.validateEvaluationSources(a, extra, "references", "first"));
    try repository.dir.writeFile(io, .{ .sub_path = "source.md", .data = "Changed later." });
    try std.testing.expectEqualStrings("New UTC requirement.\n", captured.evaluation.sources[0].text);
    try std.testing.expectError(error.FixtureChanged, fixture.verifySources(io, a, repository.dir, captured));
}

test "published artifact replacement cannot be graded as the generating execution" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    const paths = try resolve(a);
    const prepared = try preparedOutput(a, paths);
    inline for (expected) |artifact| {
        const path = paths.get(@field(artifacts.Artifact, @tagName(artifact))).project_relative;
        try project.dir.createDirPath(io, std.fs.path.dirname(path).?);
        try project.dir.writeFile(io, .{ .sub_path = path, .data = "published bytes\n" });
    }
    const first = try oracle.inspect(io, a, project.dir, .ok, .{ .confirmed = &prepared }, &expected, paths);
    try std.testing.expectEqualStrings("published bytes\n", first.specification_bytes.?);
    try project.dir.writeFile(io, .{ .sub_path = paths.get(.specification).project_relative, .data = "An unrelated replacement." });
    const changed = try oracle.inspect(io, a, project.dir, .ok, .{ .confirmed = &prepared }, &expected, paths);
    try std.testing.expectEqual(.artifact_changed, changed.status);
    try std.testing.expect(changed.specification_bytes == null);
    try std.testing.expectEqualStrings("published bytes\n", first.specification_bytes.?);
}

test "rubric handoff preserves poor output and scores without changing workflow authority" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const choice = try c.parse(a, @embedFile("../../e2e/wf-001-hello-world/node-vitest/workflow.case.json"));
    const captured = try fixture.capture(io, a, .cwd(), choice);
    const evaluation = @import("evaluation.zig");
    var report: c.Report = .{ .started_at_utc = "2026-09-11T00:00:00Z", .status = .generated, .workflow_outcome = .ok, .publication_check = .passed, .specification = "specs/hello-world/spec.md", .models = &.{.{ .slot = "spec_generation", .provider = "aws-bedrock", .model = "openai.gpt-oss-20b-1:0" }} };
    const inputs = try evaluation.inputs(a, report, captured.evaluation, "Readable but poor output.", "run-123");
    try std.testing.expectEqualStrings("Readable but poor output.", inputs.specification);
    try std.testing.expectEqualStrings("run-123", inputs.generation.execution_id.?);
    try std.testing.expectEqual(.live_generation, inputs.generation.origin);
    for ([_]@import("../../../src/domain/workflow.zig").OutcomeTag{ .failed, .invalid, .blocked, .cancelled, .needs_user }) |outcome| {
        var failed = report;
        failed.workflow_outcome = outcome;
        try std.testing.expectError(error.GenerationNotCompleted, evaluation.inputs(a, failed, captured.evaluation, "stale output", "run-124"));
    }
    const config = try @import("../configuration.zig").parse(a, captured.evaluation.config_bytes, .{ .api = .bedrock_converse, .model = @import("../contracts.zig").ModelId.parse("openai.gpt-oss-20b-1:0").?, .region = .@"ap-southeast-2" });
    const result: @import("../report.zig").Report = .{ .capture = inputs, .configuration = config, .attempts = &.{}, .outcome = .{ .evaluated = .{ .results = &.{}, .assessment = .scored, .score_percent = 10, .threshold = .not_met } } };
    evaluation.apply(&report, result);
    try std.testing.expectEqual(.scored, report.semantic_quality);
    try std.testing.expectEqual(.ok, report.workflow_outcome.?);
    try std.testing.expectEqual(@as(f64, 10), report.evaluation.?.outcome.evaluated.score_percent.?);
    var failed_judge = result;
    failed_judge.outcome = .{ .evaluator_error = .authentication };
    evaluation.apply(&report, failed_judge);
    try std.testing.expectEqual(.evaluator_failed, report.status);
    try std.testing.expectEqual(.ok, report.workflow_outcome.?);
    try std.testing.expect(report.specification != null);
    try std.testing.expectEqual(.evaluator_error, report.semantic_quality);
}

test "one dated E2E directory retains one isolated project per invocation" {
    const io = std.testing.io;
    var parent = std.testing.tmpDir(.{});
    defer parent.cleanup();
    const first = try run_directory.Run.create(io, parent.dir);
    defer first.close(io);
    const second = try run_directory.Run.create(io, parent.dir);
    defer second.close(io);
    try std.testing.expect(!std.mem.eql(u8, &first.name, &second.name));
    try first.project.writeFile(io, .{ .sub_path = "spec.md", .data = "first" });
    try std.testing.expectError(error.FileNotFound, second.project.access(io, "spec.md", .{}));
    try std.testing.expectError(error.FileNotFound, first.dir.access(io, "case-00", .{}));
    const name = run_directory.directoryName("2026-09-10T09:08:07Z".*, @splat(0x11));
    try std.testing.expectEqualStrings("2026-09-10T09-08-07Z-11111111111111111111111111111111", &name);
    const concurrent = run_directory.directoryName("2026-09-10T09:08:07Z".*, @splat(0x22));
    try std.testing.expect(!std.mem.eql(u8, &name, &concurrent));
}

test "fixture copy preserves declared reference bytes and rejects preseeded output and aliases" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var repository = std.testing.tmpDir(.{});
    defer repository.cleanup();
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try repository.dir.writeFile(io, .{ .sub_path = "config.json", .data = "declared config" });
    try repository.dir.writeFile(io, .{ .sub_path = "source.md", .data = "The library renews a loan.\n" });
    try writeEvaluation(io, repository.dir);
    const captured = try fixture.capture(io, a, repository.dir, selected);
    try fixture.materialize(io, project.dir, captured);
    const copy = try project.dir.readFileAlloc(io, "references/first/source.md", a, .limited(1024));
    try std.testing.expectEqualStrings("The library renews a loan.\n", copy);
    try fixture.verifySources(io, a, repository.dir, captured);
    try fixture.validateOutputs(captured, .{ .specs = "outputs", .archive = "archive", .workflows = "engine" }, a);
    var forged = captured;
    forged.files = &.{.{ .mapping = .{ .source = "source.md", .destination = "outputs/chosen/spec.md" }, .bytes = "stale" }};
    try std.testing.expectError(error.FixtureContainsWorkflowOutput, fixture.validateOutputs(forged, .{ .specs = "outputs", .archive = "archive", .workflows = "engine" }, a));
    try repository.dir.writeFile(io, .{ .sub_path = "source.md", .data = "changed" });
    try std.testing.expectError(error.FixtureChanged, fixture.verifySources(io, a, repository.dir, captured));
    try repository.dir.symLink(io, "source.md", "alias.md", .{});
    var aliased = selected;
    aliased.files = &.{.{ .source = "alias.md", .destination = "references/first/source.md" }};
    try std.testing.expectError(error.InputUnavailable, fixture.capture(io, a, repository.dir, aliased));
}

fn resolve(a: std.mem.Allocator) !artifacts.FeaturePaths {
    const feature = try @import("../../../src/domain/feature_directory.zig").validate(a, .{ .bytes = "chosen" }, .{ .specs = "outputs", .archive = "archive" });
    return artifacts.resolveFeaturePaths(a, .{ .specs = "outputs", .archive = "archive", .workflows = "engine" }, feature);
}

test "E2E oracle requires actual publication and every expected file" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    const paths = try resolve(a);
    const prepared = try preparedOutput(a, paths);
    try std.testing.expectEqual(.publication_missing, (try oracle.inspect(io, a, project.dir, .ok, .not_observed, &expected, paths)).status);
    try std.testing.expectEqual(.artifact_missing, (try oracle.inspect(io, a, project.dir, .ok, .{ .confirmed = &prepared }, &expected, paths)).status);
    inline for (expected) |artifact| {
        const path = paths.get(@field(artifacts.Artifact, @tagName(artifact))).project_relative;
        try project.dir.createDirPath(io, std.fs.path.dirname(path).?);
        try project.dir.writeFile(io, .{ .sub_path = path, .data = "published bytes\n" });
    }
    try std.testing.expectEqual(.publication_missing, (try oracle.inspect(io, a, project.dir, .ok, .not_observed, &expected, paths)).status);
    const passed = try oracle.inspect(io, a, project.dir, .ok, .{ .confirmed = &prepared }, &expected, paths);
    try std.testing.expectEqual(.generated, passed.status);
    try std.testing.expectEqualStrings("outputs/chosen/spec.md", passed.specification.?);
    for ([_]@import("../../../src/domain/workflow.zig").OutcomeTag{ .failed, .invalid, .blocked, .cancelled, .needs_user, .more }) |outcome| {
        const result = try oracle.inspect(io, a, project.dir, outcome, .{ .confirmed = &prepared }, &expected, paths);
        try std.testing.expectEqual(.workflow_failed, result.status);
        try std.testing.expect(result.specification == null);
    }
    try project.dir.deleteFile(io, paths.get(.workflow_state).project_relative);
    const missing = try oracle.inspect(io, a, project.dir, .ok, .{ .confirmed = &prepared }, &expected, paths);
    try std.testing.expectEqual(.artifact_missing, missing.status);
    try std.testing.expectEqual(.workflow_state, missing.missing_artifact.?);
    try std.testing.expect(missing.specification == null);
}

test "failure reports preserve separate engine provider and model evidence" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const output = try @import("report.zig").Output.reserve(io, dir.dir);
    defer output.close(io);
    const report: c.Report = .{
        .started_at_utc = "2026-09-11T00:00:00Z",
        .execution_id = "run-failed",
        .case_source = "chosen.case.json",
        .status = .workflow_failed,
        .workflow_outcome = .failed,
        .diagnostic = "ENGINE_REJECTION",
        .provider_diagnostic = "output_limit",
        .model_diagnostic = "InvalidModelEnvelope",
        .json_error = .{ .reason = .SyntaxError, .location = .{ .byte_offset = 9, .line = 2, .column = 8 } },
        .schema_error = .{ .reason = .missing_required_property, .path = "/statements/0/content/kind" },
        .candidate_error = .{ .token_classifications = .{
            .scope = .{ .state_id = .{ .bytes = "current-state" }, .chunk_id = .{ .bytes = "chunk-2" } },
            .revision = 3,
            .issues = .{ .missing = &.{.{ .source_id = .{ .ordinal = 2 }, .extractor_id = .markdown_inline_code_v1, .ordinal = 7 }}, .duplicate = &.{}, .unknown = &.{}, .forbidden = &.{} },
        } },
        .last_model_usage = @import("../../../src/domain/llm_provider_operation.zig").ProviderUsage.init(100, 512, 612).?,
    };
    try output.save(io, a, report);
    const bytes = try @import("../files.zig").read(io, a, dir.dir, "report.json");
    const retained = try @import("../contracts.zig").decode(c.Report, a, bytes);
    try std.testing.expectEqualStrings("ENGINE_REJECTION", retained.diagnostic.?);
    try std.testing.expectEqualStrings("output_limit", retained.provider_diagnostic.?);
    try std.testing.expectEqualStrings("InvalidModelEnvelope", retained.model_diagnostic.?);
    try std.testing.expectEqualDeep(report.json_error, retained.json_error);
    try std.testing.expectEqualDeep(report.schema_error, retained.schema_error);
    try std.testing.expectEqualDeep(report.candidate_error, retained.candidate_error);
    try std.testing.expectEqualStrings("run-failed", retained.execution_id.?);
    try std.testing.expectEqual(.not_evaluated, retained.semantic_quality);
    try std.testing.expect(retained.evaluation == null);
    const view = try @import("../files.zig").read(io, a, dir.dir, "report.md");
    try std.testing.expect(std.mem.indexOf(u8, view, "provider stopped generation at its output limit") != null);
    try std.testing.expect(std.mem.indexOf(u8, view, "100 input + 512 output = 612 tokens") != null);
    try std.testing.expect(std.mem.indexOf(u8, view, "No rubric grade is available") != null);
    const terminal = try @import("report.zig").terminal(a, report, "runs", "example");
    for ([_][]const u8{ view, terminal }) |rendered|
        try std.testing.expect(std.mem.indexOf(u8, rendered, "JSON error: SyntaxError at line 2, column 8 (byte offset 9)") != null);
    const diagnostic = try std.json.Stringify.valueAlloc(a, report.candidate_error.?, .{});
    for ([_][]const u8{ view, terminal }) |rendered| try std.testing.expect(std.mem.indexOf(u8, rendered, diagnostic) != null);
    const schema_diagnostic = try std.json.Stringify.valueAlloc(a, report.schema_error.?, .{});
    for ([_][]const u8{ view, terminal }) |rendered| try std.testing.expect(std.mem.indexOf(u8, rendered, schema_diagnostic) != null);
    try std.testing.expect(std.mem.indexOf(u8, terminal, "runs/example/report.json") != null);
    try std.testing.expectError(error.PathAlreadyExists, @import("report.zig").Output.reserve(io, dir.dir));
}

test "evidence store retains distinct attempts excludes credentials and refuses overwrites" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var run = std.testing.tmpDir(.{});
    defer run.cleanup();
    var secret: [32]u8 = undefined;
    io.random(&secret);
    for (&secret) |*byte| byte.* = 'A' + byte.* % 26;
    const store: @import("../evidence.zig").Store = .{ .io = io, .allocator = a, .run = run.dir, .secrets = &.{&secret} };
    for ([_][]const u8{ "```json\n{}\n```", "{\"unrelated\": }" }, 1..) |body, ordinal| {
        try store.write(.generation, ordinal, .model_output, body);
        const path = try @import("../evidence.zig").Store.path(a, .generation, ordinal, .model_output);
        try std.testing.expectEqualStrings(body, try @import("../files.zig").read(io, a, run.dir, path));
        try std.testing.expectError(error.PathAlreadyExists, store.write(.generation, ordinal, .model_output, "replacement"));
    }
    const body = try std.fmt.allocPrint(a, "{{\"echo\":\"{s}\",\"result\":42}}", .{secret});
    try store.write(.evaluation, 1, .response, body);
    const saved = try @import("../files.zig").read(io, a, run.dir, "evidence/evaluation/call-000001/response.json");
    try std.testing.expect(std.mem.indexOf(u8, saved, &secret) == null);
    try std.testing.expectEqualStrings("{\"echo\":\"[REDACTED_CREDENTIAL]\",\"result\":42}", saved);
}

test "input failure report explains environment setup and escapes untrusted labels" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const report: c.Report = .{
        .started_at_utc = "2026-09-12T00:00:00Z",
        .case_id = "<script> [click](untrusted)",
        .status = .input_invalid,
        .diagnostic = "InvalidEvaluationEnvironment",
    };
    const view = try @import("report.zig").renderMarkdown(arena.allocator(), report);
    try std.testing.expect(std.mem.indexOf(u8, view, "Input setup failed before workflow execution") != null);
    try std.testing.expect(std.mem.indexOf(u8, view, "scripts/e2e-spec.sh") != null);
    try std.testing.expect(std.mem.indexOf(u8, view, "workflow: not_run") == null);
    try std.testing.expect(std.mem.indexOf(u8, view, "Workflow outcome: not_run") != null);
    try std.testing.expect(std.mem.indexOf(u8, view, "<script>") == null);
    try std.testing.expect(std.mem.indexOf(u8, view, "\\[click\\]") != null);
}
