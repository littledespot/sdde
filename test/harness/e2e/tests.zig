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
        .terminal_outcome = .ok,
        .feature = .{ .selector = paths.feature, .root_observation = .absent, .observation = .absent },
        .paths = paths,
        .prior = .{ .state = null, .forms = &.{} },
        .prior_workflow_state = .{ .captured = null },
        .files = files,
    };
}

test "shipped workflow conforms to native registrations and rejects contract drift before invocation" {
    const Runtime = @import("../../../src/composition/root.zig").Runtime;
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const choice = try c.parse(a, @embedFile("../../e2e/wf-001-hello-world/node-vitest/workflow.case.json"));
    const captured = try fixture.capture(io, a, .cwd(), choice);
    const workflow_file = for (captured.files) |file| {
        if (std.mem.eql(u8, file.mapping.source, "design/workflows/spec.workflow.yaml")) break file;
    } else return error.MissingWorkflowFixture;
    const mutations = [_][2][]const u8{
        .{ "use: collect-specification-support", "use: unregistered-support-reader" },
        .{ "use: collect-specification-support", "use: apply-specification-support" },
        .{ "retry-limit: 1", "retry-limit: -1" },
        .{ "selection: input", "selection: missing-definition" },
        .{ "composition-part: content", "composition-part: classifications" },
        .{ "use: retain-json-part", "use: check-model-request-phase" },
    };
    for (0..mutations.len + 1) |index| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try fixture.materialize(io, project.dir, captured);
        if (index > 0) {
            const change = mutations[index - 1];
            const changed = try std.mem.replaceOwned(u8, a, workflow_file.bytes, change[0], change[1]);
            try std.testing.expect(!std.mem.eql(u8, workflow_file.bytes, changed));
            try project.dir.writeFile(io, .{ .sub_path = workflow_file.mapping.destination, .data = changed });
        }
        var runtime: Runtime = undefined;
        runtime.init(io, std.testing.allocator, project.dir, .{});
        defer runtime.deinit();
        try std.testing.expectEqual(index == 0, runtime.boot == .ready);
        if (index == 0) {
            // Exercise the existing registry's cross-owner checks, with no model
            // provider or workflow invocation. No parallel contract is constructed.
            try std.testing.expect(runtime.native.registry.validate());
            const graph = runtime.boot.ready.workflows.registry().resolve(.{ .bytes = choice.workflow_id }).?;
            // A registered native request remains forbidden inside active
            // composition, even when its ordinary data contract still matches.
            const InvalidSelection = enum { unknown_part, ordinary_request, missing_schema };
            for ([_]InvalidSelection{ .unknown_part, .ordinary_request, .missing_schema }) |fault| {
                var invalid_graph = graph.*;
                const steps = try a.dupe(@import("../../../src/domain/workflow_compilation.zig").CompiledStep, graph.authority.steps);
                invalid_graph.authority.steps = steps;
                var changed_part = false;
                for (steps) |*step| {
                    const parameters = try a.dupe(@import("../../../src/domain/workflow_compilation.zig").CompiledParameter, step.parameters);
                    for (parameters, 0..) |*parameter, parameter_index| {
                        if (!std.mem.eql(u8, parameter.id.bytes, if (fault == .missing_schema) "result-schema" else "composition-part")) continue;
                        if (fault == .ordinary_request) {
                            parameter.id.bytes = "result-schema";
                            parameter.value = .{ .resource = .{ .bytes = "extraction-schema" } };
                        } else if (fault == .missing_schema) {
                            std.mem.copyForwards(@import("../../../src/domain/workflow_compilation.zig").CompiledParameter, parameters[parameter_index .. parameters.len - 1], parameters[parameter_index + 1 ..]);
                        } else parameter.value = .{ .string = "unknown-part" };
                        step.parameters = if (fault == .missing_schema) parameters[0 .. parameters.len - 1] else parameters;
                        changed_part = true;
                        break;
                    }
                    if (changed_part) break;
                }
                try std.testing.expect(changed_part);
                try std.testing.expectError(error.WorkflowGraphCompileInvalid, (@import("../../../src/actions/workflow/validate_compiled_workflow_graphs.zig").Action{}).execute(a, &.{invalid_graph}));
            }
            const protocol = for (captured.files) |file| {
                if (std.mem.eql(u8, file.mapping.source, "design/workflows/spec/protocol.prompt.md")) break file.bytes;
            } else return error.MissingProtocolPrompt;
            var model_requests: usize = 0;
            for (graph.authority.steps) |step| {
                if (step.model == null) continue;
                model_requests += 1;
                const prompt_id = for (step.parameters) |parameter| {
                    if (std.mem.eql(u8, parameter.id.bytes, "protocol-prompt")) break parameter.value.resource;
                } else return error.MissingProtocolPrompt;
                const resource = for (graph.authority.resources) |resource| {
                    if (std.mem.eql(u8, resource.id.bytes, prompt_id.bytes)) break resource;
                } else return error.MissingProtocolPrompt;
                try std.testing.expectEqualStrings(protocol, resource.content.prompt);
            }
            try std.testing.expect(model_requests > 0);
            var missing_schema = runtime.native.registry;
            missing_schema.data_schemas = &.{};
            try std.testing.expect(!missing_schema.validate());
            var duplicate = runtime.native.registry;
            const entries = try a.alloc(@TypeOf(duplicate.operations[0]), duplicate.operations.len + 1);
            @memcpy(entries[0..duplicate.operations.len], duplicate.operations);
            entries[duplicate.operations.len] = duplicate.operations[0];
            duplicate.operations = entries;
            try std.testing.expect(!duplicate.validate());
        }
    }
}

test "shared production runtime preserves deferred environment capture and isolated snapshots" {
    const Runtime = @import("../../../src/composition/root.zig").Runtime;
    const key = @import("../../../src/adapters/provider/bedrock_api_key.zig");
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const choice = try c.parse(a, @embedFile("../../e2e/wf-001-hello-world/node-vitest/workflow.case.json"));
    const captured = try fixture.capture(io, a, .cwd(), choice);
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try fixture.materialize(io, project.dir, captured);
    for ([_]?[]const u8{ null, "", "invalid key", "isolated-credential" }) |raw| {
        inline for (.{ false, true }) |from_environment| {
            var environment: std.process.Environ.Map = .init(std.testing.allocator);
            defer environment.deinit();
            if (from_environment) {
                if (raw) |bytes| try environment.put("AWS_BEARER_TOKEN_BEDROCK", bytes);
            } else {
                // A direct missing/invalid credential cannot use an ambient key.
                try environment.put("AWS_BEARER_TOKEN_BEDROCK", "ambient-credential");
            }
            var runtime: Runtime = undefined;
            runtime.init(io, std.testing.allocator, project.dir, .{});
            defer runtime.deinit();
            try std.testing.expect(runtime.boot == .ready);
            var invocation = runtime.invocation(&.{ choice.workflow_id, "--feature", choice.feature, "--reference", choice.reference }, if (from_environment)
                .{ .environment = &environment }
            else
                .{ .snapshot = try key.Snapshot.capture(std.testing.allocator, raw) });
            defer invocation.deinit();
            if (from_environment) try std.testing.expect(runtime.provider_runtime.authorization.material == .unavailable);
            const bindings = invocation.bindings();
            try std.testing.expectEqual(.ok, bindings.invokeValidateOperationRegistry());
            try std.testing.expectEqual(.ok, bindings.invokeParseInvocation());
            try std.testing.expectEqual(.ok, bindings.invokeSelectWorkflow());
            try std.testing.expectEqual(.ok, bindings.invokePrepareWorkflow());
            try std.testing.expect(runtime.provider_runtime.provider != null);
            const material = runtime.provider_runtime.authorization.material;
            const valid = if (raw) |bytes| std.mem.eql(u8, bytes, "isolated-credential") else false;
            try std.testing.expectEqual(valid, material == .ready);
            if (valid) {
                try environment.put("AWS_BEARER_TOKEN_BEDROCK", "changed-credential");
                try std.testing.expectEqualStrings(raw.?, material.ready.bytes);
            }
            // Preparation exercises production binding without invoking HTTP.
        }
    }
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
        try std.testing.expectEqual(.not_run, report.semantic_quality);
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
    try std.testing.expectEqual(.evaluated, report.status);
    const terminal = try @import("report.zig").terminal(a, report, "runs", "sample");
    try std.testing.expect(std.mem.indexOf(u8, terminal, "threshold: not_met; score: 10.00%") != null);
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
    try std.testing.expectEqual(.publication_missing, (try oracle.inspect(io, a, project.dir, .needs_user, .not_observed, &expected, paths)).status);
    const passed = try oracle.inspect(io, a, project.dir, .ok, .{ .confirmed = &prepared }, &expected, paths);
    try std.testing.expectEqual(.generated, passed.status);
    try std.testing.expectEqualStrings("outputs/chosen/spec.md", passed.specification.?);
    const outcomes = [_]@import("../../../src/domain/workflow.zig").OutcomeTag{ .failed, .invalid, .blocked, .cancelled, .needs_user, .more };
    const statuses = [_]c.Status{ .workflow_failed, .workflow_invalid, .workflow_blocked, .workflow_cancelled, .awaiting_clarification, .workflow_failed };
    for (outcomes, statuses) |outcome, status| {
        const result = try oracle.inspect(io, a, project.dir, outcome, .{ .confirmed = &prepared }, &expected, paths);
        try std.testing.expectEqual(status, result.status);
        if (outcome == .needs_user) {
            try std.testing.expectEqualStrings("outputs/chosen/spec.md", result.specification.?);
            try std.testing.expect(result.specification_bytes == null);
        } else try std.testing.expect(result.specification == null);
        try std.testing.expectEqual(outcome == .needs_user, result.status.commandSucceeded());
    }
    try project.dir.deleteFile(io, paths.get(.workflow_state).project_relative);
    const missing = try oracle.inspect(io, a, project.dir, .ok, .{ .confirmed = &prepared }, &expected, paths);
    try std.testing.expectEqual(.artifact_missing, missing.status);
    try std.testing.expectEqual(.workflow_state, missing.missing_artifact.?);
    try std.testing.expect(missing.specification == null);
    try std.testing.expectEqual(.artifact_missing, (try oracle.inspect(io, a, project.dir, .needs_user, .{ .confirmed = &prepared }, &expected, paths)).status);
}

test "clarification reports are ungraded normal pauses with registered IDs and paths" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const output = try @import("report.zig").Output.reserve(io, dir.dir);
    defer output.close(io);
    const id = @import("../../../src/domain/clarification_inputs.zig").Id.parse("S02").?;
    const report: c.Report = .{ .started_at_utc = "2026-09-16T00:00:00Z", .status = .awaiting_clarification, .workflow_outcome = .needs_user, .publication_check = .passed, .specification = "outputs/chosen/spec.md", .clarifications = &.{.{ .id = id, .path = try @import("../../../src/domain/workflow_output.zig").path(a, try resolve(a), .{ .form = id }) }} };
    try output.save(io, a, report);
    const bytes = try @import("../files.zig").read(io, a, dir.dir, "report.json");
    const retained = try @import("../contracts.zig").decode(c.Report, a, bytes);
    try std.testing.expectEqualDeep(report.clarifications, retained.clarifications);
    try std.testing.expectEqual(.passed, retained.publication_check);
    try std.testing.expectEqual(.not_run, retained.semantic_quality);
    try std.testing.expect(retained.diagnostic == null and retained.evaluation == null and retained.specification != null);
    try std.testing.expect(retained.status.commandSucceeded());
    for (std.meta.tags(c.Status)) |status| try std.testing.expectEqual(status == .awaiting_clarification or status == .evaluated, status.commandSucceeded());
    const markdown = try @import("../files.zig").read(io, a, dir.dir, "report.md");
    const terminal = try @import("report.zig").terminal(a, report, "runs", "example");
    for ([_][]const u8{ markdown, terminal }) |rendered| {
        try std.testing.expect(std.mem.indexOf(u8, rendered, "Awaiting clarification") != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, "S02") != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, "outputs/chosen/clarify/S02.md") != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, "publication: passed") != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, "Engine/harness error") == null);
    }
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
        .retry_error = .{ .operation_instance_id = .{ .bytes = "request-account" }, .retry_limit = 4, .completed_executions = 5 },
        .provider_diagnostic = "output_limit",
        .model_diagnostic = "InvalidModelEnvelope",
        .json_error = .{ .reason = .SyntaxError, .location = .{ .byte_offset = 9, .line = 2, .column = 8 } },
        .schema_error = .{ .reason = .missing_required_property, .path = "/statements/0/content/kind" },
        .candidate_error = .{ .token_classifications = .{
            .choices = .{ .outcome = .claims, .decisions = &.{ .preserve, .irrelevant } },
            .observed = &.{},
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
    try std.testing.expectEqualDeep(report.retry_error, retained.retry_error);
    try std.testing.expectEqualDeep(report.schema_error, retained.schema_error);
    try std.testing.expectEqualDeep(report.candidate_error, retained.candidate_error);
    try std.testing.expectEqualStrings("run-failed", retained.execution_id.?);
    try std.testing.expectEqual(.not_run, retained.semantic_quality);
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
    const retry_diagnostic = try std.json.Stringify.valueAlloc(a, report.retry_error.?, .{});
    for ([_][]const u8{ view, terminal }) |rendered| try std.testing.expect(std.mem.indexOf(u8, rendered, retry_diagnostic) != null);
    try std.testing.expect(std.mem.indexOf(u8, terminal, "runs/example/report.json") != null);
    try std.testing.expectError(error.PathAlreadyExists, @import("report.zig").Output.reserve(io, dir.dir));
}

test "retired protocol rejection stays associated with its call across later failures" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var snapshot: @import("observation.zig").LastModelRejection = .{};
    defer snapshot.deinit(std.testing.allocator);
    const empty: c.Report = .{ .started_at_utc = "", .status = .workflow_failed, .workflow_outcome = .failed };
    var rejected = empty;
    rejected.model_diagnostic = "InvalidModelEnvelope";
    rejected.last_model_origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    var key = "local_key".*;
    rejected.json_error = .{ .reason = .DuplicateField, .location = .{ .byte_offset = 437, .line = 1, .column = 438 }, .context = .{
        .path = "/statements/0",
        .key = &key,
        .first_occurrence = .{ .byte_offset = 16, .line = 1, .column = 17 },
        .repeated_occurrence = .{ .byte_offset = 426, .line = 1, .column = 427 },
    } };
    try snapshot.observe(std.testing.allocator, 5, rejected);
    // Transport retirement has removed the active decoder/payload slots.
    try snapshot.observe(std.testing.allocator, 5, empty);
    var exhausted = empty;
    exhausted.diagnostic = "RetryLimitExhausted";
    exhausted.retry_error = .{ .operation_instance_id = .{ .bytes = "account" }, .retry_limit = 4, .completed_executions = 5 };
    try snapshot.project(a, 5, &exhausted);
    try std.testing.expectEqualStrings("InvalidModelEnvelope", exhausted.model_diagnostic.?);
    try std.testing.expectEqualDeep(rejected.json_error, exhausted.json_error);
    @memset(&key, 'x');
    try std.testing.expectEqualStrings("local_key", snapshot.json_error.?.context.?.key.?);
    try std.testing.expectEqualStrings("local_key", exhausted.json_error.?.context.?.key.?);
    // A later call's schema error replaces the earlier syntax error.
    var path = "/items/0/kind".*;
    rejected.model_diagnostic = "missing_required_property";
    rejected.json_error = null;
    rejected.schema_error = .{ .reason = .missing_required_property, .path = &path };
    try snapshot.observe(std.testing.allocator, 6, rejected);
    @memset(&path, 'x');
    var later = empty;
    try snapshot.project(a, 6, &later);
    try std.testing.expect(later.json_error == null);
    try std.testing.expectEqualStrings("/items/0/kind", later.schema_error.?.path);
    var complete = empty;
    complete.workflow_outcome = .ok;
    try snapshot.project(a, 6, &complete);
    try std.testing.expect(complete.model_diagnostic == null);
    try snapshot.observe(std.testing.allocator, 7, empty);
    var fresh = empty;
    try snapshot.project(a, 7, &fresh);
    try std.testing.expect(fresh.model_diagnostic == null);
    try std.testing.expectEqual(@as(usize, 6), fresh.last_protocol_rejection.?.call);
    try std.testing.expectEqualDeep(rejected.last_model_origin.?, fresh.last_protocol_rejection.?.origin);
    // The final report owns its data after the observer releases the snapshot.
    try std.testing.expectEqualStrings("/items/0/kind", later.schema_error.?.path);
}

test "source selection reports retain the producing call separately from the last call" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const report: c.Report = .{
        .started_at_utc = "2026-09-12T00:00:00Z",
        .status = .workflow_failed,
        .candidate_error = .{ .source_selections = .{
            .observed = &.{},
            .scope = .{ .state_id = .{ .bytes = "current-state" }, .chunk_id = .{ .bytes = "chunk-2" } },
            .revision = 3,
            .claim_index = 2,
            .issue = .{ .reason = .unknown_selection, .index = 1, .rejected = .{ .first = .{ .ordinal = 1 }, .last = .{ .ordinal = 99 } }, .available = .{ .first = .{ .ordinal = 1 }, .last = .{ .ordinal = 4 } } },
            .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 2 } },
        } },
        .candidate_model_call = 2,
        .candidate_model_step = "extract",
        .candidate_model_output = "evidence/generation-call-0002.output.txt",
        .last_model_call = 5,
        .last_model_step = "repair",
        .last_model_output = "evidence/generation-call-0005.output.txt",
    };
    const retained = try @import("../contracts.zig").decode(c.Report, a, try std.json.Stringify.valueAlloc(a, report, .{}));
    try std.testing.expectEqualDeep(report, retained);
    const diagnostic = try std.json.Stringify.valueAlloc(a, report.candidate_error.?, .{});
    for ([_][]const u8{ try @import("report.zig").renderMarkdown(a, retained), try @import("report.zig").terminal(a, retained, "runs", "sample") }) |rendered| {
        try std.testing.expect(std.mem.indexOf(u8, rendered, diagnostic) != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, report.candidate_model_output.?) != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, report.last_model_output.?) != null);
    }
}

test "later budget transport and capture stops retain separate protocol and exchange evidence" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const obs = @import("observation.zig");
    const Usage = @import("../../../src/domain/llm_provider_operation.zig").ProviderUsage;
    var calls: [35]obs.Call = undefined;
    for (&calls, 1..) |*call, ordinal| call.* = .{ .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = @intCast(ordinal) } }, .step = "repair", .raw_response_available = true, .output_available = ordinal < 35 };
    var retained: obs.LastModelRejection = .{};
    defer retained.deinit(std.testing.allocator);
    try retained.observe(std.testing.allocator, 34, .{ .started_at_utc = "", .status = .workflow_failed, .last_model_origin = calls[33].origin, .model_diagnostic = "SyntaxError", .json_error = .{ .reason = .SyntaxError } });
    for (0..4) |stop| {
        var report: c.Report = .{
            .started_at_utc = "",
            .status = .workflow_failed,
            .workflow_outcome = .failed,
            .total_tokens = 100114,
            .total_token_budget = 100000,
            .terminal_rejection = .{ .kind = if (stop == 0) .token_budget else .operation_failed },
            .last_model_origin = calls[34].origin,
            .last_model_usage = if (stop == 2) null else Usage.init(2800, 18, 2818).?,
            .evidence_error = if (stop == 3) "EvidenceWriteFailed" else null,
        };
        calls[34].raw_response_available = stop != 2;
        calls[34].usage = null;
        try retained.observe(std.testing.allocator, 35, report);
        try retained.project(a, 35, &report);
        try obs.correlate(a, &calls, &report);
        try std.testing.expect(report.model_diagnostic == null and report.json_error == null);
        try std.testing.expectEqual(@as(usize, 34), report.last_protocol_rejection.?.call);
        try std.testing.expectEqual(@as(usize, 35), report.last_model_call.?);
        try std.testing.expect(report.last_model_output == null);
        const evidence = report.exchange_evidence.?;
        try std.testing.expectEqual(([_]@FieldType(c.ExchangeEvidence, "text"){ .budget_stop, .not_projected, .response_absent, .capture_failed })[stop], evidence.text);
        try std.testing.expectEqual(stop != 2, evidence.raw_response != null);
        if (stop != 2) try std.testing.expectEqual(@as(u64, 2818), report.last_model_usage.?.total_tokens) else try std.testing.expect(report.last_model_usage == null);
        const protocol = try std.json.Stringify.valueAlloc(a, report.last_protocol_rejection, .{});
        const exchange = try std.json.Stringify.valueAlloc(a, evidence, .{});
        for ([_][]const u8{ try std.json.Stringify.valueAlloc(a, report, .{}), try @import("report.zig").terminal(a, report, "runs", "example"), try @import("report.zig").renderMarkdown(a, report) }) |output| {
            try std.testing.expect(std.mem.indexOf(u8, output, protocol) != null);
            try std.testing.expect(std.mem.indexOf(u8, output, exchange) != null);
        }
    }
}

test "provider cause survives request release without inventing a candidate rejection" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const obs = @import("observation.zig");
    var calls = [_]obs.Call{.{
        .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } },
        .step = "extract",
        .raw_response_available = true,
        .status = 403,
        .exception = "AccessDeniedException",
        .request_id = "request-1",
    }};
    var observed: c.Report = .{ .started_at_utc = "", .status = .workflow_failed, .provider_diagnostic = "authorization_denied", .last_model_origin = calls[0].origin };
    try obs.correlate(a, &calls, &observed);
    // The next projection has no active request or provider observation slots.
    var released: c.Report = .{ .started_at_utc = "", .status = .workflow_failed, .usage_complete = false };
    try obs.correlate(a, &calls, &released);
    try std.testing.expectEqual(@as(usize, 1), released.last_model_call.?);
    try std.testing.expectEqualStrings("authorization_denied", released.provider_diagnostic.?);
    try std.testing.expect(released.model_diagnostic == null and released.last_model_output == null and released.last_model_usage == null);
    try std.testing.expect(released.last_protocol_rejection == null);
    try std.testing.expectEqual(@as(u16, 403), released.exchange_evidence.?.status.?);
    try std.testing.expect(released.exchange_evidence.?.raw_response != null);
    for ([_][]const u8{ try std.json.Stringify.valueAlloc(a, released, .{}), try @import("report.zig").terminal(a, released, "runs", "example"), try @import("report.zig").renderMarkdown(a, released) }, 0..) |output, index| {
        try std.testing.expect(std.mem.indexOf(u8, output, if (index == 2) "authorization\\_denied" else "authorization_denied") != null);
        try std.testing.expect(std.mem.indexOf(u8, output, "AccessDeniedException") != null);
    }
}

test "unrepairable responses preserve complete production logs and forbid publication with open clarifications" {
    for (0..3) |mode| {
        const io = std.testing.io;
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const choice = try c.parse(a, @embedFile("../../e2e/wf-001-hello-world/node-vitest/workflow.case.json"));
        const captured = try fixture.capture(io, a, .cwd(), choice);
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try fixture.materialize(io, project.dir, captured);
        const cf = @import("../../../src/test_fixtures/clarification_inputs.zig");
        var bootstrap: @import("../../../src/composition/root.zig").Runtime = undefined;
        bootstrap.init(io, std.testing.allocator, project.dir, .{});
        defer bootstrap.deinit();
        try std.testing.expect(bootstrap.boot == .ready);
        const roots = bootstrap.boot.ready.roots.registry();
        const selected_feature = try @import("../../../src/domain/feature_directory.zig").validate(a, .{ .bytes = choice.feature }, roots.featureDirectoryRoots());
        const paths = try artifacts.resolveFeaturePaths(a, roots.featureArtifactRoots(), selected_feature);
        const record = cf.record("S01");
        var pending = cf.state(&.{record});
        pending.feature_id = choice.feature;
        const state_bytes = try std.json.Stringify.valueAlloc(a, pending, .{});
        const form_bytes = try @import("../../../src/domain/clarification_form.zig").render(a, record, cf.binding(pending, record), .open, "");
        const form_path = try @import("../../../src/domain/workflow_output.zig").path(a, paths, .{ .form = @import("../../../src/domain/clarification_inputs.zig").Id.parse("S01").? });
        for ([_]struct { path: []const u8, bytes: []const u8 }{
            .{ .path = paths.get(.clarification_state).project_relative, .bytes = state_bytes },
            .{ .path = form_path.project_relative, .bytes = form_bytes },
        }) |file| {
            try project.dir.createDirPath(io, std.fs.path.dirname(file.path).?);
            try project.dir.writeFile(io, .{ .sub_path = file.path, .data = file.bytes });
        }
        var report: c.Report = .{ .started_at_utc = "", .status = .workflow_failed };
        {
            var runtime: @import("../../../src/composition/root.zig").Runtime = undefined;
            runtime.init(io, std.testing.allocator, project.dir, .{});
            defer runtime.deinit();
            try std.testing.expect(runtime.boot == .ready);
            var invocation = runtime.invocation(&.{ choice.workflow_id, "--feature", choice.feature, "--reference", choice.reference }, .{
                .snapshot = try @import("../../../src/adapters/provider/bedrock_api_key.zig").Snapshot.capture(std.testing.allocator, "isolated-credential"),
            });
            defer invocation.deinit();
            const bindings = invocation.bindings();
            try std.testing.expectEqual(.ok, bindings.invokeValidateOperationRegistry());
            try std.testing.expectEqual(.ok, bindings.invokeParseInvocation());
            try std.testing.expectEqual(.ok, bindings.invokeSelectWorkflow());
            try std.testing.expectEqual(.ok, bindings.invokePrepareWorkflow());
            var wire: @import("../../../src/bedrock_transport_test_fixture.zig").Wire = .{ .inference_body = "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"reasoningContent\":{\"reasoningText\":{\"text\":\"metadata\"}}}]}},\"stopReason\":\"end_turn\",\"usage\":{\"inputTokens\":884,\"outputTokens\":48,\"totalTokens\":932}}" };
            if (mode != 0) wire.inference_body = try std.fmt.allocPrint(a, "{{\"output\":{{\"message\":{{\"role\":\"assistant\",\"content\":[{{\"text\":{s}}}]}}}},\"stopReason\":\"end_turn\",\"usage\":{{\"inputTokens\":884,\"outputTokens\":48,\"totalTokens\":932}}}}", .{try std.json.Stringify.valueAlloc(a, if (mode == 1) "{" else "{}", .{})});
            runtime.provider_runtime.provider.?.aws_bedrock.transport = wire.port();
            const Prepared = struct {
                fn selected(_: *anyopaque) @import("../../../src/application/workflow_engine_child_bindings.zig").SelectionStepOutcome {
                    return .ok;
                }
                fn ready(_: *anyopaque) @import("../../../src/application/workflow_engine_child_bindings.zig").PreparationOutcome {
                    return .ok;
                }
            };
            // Bootstrap is already exercised; the production engine owns all execution transitions.
            var prepared = bindings.vtable.*;
            prepared.validate_operation_registry = Prepared.selected;
            prepared.parse_invocation = Prepared.selected;
            prepared.select_workflow = Prepared.selected;
            prepared.prepare_workflow = Prepared.ready;
            const outcome = @import("../../../src/application/workflow_engine_orchestrator.zig").run(.{ .context = bindings.context, .vtable = &prepared });
            try std.testing.expectEqual(.failed, outcome.executionStatus().?);
            try std.testing.expectEqual(@as(usize, 3), wire.calls);
            // Production activation, capture, retry attribution and closure use real
            // registered files even when the provider body is rejected.
            const log_runtime = &runtime.logging.?;
            const log_artifacts = @import("../../../src/domain/workflow_artifact_registry.zig");
            const log_binding = @import("../../../src/domain/feature_log_binding.zig");
            const log_paths = log_artifacts.bindFeatureLogSinkAdapter(log_artifacts.registry(log_runtime.artifact_owner.?), log_binding.binding(log_runtime.binding_owner.?)).?;
            const prompt_path = try std.fmt.allocPrint(a, "{s}/{s}/0001.log", .{ log_paths.specs_root_path, log_paths.prompt_binding_path });
            const prompt_bytes = try project.dir.readFileAlloc(io, prompt_path, a, .limited(8 * 1024 * 1024));
            try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, prompt_bytes, "inference-request-provider_body-utf8-00000000000000000000"));
            try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, prompt_bytes, "inference-response-provider_body-utf8-00000000000000000000"));
            try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, prompt_bytes, wire.inference_body));
            try std.testing.expect(std.mem.indexOf(u8, prompt_bytes, "segment_trailer|") != null);
            try std.testing.expect(std.mem.indexOf(u8, prompt_bytes, "isolated-credential") == null);
            const event_path = try std.fmt.allocPrint(a, "{s}/{s}/0001.log", .{ log_paths.specs_root_path, log_paths.event_binding_path });
            const event_bytes = try project.dir.readFileAlloc(io, event_path, a, .limited(8 * 1024 * 1024));
            try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, event_bytes, "|run.started|"));
            try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, event_bytes, "|model.requested|"));
            try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, event_bytes, "|model.completed|"));
            try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, event_bytes, if (mode == 2) "|model.schema_failed|" else "|model.protocol_failed|"));
            try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, event_bytes, "|retry.exhausted|"));
            try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, event_bytes, "|run.failed|"));
            try std.testing.expect(std.mem.indexOf(u8, event_bytes, "|publication.prepared|") == null);
            try std.testing.expect(std.mem.indexOf(u8, event_bytes, "|run.completed|") == null);
            try std.testing.expect(std.mem.indexOf(u8, event_bytes, "segment_trailer|") != null);
            try std.testing.expectError(error.FileNotFound, project.dir.access(io, paths.get(.specification).project_relative, .{}));
            try std.testing.expectError(error.FileNotFound, project.dir.access(io, paths.get(.workflow_state).project_relative, .{}));
            try std.testing.expectEqualStrings(form_bytes, try project.dir.readFileAlloc(io, form_path.project_relative, a, .limited(16384)));
            try std.testing.expectEqualStrings(state_bytes, try project.dir.readFileAlloc(io, paths.get(.clarification_state).project_relative, a, .limited(16384)));
            try std.testing.expect(log_runtime.finalized and runtime.boot.ready.logs.lifecycle.active == null);
            try std.testing.expectEqual(@as(u64, 3), outcome.execution_rejected.retry_limit.completed_executions);
            try std.testing.expectEqual(@as(u32, 2), outcome.execution_rejected.retry_limit.limit.value);
            report.terminal_rejection = c.TerminalRejection.fromNative(outcome.execution_rejected);
            const runner = &invocation.pipeline_runner.?;
            // Retire current transport views through the common delta boundary before reporting.
            const pipeline = @import("../../../src/domain/pipeline.zig");
            const retired = [_]pipeline.DataKey{
                @import("../../../src/application/model_request_workflow.zig").prepared_schema.key,
            };
            var retirement: pipeline.NodeDelta = .{};
            for (retired) |key| retirement.data_invalidations.insert(key);
            try runner.envelope.apply(.{ .id = "test.retire-request", .kind = .action, .requires = &.{}, .produces = &.{}, .invalidates = &retired, .side_effect = .none }, &retirement, .ok);
            for (retired) |key| try std.testing.expect(runner.envelope.slots[@intFromEnum(key)] == null);
            report.workflow_outcome = outcome.executionStatus();
            try @import("observation.zig").capture(a, runner, &report);
        }
        try std.testing.expectEqual(@as(u128, 2796), report.total_tokens);
        try std.testing.expectEqual(@as(u64, 932), report.last_model_usage.?.total_tokens);
        try std.testing.expect(report.usage_complete);
        if (mode == 0) {
            try std.testing.expectEqualStrings("response_invalid", report.provider_diagnostic.?);
            try std.testing.expectEqual(.missing_final_text, report.provider_content_diagnostic.?);
            try std.testing.expect(report.last_model_output == null);
        }
        try std.testing.expectEqual(@as(usize, 3), report.attempts.len);
        for (report.attempts, 1..) |attempt, ordinal| {
            try std.testing.expectEqual(@as(u32, @intCast(ordinal)), attempt.origin.attempt.value);
            try std.testing.expectEqual(report.attempts[0].origin.request, attempt.origin.request);
        }
        const encoded = try std.json.Stringify.valueAlloc(a, report, .{});
        _ = try @import("../../../src/domain/strict_json.zig").decode(c.Report, a, encoded, .{ .maximum_depth = 64 });
        if (mode == 0) try std.testing.expect(std.mem.indexOf(u8, try @import("report.zig").renderMarkdown(a, report), "missing_final_text") != null);
    }
}

test "reports retain scoped retry history and rejected-content usage after owner release" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const retry = @import("../../../src/domain/workflow_retry.zig");
    const counts = retained: {
        var state = retry.State.init(std.testing.allocator);
        defer state.deinit();
        for (1..4) |ordinal| {
            const permit: retry.Permit = .{ .key = .{ .scope = @splat(1), .target = @splat(@intCast(ordinal)), .family = @splat(2) }, .authorization = @splat(@intCast(ordinal)), .revision = ordinal, .maximum_targets = 3 };
            try state.commit(try state.prepare(.{ .authorized = permit }));
            _ = try state.beginAttempt(.{ .bytes = "merge" }, .{ .value = 1 }, permit);
            try state.commit(try state.prepare(.{ .merged_validated = .{ .permit = permit, .revision_after = ordinal + 1, .result = .resolved } }));
        }
        const epoch = try @import("../../../src/domain/execution_reference.zig").create(std.testing.allocator);
        defer epoch.release();
        const request: @import("../../../src/domain/model_request_identity.zig").ModelRequestId = .{
            .stage_run_epoch_id = .{ .reference = epoch },
            .immutable_unit_owner_id = .{ .reference_global = .{ .reference_state_id = .{ .bytes = "source" }, .unit_slot_id = .{ .bytes = "global" } } },
            .model_operation_id = .{ .workflow_id = .{ .bytes = "spec" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "prepare" } },
            .purpose = .initial_generation,
            .request_ordinal = .{ .value = 1 },
        };
        for (0..3) |_| _ = try state.beginAssignmentAttempt(.{ .bytes = "account" }, .{ .value = 2 }, .{ .request = &request, .record = .{ .value = 1 } });
        break :retained .{ .defects = try state.observe(a, .{ .bytes = "merge" }), .assignments = try state.observeAssignments(a, .{ .bytes = "account" }) };
    };
    try std.testing.expectEqual(@as(usize, 3), counts.defects.len);
    var calls = [_]@import("observation.zig").Call{.{ .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } }, .step = "repair", .raw_response_available = true, .status = 200 }};
    var observed: c.Report = .{
        .started_at_utc = "",
        .status = .workflow_failed,
        .workflow_outcome = .failed,
        .provider_diagnostic = "response_invalid",
        .provider_content_diagnostic = .missing_final_text,
        .last_model_origin = calls[0].origin,
        .last_model_usage = .{ .input_tokens = 884, .output_tokens = 48, .total_tokens = 932 },
        .retry_settings = &.{
            .{ .step = "merge", .limit = 1, .scope = .repair, .operation_executions = 0, .defects = counts.defects },
            .{ .step = "account", .limit = 2, .scope = .model_request, .operation_executions = 0, .defects = &.{}, .assignments = counts.assignments },
        },
    };
    try @import("observation.zig").correlate(a, &calls, &observed);
    var retained: c.Report = .{ .started_at_utc = "", .status = .workflow_failed, .retry_settings = observed.retry_settings };
    try @import("observation.zig").correlate(a, &calls, &retained);
    try std.testing.expectEqual(@as(u64, 932), retained.last_model_usage.?.total_tokens);
    try std.testing.expectEqual(@as(usize, 0), retained.repairs.len);
    try std.testing.expect(retained.last_model_output == null);
    const encoded = try std.json.Stringify.valueAlloc(a, retained, .{});
    const decoded = try @import("../../../src/domain/strict_json.zig").decode(c.Report, a, encoded, .{ .maximum_depth = 64 });
    const settings = try std.json.Stringify.valueAlloc(a, decoded.retry_settings, .{});
    for ([_][]const u8{ encoded, try @import("report.zig").renderMarkdown(a, decoded) }) |output| {
        try std.testing.expect(std.mem.indexOf(u8, output, settings) != null);
        try std.testing.expect(std.mem.indexOf(u8, output, "missing_final_text") != null);
    }
    for (decoded.retry_settings[0].defects) |defect| try std.testing.expectEqual(@as(u64, 1), defect.completed_executions);
    try std.testing.expectEqual(@as(usize, 1), decoded.retry_settings[1].assignments[0].request.value);
    try std.testing.expectEqual(@as(u64, 3), decoded.retry_settings[1].assignments[0].completed_executions);
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
    const metadata = try store.redact(std.testing.allocator, body);
    defer std.testing.allocator.free(metadata);
    try std.testing.expectEqualStrings(saved, metadata);
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

test "step events keep the newer exchange usage separate from an older rejected candidate" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const obs = @import("observation.zig");
    const Origin = @import("../../../src/domain/model_candidate_origin.zig").Origin;
    const original: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const repair: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const Usage = @import("../../../src/domain/llm_provider_operation.zig").ProviderUsage;
    var calls = [_]obs.Call{
        .{ .origin = original, .step = "extract", .usage = Usage.init(100, 20, 120).?, .output_available = true },
        .{ .origin = repair, .step = "repair", .output_available = true },
    };
    var report: c.Report = .{
        .started_at_utc = "",
        .status = .workflow_failed,
        .last_model_origin = repair,
        .last_model_usage = Usage.init(300, 40, 340).?,
        .candidate_error = .{ .source_selections = .{
            .observed = &.{},
            .scope = .{ .state_id = .{ .bytes = "state" }, .chunk_id = .{ .bytes = "chunk" } },
            .revision = 1,
            .claim_index = 0,
            .origin = original,
            .issue = .{ .reason = .unknown_selection, .index = 0, .rejected = .{ .first = .{ .ordinal = 99 }, .last = .{ .ordinal = 99 } }, .available = .{ .first = .{ .ordinal = 1 }, .last = .{ .ordinal = 7 } } },
        } },
    };
    try obs.correlate(a, &calls, &report);
    try std.testing.expectEqual(@as(usize, 2), report.last_model_call.?);
    try std.testing.expectEqual(@as(usize, 1), report.candidate_model_call.?);
    try std.testing.expectEqualStrings("repair", report.last_model_step.?);
    try std.testing.expectEqualStrings("extract", report.candidate_model_step.?);
    try std.testing.expectEqual(@as(u64, 340), report.last_model_usage.?.total_tokens);
    const event = try @import("trace.zig").Trace.stepEvent(a, 91, .{ .bytes = "validate-selections" }, .{ .outcome = .invalid }, report);
    const tree = try std.json.parseFromSlice(std.json.Value, a, event, .{});
    const exchange = tree.value.object.get("exchange").?.object;
    const candidate = tree.value.object.get("candidate_source").?.object;
    try std.testing.expectEqual(@as(i64, 2), exchange.get("call").?.integer);
    try std.testing.expectEqual(@as(i64, 1), candidate.get("call").?.integer);
    try std.testing.expectEqual(@as(i64, 340), exchange.get("usage").?.object.get("total_tokens").?.integer);
    try std.testing.expect(!tree.value.object.contains("model_call"));
    try std.testing.expect(!tree.value.object.contains("usage"));
    // A later deterministic failure keeps its own step after request retirement.
    report.last_model_usage = null;
    report.last_model_origin = null;
    report.terminal_step = "validate-accounting";
    report.terminal_rejection = .{ .kind = .operation_failed };
    try obs.correlate(a, &calls, &report);
    try std.testing.expectEqual(@as(u64, 340), report.last_model_usage.?.total_tokens);
    for ([_][]const u8{ try @import("report.zig").renderMarkdown(a, report), try @import("report.zig").terminal(a, report, "runs", "sample") }) |rendered| {
        try std.testing.expect(std.mem.indexOf(u8, rendered, "validate-accounting") != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, "operation_failed") != null);
    }
    // Correlation cannot fill missing evidence by assuming the latest call.
    calls[0].output_available = false;
    try std.testing.expectError(error.MissingRequestEvidence, obs.correlate(a, &calls, &report));
    calls[0].output_available = true;
    report.candidate_error.?.source_selections.origin.?.attempt.value = 9;
    try std.testing.expectError(error.MissingRequestEvidence, obs.correlate(a, &calls, &report));
    report.candidate_error.?.source_selections.origin = null;
    try std.testing.expectError(error.MissingRequestEvidence, obs.correlate(a, &calls, &report));
    report.candidate_error = null;
    calls[0].origin = repair;
    try std.testing.expectError(error.MissingRequestEvidence, obs.correlate(a, &calls, &report));
}

test "reports preserve native extraction reconciliation specification and complete review failures after source release" {
    const reference_fixture = @import("../../../src/reference_reconciliation_test.zig");
    const references = @import("../../../src/test_fixtures/reference_reconciliation.zig");
    const Diagnostic = @import("../../../src/domain/candidate_validation_diagnostic.zig").Diagnostic;
    const Origin = @import("../../../src/domain/model_candidate_origin.zig").Origin;
    const origin: Origin = .{ .request = .{ .value = 3 }, .attempt = .{ .value = 2 } };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var retained: [4]Diagnostic = undefined;
    {
        var source: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer source.deinit();
        const scratch = source.allocator();
        const input = try reference_fixture.prepare(scratch, &.{ "Confirm a reservation.\n", "Renew a loan.\n" });
        defer input.deinit();
        const global = try references.summaries(scratch, try references.initialize(scratch, input.inputs, input.extracted, 2), input.context());
        const proposal = try references.global(scratch, global);
        var bad = proposal;
        bad.claim_dispositions = proposal.claim_dispositions[1..];
        const rejected = (try references.validate_dispositions.execute(scratch, .{ .input = global, .proposal = .{ .global = bad }, .source = .{ .origin = origin } })).invalid;
        retained[0] = try (Diagnostic{ .reconciliation = rejected }).copy(a);
        const accounted = (try references.finish(scratch, global, proposal, input.context())).valid;
        const context: @import("../../../src/domain/specification_provenance.zig").Context = .{ .inputs = input.inputs, .references = accounted, .registry = input.context().registry, .current = input.context().current };
        const review_inputs = try @import("../../../src/domain/specification_authority.zig").project(scratch, input.inputs.corpus.feature_id, accounted, null, null);
        const missing = (try @import("../../../src/domain/specification_support.zig").Source.collect(scratch, review_inputs, context, "{\"entries\":[]}", origin)).rejected;
        try std.testing.expect(missing.rejection.diagnostics.len > 1);
        retained[3] = try (Diagnostic{ .support = missing.rejection }).copy(a);
        var current = try @import("../../../src/domain/specification_session.zig").initialize(.{ .bytes = "chosen" }, context);
        current.completed = 1;
        const action = @import("../../../src/actions/specification/validate_specification_unit.zig").Action{ .validator = @import("../../../src/test_fixtures/reference_text.zig").validator };
        const spec = (try action.execute(scratch, current, context, .{ .origins = .{ .initial = origin }, .response = .{ .content = .{ .primary_user_story = .{ .value = .{ .normalized = .{ .segments = &.{.{ .literal = .{ .value = "A reservation is confirmed." } }} } }, .provenance = .{ .claim_ids = &.{.{ .ordinal = 999 }}, .clarification_response_ids = &.{} } } } } })).invalid;
        retained[1] = try (Diagnostic{ .specification = spec }).copy(a);
        const extraction_action = @import("../../../src/actions/reference/validate_reference_extraction_text.zig").Action{ .validator = @import("../../../src/test_fixtures/reference_text.zig").validator };
        const lexical = (try extraction_action.execute(scratch, context.registry, context.current, input.inputs, .{ .entries = &.{.{ .scope = .{ .state_id = input.inputs.corpus.state_id, .chunk_id = input.inputs.chunks.entries[0].id }, .origin = origin, .token_classifications = &.{}, .outcome = .{ .no_feature_claim = .{ .nodes = &.{.{ .literal = .{ .value = "unbound/reference.md" } }} } } }} })).invalid;
        retained[2] = try (Diagnostic{ .extraction_text = lexical }).copy(a);
    }
    for (retained) |diagnostic| {
        const report: c.Report = .{ .started_at_utc = "", .status = .workflow_failed, .workflow_outcome = .invalid, .terminal_step = "native-validation", .candidate_error = diagnostic };
        const decoded = try @import("../contracts.zig").decode(c.Report, a, try std.json.Stringify.valueAlloc(a, report, .{}));
        try std.testing.expectEqualDeep(report, decoded);
        try std.testing.expectEqualDeep(origin, decoded.candidate_error.?.origin().?);
        const bytes = try std.json.Stringify.valueAlloc(a, diagnostic, .{});
        for ([_][]const u8{ try @import("report.zig").renderMarkdown(a, decoded), try @import("report.zig").terminal(a, decoded, "runs", "case") }) |output| {
            try std.testing.expect(std.mem.indexOf(u8, output, bytes) != null);
            try std.testing.expect(std.mem.indexOf(u8, output, "native-validation") != null);
        }
    }
}

test "events and reports preserve native repair changes and text spans after release" {
    const reconciliation_fixture = @import("../../../src/reference_reconciliation_test.zig");
    const reference = @import("../../../src/test_fixtures/reference_reconciliation.zig");
    const repair = @import("../../../src/domain/reference_reconciliation_repair.zig");
    const Diagnostic = @import("../../../src/domain/candidate_validation_diagnostic.zig").Diagnostic;
    const Merge = @import("../../../src/domain/atomic_repair.zig").Merge;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var retained: Diagnostic = undefined;
    var merged: [2]Merge = undefined;
    {
        var source: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer source.deinit();
        const scratch = source.allocator();
        const inputs = try reconciliation_fixture.prepare(scratch, &.{ "Display a greeting.\n", "Confirm a reservation.\n" });
        defer inputs.deinit();
        const current = try reference.summaries(scratch, try reference.initialize(scratch, inputs.inputs, inputs.extracted, 2), inputs.context());
        var proposal = try reference.global(scratch, current);
        const signals = try scratch.dupe(reference.r.SignalProposal, proposal.signals);
        const good = signals[0].content;
        signals[0].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Display \\\"a result\\\"." } }} } } };
        proposal.signals = signals;
        const candidate: reference.r.Parsed = .{ .input = current, .proposal = .{ .global = proposal } };
        const rejected = (try reference.validate_signals.execute(scratch, (try reference.validate_dispositions.execute(scratch, candidate)).valid, inputs.context())).invalid;
        const authorization = (try repair.authorize(scratch, candidate, inputs.context(), rejected)).model;
        for (0..2) |index| {
            const value = try repair.merge(scratch, candidate, inputs.context(), authorization, if (index == 0) authorization.operation.replace else .{ .content = good }, .{ .request = .{ .value = 5 }, .attempt = .{ .value = 2 } });
            merged[index] = try value.source.last_repair.?.copy(a);
            const validation = try reference.validate_signals.execute(scratch, (try reference.validate_dispositions.execute(scratch, value)).valid, inputs.context());
            if (index == 0) retained = try (Diagnostic{ .reconciliation = validation.invalid }).copy(a) else try std.testing.expect(validation == .valid);
        }
    }
    try std.testing.expectEqualStrings("\\", retained.reconciliation.issue.expected.text_issue.path_match.?.lexeme);
    for (merged, 0..) |merge, index| {
        const report: c.Report = .{ .started_at_utc = "", .status = .workflow_failed, .workflow_outcome = if (index == 0) .invalid else .ok, .terminal_step = "validate-signals", .candidate_error = if (index == 0) retained else null, .repairs = &.{merge} };
        const decoded = try @import("../contracts.zig").decode(c.Report, a, try std.json.Stringify.valueAlloc(a, report, .{}));
        try std.testing.expectEqualDeep(report, decoded);
        try std.testing.expectEqual(index == 1, decoded.repairs[0].changed);
        try std.testing.expectEqual(@as(u64, 1), merge.revision_before);
        try std.testing.expectEqual(@as(u64, 2), merge.revision_after);
        const bytes = try std.json.Stringify.valueAlloc(a, report.repairs, .{});
        for ([_][]const u8{ try @import("report.zig").renderMarkdown(a, decoded), try @import("report.zig").terminal(a, decoded, "runs", "case") }) |output| try std.testing.expect(std.mem.indexOf(u8, output, bytes) != null);
        const event = try @import("trace.zig").Trace.stepEvent(a, index + 1, .{ .bytes = "validate-signals" }, .{ .outcome = report.workflow_outcome.? }, decoded);
        const tree = try std.json.parseFromSlice(std.json.Value, a, event, .{});
        try std.testing.expectEqual(index == 1, tree.value.object.get("repairs").?.array.items[0].object.get("changed").?.bool);
    }
}

test "persisted extraction rejection retains its terminal diagnostic in report readback" {
    const native: @import("../../../src/domain/workflow_execution.zig").Rejection = .{ .operation_failed = error.REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE };
    const value = c.TerminalRejection.fromNative(native);
    const bytes = try std.json.Stringify.valueAlloc(std.testing.allocator, value, .{});
    defer std.testing.allocator.free(bytes);
    var decoded = try std.json.parseFromSlice(c.TerminalRejection, std.testing.allocator, bytes, .{});
    defer decoded.deinit();
    try std.testing.expectEqual(.operation_failed, decoded.value.kind);
    try std.testing.expectEqualStrings("REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE", decoded.value.detail.?);
}
