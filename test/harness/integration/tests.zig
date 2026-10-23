const std = @import("std");
const c = @import("../e2e/contracts.zig");
const fixture = @import("../e2e/fixture.zig");
const oracle = @import("../e2e/oracle.zig");
const run_directory = @import("../e2e/run_directory.zig");
const artifacts = @import("../../../src/domain/workflow_artifact_registry.zig");
const expected = [_]c.Artifact{ .specification, .reference_context, .clarification_state, .workflow_state };
const selected: c.Case = .{
    .schema = "spec-e2e-case/v3",
    .id = "one-reference",
    .workflow_id = "spec-generation",
    .expected_outcome = .publication,
    .feature = "chosen",
    .reference = "first",
    .config = "config.json",
    .evaluation_case = "evaluation.case.json",
    .directories = &.{"empty"},
    .files = &.{.{ .source = "source.md", .destination = "references/first/source.md" }},
    .expected_artifacts = &expected,
};

test {
    _ = @import("../e2e/acceptance_test.zig");
}

test "E2E command selects one live case and rejects mock modes and extra cases" {
    const parse = @import("../e2e/cli.zig").parse;
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
        .{ "\"spec-e2e-case/v3\"", "\"spec-e2e-case/v2\"" },
        // A retired judge configuration is not accepted case content.
        .{ "\"id\":", "\"evaluation_config\":\"evaluation.json\",\"id\":" },
        .{ "\"expected_outcome\":\"publication\",", "" },
        .{ "\"expected_outcome\":\"publication\"", "\"expected_outcome\":\"unknown\"" },
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
        \\{"schema":"evaluation-case/v2","id":"one-reference","sources":[{"id":"source","path":"source.md"}],"rubric":"rubric.json","grading_qualification":{"panel":"panel.json","review":"review.json","qualification":"qualification.json"}}
    });
    try repository.writeFile(io, .{ .sub_path = "rubric.json", .data = @embedFile("../../e2e/wf-001-hello-world/node-vitest/rubric/spec.json") });
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

test "explicit loan renewal case binds generation and rubric to the same source bytes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const choice = try c.parse(a, @embedFile("../../e2e/wf-002-loan-renewal/workflow.case.json"));
    const captured = try fixture.capture(std.testing.io, a, .cwd(), choice);
    try fixture.validateEvaluationSources(a, captured, "references", choice.reference);
    try std.testing.expectEqualStrings(choice.id, captured.evaluation.case.id);
    for (captured.evaluation.case.sources, captured.evaluation.sources) |source, document| {
        const file = for (captured.files) |file| {
            if (std.mem.eql(u8, file.mapping.source, source.path)) break file;
        } else return error.MissingEvaluationSource;
        try std.testing.expectEqualStrings(file.bytes, document.text);
        try std.testing.expect(captured.evaluation.rubric.criteria.len > 0);
    }
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
        // Draft admission cannot bypass the final review/publication contracts.
        .{ "  generate:\n    call: generate-specification\n    on:\n      ok: review", "  generate:\n    call: generate-specification\n    on:\n      ok: publish" },
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
                    if (fault == .missing_schema and !@import("../../../src/domain/workflow_model.zig").assignsRequest(step.produces, step.replaces)) continue;
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
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const choice = try c.parse(a, @embedFile("../../e2e/wf-001-hello-world/node-vitest/workflow.case.json"));
    const captured = try fixture.capture(io, a, .cwd(), choice);
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try fixture.materialize(io, project.dir, captured);
    const target = try configured(a, captured);
    const variable = @import("../../../src/adapters/system/provider_api_key_source.zig").variable(target.family);
    for ([_]?[]const u8{ null, "", "invalid key", "isolated-credential" }) |raw| {
        inline for (.{ false, true }) |from_environment| {
            var environment: std.process.Environ.Map = .init(std.testing.allocator);
            defer environment.deinit();
            if (from_environment) {
                if (raw) |bytes| try environment.put(variable, bytes);
            } else {
                // A direct missing/invalid credential cannot use an ambient key.
                try environment.put(variable, "ambient-credential");
            }
            var runtime: Runtime = undefined;
            runtime.init(io, std.testing.allocator, project.dir, .{});
            defer runtime.deinit();
            try std.testing.expect(runtime.boot == .ready);
            var invocation = runtime.invocation(&.{ choice.workflow_id, "--feature", choice.feature, "--reference", choice.reference }, if (from_environment)
                .{ .environment = &environment }
            else
                .{ .snapshots = try familySnapshots(target.family, raw) });
            defer invocation.deinit();
            if (from_environment) try std.testing.expect(runtime.provider_runtime.authorization.materials.get(target.family).* == .unavailable);
            const bindings = invocation.bindings();
            try std.testing.expectEqual(.ok, bindings.invokeValidateOperationRegistry());
            try std.testing.expectEqual(.ok, bindings.invokeParseInvocation());
            try std.testing.expectEqual(.ok, bindings.invokeSelectWorkflow());
            try std.testing.expectEqual(.ok, bindings.invokePrepareWorkflow());
            try std.testing.expect(runtime.provider_runtime.provider != null);
            const material = runtime.provider_runtime.authorization.materials.get(target.family).*;
            const valid = if (raw) |bytes| std.mem.eql(u8, bytes, "isolated-credential") else false;
            try std.testing.expectEqual(valid, material == .ready);
            if (valid) {
                try environment.put(variable, "changed-credential");
                try std.testing.expectEqualStrings(raw.?, material.ready.bytes);
            }
            // Preparation exercises production binding without invoking HTTP.
        }
    }
}

test "production E2E binding honors configured models and cannot succeed without real credentials" {
    const io = std.testing.io;
    var catalogue_arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer catalogue_arena.deinit();
    const shipped = try fixture.capture(io, catalogue_arena.allocator(), .cwd(), try c.parse(catalogue_arena.allocator(), @embedFile("../../e2e/wf-001-hello-world/node-vitest/workflow.case.json")));
    const catalogue_bytes = for (shipped.files) |file| {
        if (std.mem.endsWith(u8, file.mapping.destination, ".sddproviders.json")) break file.bytes;
    } else return error.MissingProviderCatalogue;
    const catalogue = try std.json.parseFromSliceLeaky(std.json.Value, catalogue_arena.allocator(), catalogue_bytes, .{});
    // Every entry the shipped catalogue offers is honored as configured, and
    // none can succeed without its family's real credential.
    var entries: usize = 0;
    for (catalogue.object.get("providers").?.array.items) |provider_entry| for (provider_entry.object.get("models").?.array.items) |model_entry| {
        entries += 1;
        const provider = provider_entry.object.get("provider").?.string;
        const model = model_entry.object.get("model").?.string;
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const choice = try c.parse(a, @embedFile("../../e2e/wf-001-hello-world/node-vitest/workflow.case.json"));
        const captured = try fixture.capture(io, a, .cwd(), choice);
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try fixture.materialize(io, project.dir, captured);
        var model_config = try std.json.parseFromSliceLeaky(std.json.Value, a, captured.config, .{});
        for (model_config.object.get("models").?.object.get("slots").?.object.values()) |*slot| {
            try slot.object.put(a, "provider", .{ .string = provider });
            try slot.object.put(a, "model", .{ .string = model });
            // Omitted effort is valid for every registered model.
            _ = slot.object.swapRemove("reasoningEffort");
        }
        try project.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = try std.json.Stringify.valueAlloc(a, model_config, .{}) });
        var report: c.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "2026-09-11T00:00:00Z", .status = .input_invalid };
        var evidence_run = std.testing.tmpDir(.{});
        defer evidence_run.cleanup();
        const store: @import("../evidence.zig").Store = .{ .io = io, .allocator = a, .run = evidence_run.dir, .secrets = &.{} };
        const output = try @import("../e2e/invoke.zig").run(io, a, project.dir, choice, captured, .initFill(null), store, &report, .{ .purpose = .whole_workflow });
        try std.testing.expect(output == null);
        try std.testing.expectEqual(.live, report.origin);
        try std.testing.expectEqual(.workflow_failed, report.status);
        try std.testing.expectEqual(.failed, report.workflow_outcome.?);
        try std.testing.expectEqualStrings("failed", report.diagnostic.?);
        try std.testing.expectEqualStrings("authentication_failed", report.provider_diagnostic.?);
        try std.testing.expectEqual(@as(usize, 0), report.model_calls);
        try std.testing.expectEqualStrings(model, report.models[0].model);
        try std.testing.expectEqualStrings(provider, report.models[0].provider);
        const events = try @import("../files.zig").read(io, a, evidence_run.dir, report.events_file.?);
        try std.testing.expect(std.mem.indexOf(u8, events, "authentication_failed") != null);
        try std.testing.expect(report.last_model_call == null);
        try std.testing.expect(report.evaluation_inputs == null);
        try std.testing.expectError(error.FileNotFound, project.dir.access(io, "specs/hello-world/spec.md", .{}));
        try fixture.verifySources(io, a, .cwd(), captured);
    };
    try std.testing.expect(entries != 0);
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

test "publication handoff captures poor output for adjudication without changing workflow authority" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const choice = try c.parse(a, @embedFile("../../e2e/wf-001-hello-world/node-vitest/workflow.case.json"));
    const captured = try fixture.capture(io, a, .cwd(), choice);
    const evaluation = @import("../e2e/evaluation.zig");
    var report: c.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "2026-09-11T00:00:00Z", .execution_id = "run-123", .expected_outcome = .publication, .evaluation_case_id = captured.evaluation.case.id, .status = .generated, .workflow_outcome = .ok, .publication_check = .passed, .specification = "specs/hello-world/spec.md", .models = &.{.{ .slot = "spec_generation", .provider = "aws-bedrock", .model = "openai.gpt-oss-20b-1:0" }} };
    const inputs = try evaluation.inputs(a, report, captured.evaluation, "Readable but poor output.", "run-123");
    report.evaluation_inputs = inputs;
    try std.testing.expectEqualStrings("Readable but poor output.", inputs.specification);
    try std.testing.expectEqualStrings("run-123", inputs.generation.execution_id.?);
    try std.testing.expectEqual(.live_generation, inputs.generation.origin);
    for ([_]@import("../../../src/domain/workflow.zig").OutcomeTag{ .failed, .invalid, .blocked, .cancelled, .needs_user }) |outcome| {
        var failed = report;
        failed.workflow_outcome = outcome;
        try std.testing.expectError(error.GenerationNotCompleted, evaluation.inputs(a, failed, captured.evaluation, "stale output", "run-124"));
    }
    // The capture is evidence for a human; it changes no workflow state.
    try std.testing.expectEqual(.generated, report.status);
    try std.testing.expectEqual(.ok, report.workflow_outcome.?);
    try std.testing.expectEqualStrings(captured.evaluation.rubric_bytes, inputs.rubric_bytes);
    const terminal = try @import("../e2e/report.zig").terminal(a, report, "runs", "sample");
    try std.testing.expect(std.mem.indexOf(u8, terminal, "Specification publication: passed") != null);
    try std.testing.expect(std.mem.indexOf(u8, terminal, "score") == null);
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
    const output = try @import("../e2e/report.zig").Output.reserve(io, dir.dir);
    defer output.close(io);
    const id = @import("../../../src/domain/clarification_inputs.zig").Id.parse("S02").?;
    const report: c.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "2026-09-16T00:00:00Z", .expected_outcome = .clarification, .status = .awaiting_clarification, .workflow_outcome = .needs_user, .publication_check = .passed, .specification = "outputs/chosen/spec.md", .admission_audit = .{ .sources = &.{}, .checks = &.{}, .complete = true }, .admission_escape = .{ .status = .measured }, .clarifications = &.{.{ .id = id, .path = try @import("../../../src/domain/workflow_output.zig").path(a, try resolve(a), .{ .form = id }) }} };
    try output.save(io, a, report);
    const bytes = try @import("../files.zig").read(io, a, dir.dir, "report.json");
    const retained = try @import("../contracts.zig").decode(c.Report, a, bytes);
    try std.testing.expectEqualDeep(report.clarifications, retained.clarifications);
    try std.testing.expectEqual(.passed, retained.publication_check);
    try std.testing.expect(retained.diagnostic == null and retained.evaluation_inputs == null and retained.specification != null);
    try std.testing.expect(try @import("../e2e/acceptance.zig").commandSucceeded(a, retained));
    try std.testing.expectEqual(.passed, retained.acceptance);
    var unexpected = retained;
    unexpected.expected_outcome = .publication;
    try std.testing.expect(!try @import("../e2e/acceptance.zig").commandSucceeded(a, unexpected));
    const markdown = try @import("../files.zig").read(io, a, dir.dir, "report.md");
    const terminal = try @import("../e2e/report.zig").terminal(a, report, "runs", "example");
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
    const output = try @import("../e2e/report.zig").Output.reserve(io, dir.dir);
    defer output.close(io);
    const report: c.Report = .{
        .schema = .@"spec-e2e-report/v9",
        .started_at_utc = "2026-09-11T00:00:00Z",
        .execution_id = "run-failed",
        .case_source = "chosen.case.json",
        .status = .workflow_failed,
        .workflow_outcome = .failed,
        .diagnostic = "ENGINE_REJECTION",
        .retry_error = .{ .operation_instance_id = .{ .bytes = "request-account" }, .retry_limit = 4, .completed_executions = 5, .reason = .retry_limit, .defect = null },
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
    try std.testing.expect(retained.evaluation_inputs == null);
    const view = try @import("../files.zig").read(io, a, dir.dir, "report.md");
    try std.testing.expect(std.mem.indexOf(u8, view, "provider stopped generation at its output limit") != null);
    try std.testing.expect(std.mem.indexOf(u8, view, "100 input + 512 output = 612 tokens") != null);
    try std.testing.expect(std.mem.indexOf(u8, view, "No model grades this run.") != null);
    const terminal = try @import("../e2e/report.zig").terminal(a, report, "runs", "example");
    for ([_][]const u8{ view, terminal }) |rendered|
        try std.testing.expect(std.mem.indexOf(u8, rendered, "JSON error: SyntaxError at line 2, column 8 (byte offset 9)") != null);
    const diagnostic = try std.json.Stringify.valueAlloc(a, report.candidate_error.?, .{});
    for ([_][]const u8{ view, terminal }) |rendered| try std.testing.expect(std.mem.indexOf(u8, rendered, diagnostic) != null);
    const schema_diagnostic = try std.json.Stringify.valueAlloc(a, report.schema_error.?, .{});
    for ([_][]const u8{ view, terminal }) |rendered| try std.testing.expect(std.mem.indexOf(u8, rendered, schema_diagnostic) != null);
    const retry_diagnostic = try std.json.Stringify.valueAlloc(a, report.retry_error.?, .{});
    for ([_][]const u8{ view, terminal }) |rendered| try std.testing.expect(std.mem.indexOf(u8, rendered, retry_diagnostic) != null);
    try std.testing.expect(std.mem.indexOf(u8, terminal, "runs/example/report.json") != null);
    try std.testing.expectError(error.PathAlreadyExists, @import("../e2e/report.zig").Output.reserve(io, dir.dir));
}

test "completed E2E reports retain the exact captured adjudication inputs" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const choice = try c.parse(a, @embedFile("../../e2e/wf-001-hello-world/node-vitest/workflow.case.json"));
    var captured = try fixture.capture(io, a, .cwd(), choice);
    captured.evaluation.rubric.pass_threshold_percent = 75.5;
    captured.evaluation.rubric_bytes = try std.json.Stringify.valueAlloc(a, captured.evaluation.rubric, .{});
    var report: c.Report = .{
        .schema = .@"spec-e2e-report/v9",
        .started_at_utc = "2026-10-11T00:00:00Z",
        .execution_id = "MOCK-published-run",
        .expected_outcome = .publication,
        .evaluation_case_id = captured.evaluation.case.id,
        .status = .generated,
        .workflow_outcome = .ok,
        .publication_check = .passed,
        .specification = "MOCK-feature/spec.md",
        .models = &.{.{ .slot = "MOCK-slot", .provider = "aws-bedrock", .model = "openai.gpt-oss-20b-1:0" }},
    };
    report.evaluation_inputs = try @import("../e2e/evaluation.zig").inputs(a, report, captured.evaluation, "MOCK published specification", report.execution_id.?);
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const output = try @import("../e2e/report.zig").Output.reserve(io, dir.dir);
    defer output.close(io);
    // The saver must release all of its own JSON and Markdown allocations.
    try output.save(io, std.testing.allocator, report);
    const retained = try @import("../contracts.zig").decode(c.Report, a, try @import("../files.zig").read(io, a, dir.dir, "report.json"));
    try std.testing.expectEqual(.generated, retained.status);
    try std.testing.expectEqualDeep(report.evaluation_inputs, retained.evaluation_inputs);
    try std.testing.expectEqual(@as(f64, 75.5), retained.evaluation_inputs.?.rubric.pass_threshold_percent.?);
    const markdown = try @import("../files.zig").read(io, a, dir.dir, "report.md");
    try std.testing.expect(std.mem.indexOf(u8, markdown, "No model grades this run.") != null);
    try std.testing.expect(std.mem.indexOf(u8, markdown, "unresolved (") != null);
}

test "E2E report finalization preserves workflow outcomes and exposes write and sync failures" {
    const io = std.testing.io;
    const Fault = enum { none, json_write, markdown_write, sync, stderr_write };
    for ([_]c.Status{ .workflow_failed, .generated, .awaiting_clarification }) |status| {
        for (std.meta.tags(Fault)) |fault| {
            var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
            defer arena.deinit();
            const a = arena.allocator();
            var dir = std.testing.tmpDir(.{});
            defer dir.cleanup();
            var output = try @import("../e2e/report.zig").Output.reserve(io, dir.dir);
            defer output.close(io);
            switch (fault) {
                .json_write, .stderr_write => {
                    output.json.close(io);
                    output.json = try dir.dir.openFile(io, "report.json", .{ .mode = .read_only });
                },
                .markdown_write => {
                    output.markdown.close(io);
                    output.markdown = try dir.dir.openFile(io, "report.md", .{ .mode = .read_only });
                },
                .none, .sync => {},
            }
            const stdout = try dir.dir.createFile(io, "MOCK-stdout.txt", .{});
            defer stdout.close(io);
            var stderr = try dir.dir.createFile(io, "MOCK-stderr.txt", .{});
            defer stderr.close(io);
            if (fault == .stderr_write) {
                stderr.close(io);
                stderr = try dir.dir.openFile(io, "MOCK-stderr.txt", .{ .mode = .read_only });
            }
            const report: c.Report = if (status == .awaiting_clarification)
                try @import("../e2e/acceptance_test.zig").pause(a)
            else if (status == .generated)
                try @import("../e2e/acceptance_test.zig").completed(a)
            else
                .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "2026-10-11T00:00:00Z", .expected_outcome = .publication, .status = .workflow_failed, .workflow_outcome = .failed, .diagnostic = "WorkflowTokenBudgetExceeded", .terminal_rejection = .{ .kind = .token_budget, .detail = "WorkflowTokenBudgetExceeded" } };
            // Override only the standard file-sync operation; all other I/O
            // retains its real test implementation and original context.
            var vtable = io.vtable.*;
            if (fault == .sync) vtable.fileSync = struct {
                fn fail(_: ?*anyopaque, _: std.Io.File) std.Io.File.SyncError!void {
                    return error.NoSpaceLeft;
                }
            }.fail;
            const selected_io: std.Io = .{ .userdata = io.userdata, .vtable = &vtable };
            const result = @import("../e2e/cli.zig").finish(selected_io, a, output, report, "MOCK-runs", "MOCK-run", stdout, stderr);
            const succeeded = if (fault == .stderr_write) blk: {
                try std.testing.expectError(error.NotOpenForWriting, result);
                break :blk false;
            } else try result;
            try std.testing.expectEqual(fault == .none and status == .awaiting_clarification, succeeded);
            const terminal = try @import("../files.zig").read(io, a, dir.dir, "MOCK-stdout.txt");
            try std.testing.expect(std.mem.indexOf(u8, terminal, @tagName(status)) != null);
            if (status == .workflow_failed) {
                try std.testing.expect(std.mem.indexOf(u8, terminal, "WorkflowTokenBudgetExceeded") != null);
                try std.testing.expect(std.mem.indexOf(u8, terminal, "Runner rejection:") != null);
            }
            const failure = try @import("../files.zig").read(io, a, dir.dir, "MOCK-stderr.txt");
            if (fault == .none or fault == .stderr_write) {
                try std.testing.expectEqualStrings("", failure);
            } else {
                try std.testing.expect(std.mem.indexOf(u8, failure, "E2E report finalization failed:") != null);
                try std.testing.expect(std.mem.indexOf(u8, failure, "may be incomplete") != null);
                if (fault == .sync) try std.testing.expect(std.mem.indexOf(u8, failure, "NoSpaceLeft") != null);
            }
            if (fault != .json_write and fault != .stderr_write) {
                const retained = try @import("../contracts.zig").decode(c.Report, a, try @import("../files.zig").read(io, a, dir.dir, "report.json"));
                try std.testing.expectEqual(status, retained.status);
                try std.testing.expectEqualDeep(report.terminal_rejection, retained.terminal_rejection);
                try std.testing.expectEqualDeep(report.diagnostic, retained.diagnostic);
            }
        }
    }
}

test "retired protocol rejection stays associated with its call across later failures" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var snapshot: @import("../e2e/observation.zig").LastModelRejection = .{};
    defer snapshot.deinit(std.testing.allocator);
    const empty: c.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "", .status = .workflow_failed, .workflow_outcome = .failed };
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
    exhausted.retry_error = .{ .operation_instance_id = .{ .bytes = "account" }, .retry_limit = 4, .completed_executions = 5, .reason = .retry_limit, .defect = null };
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

test "composition reports retain every field across retirement rendering and later failures" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var snapshot: @import("../e2e/observation.zig").LastModelRejection = .{};
    defer snapshot.deinit(std.testing.allocator);
    const empty: c.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "", .status = .workflow_failed, .workflow_outcome = .failed };
    var rejected = empty;
    rejected.model_diagnostic = "InvalidModelEnvelope";
    rejected.last_model_call = 13;
    rejected.last_model_origin = .{ .request = .{ .value = 11 }, .attempt = .{ .value = 1 } };
    var path = "/records/0/given".*;
    const fields = [_]@import("../../../src/domain/model_text_composition.zig").FieldIssue{
        .{ .field = .ac_given, .path = &path, .issue = .{ .reason = .reference_only, .first_node = 0, .last_node = 0, .field = .ac_given } },
        .{ .field = .ac_when, .path = "/records/0/when", .issue = .{ .reason = .embedded_insertion_syntax, .first_node = 1, .last_node = 2, .field = .ac_when } },
    };
    rejected.composition_error = .{ .fields = &fields };
    try snapshot.observe(std.testing.allocator, 13, rejected);
    @memset(&path, 'x');
    try snapshot.observe(std.testing.allocator, 13, empty);
    var exhausted = empty;
    exhausted.diagnostic = "RetryLimitExhausted";
    try snapshot.project(a, 13, &exhausted);
    try std.testing.expect(exhausted.json_error == null);
    try std.testing.expectEqual(@as(usize, 2), exhausted.composition_error.?.fields.len);
    try std.testing.expectEqualStrings("/records/0/given", exhausted.composition_error.?.fields[0].path);
    try std.testing.expectEqual(.embedded_insertion_syntax, exhausted.composition_error.?.fields[1].issue.reason);
    try std.testing.expectEqualDeep(rejected.last_model_origin.?, exhausted.last_protocol_rejection.?.origin);
    const bytes = try std.json.Stringify.valueAlloc(a, exhausted, .{});
    const retained = try @import("../../../src/domain/strict_json.zig").decode(c.Report, a, bytes, .{ .maximum_depth = 64 });
    try std.testing.expect(exhausted.composition_error.?.eql(retained.composition_error.?));
    const markdown = try @import("../e2e/report.zig").renderMarkdown(a, exhausted);
    const terminal = try @import("../e2e/report.zig").terminal(a, exhausted, "output", "run");
    for ([_][]const u8{ "ac_given", "ac_when", "reference_only", "embedded_insertion_syntax" }) |needle| {
        try std.testing.expect(std.mem.indexOf(u8, markdown, needle) != null);
        try std.testing.expect(std.mem.indexOf(u8, terminal, needle) != null);
    }
    var progress: @import("../e2e/progress.zig").Progress = .init(std.testing.allocator);
    defer progress.deinit();
    exhausted.last_model_call = 13;
    exhausted.last_model_origin = rejected.last_model_origin;
    try progress.observe(1, "admit", exhausted, null);
    try std.testing.expect(exhausted.composition_error.?.eql(progress.first.?.evidence.protocol.composition_error.?));
    var later = empty;
    try snapshot.project(a, 14, &later);
    try std.testing.expect(later.composition_error == null);
    try std.testing.expectEqual(@as(usize, 13), later.last_protocol_rejection.?.call);
    try std.testing.expectEqual(@as(usize, 2), later.last_protocol_rejection.?.composition_error.?.fields.len);
    snapshot.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("/records/0/given", later.last_protocol_rejection.?.composition_error.?.fields[0].path);
}

test "source selection reports retain the producing call separately from the last call" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const report: c.Report = .{
        .schema = .@"spec-e2e-report/v9",
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
    for ([_][]const u8{ try @import("../e2e/report.zig").renderMarkdown(a, retained), try @import("../e2e/report.zig").terminal(a, retained, "runs", "sample") }) |rendered| {
        try std.testing.expect(std.mem.indexOf(u8, rendered, diagnostic) != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, report.candidate_model_output.?) != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, report.last_model_output.?) != null);
    }
}

test "later budget transport and capture stops retain separate protocol and exchange evidence" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const obs = @import("../e2e/observation.zig");
    const Usage = @import("../../../src/domain/llm_provider_operation.zig").ProviderUsage;
    var calls: [35]obs.Call = undefined;
    for (&calls, 1..) |*call, ordinal| call.* = .{ .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = @intCast(ordinal) } }, .step = "repair", .raw_response_available = true, .output = if (ordinal < 35) .available else .not_projected };
    var retained: obs.LastModelRejection = .{};
    defer retained.deinit(std.testing.allocator);
    try retained.observe(std.testing.allocator, 34, .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "", .status = .workflow_failed, .last_model_origin = calls[33].origin, .model_diagnostic = "SyntaxError", .json_error = .{ .reason = .SyntaxError } });
    for (0..4) |stop| {
        var report: c.Report = .{
            .schema = .@"spec-e2e-report/v9",
            .started_at_utc = "",
            .status = .workflow_failed,
            .workflow_outcome = .failed,
            .total_tokens = 100114,
            .token_accounting = .{ .total_budget = .{ .value = 100000 }, .total_tokens = 0, .usage_unavailable = false },
            .terminal_rejection = .{ .kind = if (stop == 0) .token_budget else .operation_failed },
            .last_model_origin = calls[34].origin,
            .last_model_usage = if (stop == 2) null else Usage.init(2800, 18, 2818).?,
            .evidence_error = if (stop == 3) "EvidenceWriteFailed" else null,
        };
        calls[34].raw_response_available = stop != 2;
        calls[34].output = if (stop == 3) .capture_failed else .not_projected;
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
        for ([_][]const u8{ try std.json.Stringify.valueAlloc(a, report, .{}), try @import("../e2e/report.zig").terminal(a, report, "runs", "example"), try @import("../e2e/report.zig").renderMarkdown(a, report) }) |output| {
            try std.testing.expect(std.mem.indexOf(u8, output, protocol) != null);
            try std.testing.expect(std.mem.indexOf(u8, output, exchange) != null);
        }
    }
}

test "provider cause survives request release without inventing a candidate rejection" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const obs = @import("../e2e/observation.zig");
    var calls = [_]obs.Call{.{
        .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } },
        .step = "extract",
        .raw_response_available = true,
        .status = 403,
        .exception = "AccessDeniedException",
        .request_id = "request-1",
    }};
    var observed: c.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "", .status = .workflow_failed, .provider_diagnostic = "authorization_denied", .provider_origin = calls[0].origin, .last_model_origin = calls[0].origin };
    try obs.correlate(a, &calls, &observed);
    // The next projection has no active request or provider observation slots.
    var released: c.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "", .status = .workflow_failed, .usage_complete = false };
    try obs.correlate(a, &calls, &released);
    try std.testing.expectEqual(@as(usize, 1), released.last_model_call.?);
    try std.testing.expectEqualStrings("authorization_denied", released.provider_diagnostic.?);
    try std.testing.expect(released.model_diagnostic == null and released.last_model_output == null and released.last_model_usage == null);
    try std.testing.expect(released.last_protocol_rejection == null);
    try std.testing.expectEqual(@as(u16, 403), released.exchange_evidence.?.status.?);
    try std.testing.expect(released.exchange_evidence.?.raw_response != null);
    for ([_][]const u8{ try std.json.Stringify.valueAlloc(a, released, .{}), try @import("../e2e/report.zig").terminal(a, released, "runs", "example"), try @import("../e2e/report.zig").renderMarkdown(a, released) }, 0..) |output, index| {
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
        var report: c.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "", .status = .workflow_failed };
        {
            var runtime: @import("../../../src/composition/root.zig").Runtime = undefined;
            runtime.init(io, std.testing.allocator, project.dir, .{});
            defer runtime.deinit();
            try std.testing.expect(runtime.boot == .ready);
            const target = try configured(a, captured);
            var invocation = runtime.invocation(&.{ choice.workflow_id, "--feature", choice.feature, "--reference", choice.reference }, .{
                .snapshots = try familySnapshots(target.family, "isolated-credential"),
            });
            defer invocation.deinit();
            const bindings = invocation.bindings();
            try std.testing.expectEqual(.ok, bindings.invokeValidateOperationRegistry());
            try std.testing.expectEqual(.ok, bindings.invokeParseInvocation());
            try std.testing.expectEqual(.ok, bindings.invokeSelectWorkflow());
            try std.testing.expectEqual(.ok, bindings.invokePrepareWorkflow());
            // Reasoning alone, malformed JSON, then schema-invalid JSON, in the
            // configured provider's own wire shape.
            var wire: ProviderWire = .{ .allocator = a, .model = target.model, .text = switch (mode) {
                0 => null,
                1 => "{",
                else => "{}",
            } };
            runtime.provider_runtime.provider.?.transport = wire.port();
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
            try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, prompt_bytes, wire.last_body));
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
            try @import("../e2e/observation.zig").capture(a, runner, &report);
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
        if (mode == 0) try std.testing.expect(std.mem.indexOf(u8, try @import("../e2e/report.zig").renderMarkdown(a, report), "missing_final_text") != null);
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
            try state.commit(try state.prepare(.{ .merged_validated = .{ .permit = permit, .changed = true, .revision_after = ordinal + 1, .result = .resolved } }));
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
    var calls = [_]@import("../e2e/observation.zig").Call{.{ .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } }, .step = "repair", .raw_response_available = true, .status = 200 }};
    var observed: c.Report = .{
        .schema = .@"spec-e2e-report/v9",
        .started_at_utc = "",
        .status = .workflow_failed,
        .workflow_outcome = .failed,
        .provider_diagnostic = "response_invalid",
        .provider_origin = calls[0].origin,
        .provider_content_diagnostic = .missing_final_text,
        .last_model_origin = calls[0].origin,
        .last_model_usage = .{ .input_tokens = 884, .output_tokens = 48, .total_tokens = 932 },
        .retry_settings = &.{
            .{ .step = "merge", .limit = 1, .scope = .repair, .operation_executions = 0, .defects = counts.defects },
            .{ .step = "account", .limit = 2, .scope = .model_request, .operation_executions = 0, .defects = &.{}, .assignments = counts.assignments },
        },
    };
    try @import("../e2e/observation.zig").correlate(a, &calls, &observed);
    var retained: c.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "", .status = .workflow_failed, .retry_settings = observed.retry_settings };
    try @import("../e2e/observation.zig").correlate(a, &calls, &retained);
    try std.testing.expectEqual(@as(u64, 932), retained.last_model_usage.?.total_tokens);
    try std.testing.expectEqual(@as(usize, 0), retained.repairs.len);
    try std.testing.expect(retained.last_model_output == null);
    const encoded = try std.json.Stringify.valueAlloc(a, retained, .{});
    const decoded = try @import("../../../src/domain/strict_json.zig").decode(c.Report, a, encoded, .{ .maximum_depth = 64 });
    const settings = try std.json.Stringify.valueAlloc(a, decoded.retry_settings, .{});
    for ([_][]const u8{ encoded, try @import("../e2e/report.zig").renderMarkdown(a, decoded) }) |output| {
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
        .schema = .@"spec-e2e-report/v9",
        .started_at_utc = "2026-09-12T00:00:00Z",
        .case_id = "<script> [click](untrusted)",
        .status = .input_invalid,
        .diagnostic = "MissingTestApiKey",
    };
    const view = try @import("../e2e/report.zig").renderMarkdown(arena.allocator(), report);
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
    const obs = @import("../e2e/observation.zig");
    const Origin = @import("../../../src/domain/model_candidate_origin.zig").Origin;
    const original: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const repair: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const Usage = @import("../../../src/domain/llm_provider_operation.zig").ProviderUsage;
    var calls = [_]obs.Call{
        .{ .origin = original, .step = "extract", .usage = Usage.init(100, 20, 120).?, .output = .available },
        .{ .origin = repair, .step = "repair", .output = .available },
    };
    var report: c.Report = .{
        .schema = .@"spec-e2e-report/v9",
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
    const event = try @import("../e2e/trace.zig").Trace.stepEvent(a, 91, .{ .bytes = "validate-selections" }, .{ .outcome = .invalid }, report);
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
    for ([_][]const u8{ try @import("../e2e/report.zig").renderMarkdown(a, report), try @import("../e2e/report.zig").terminal(a, report, "runs", "sample") }) |rendered| {
        try std.testing.expect(std.mem.indexOf(u8, rendered, "validate-accounting") != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, "operation_failed") != null);
    }
    // Correlation cannot fill missing evidence by assuming the latest call.
    calls[0].output = .not_projected;
    try std.testing.expectError(error.MissingRequestEvidence, obs.correlate(a, &calls, &report));
    calls[0].output = .available;
    report.candidate_error.?.source_selections.origin.?.attempt.value = 9;
    try std.testing.expectError(error.MissingRequestEvidence, obs.correlate(a, &calls, &report));
    report.candidate_error.?.source_selections.origin = null;
    try std.testing.expectEqual(.missing_response, report.candidate_error.?.attribution());
    try std.testing.expectError(error.MissingRequestEvidence, obs.correlate(a, &calls, &report));
    // A correlation failure does not erase a successfully captured response.
    report.candidate_error = null;
    report.evidence_error = "MissingRequestEvidence";
    try obs.correlate(a, &calls, &report);
    try std.testing.expectEqual(.available, report.exchange_evidence.?.text);
    try std.testing.expect(report.last_model_output != null);
    calls[1].output = .not_projected;
    calls[1].raw_response_available = true;
    try obs.correlate(a, &calls, &report);
    try std.testing.expectEqual(.not_projected, report.exchange_evidence.?.text);
    calls[0].origin = repair;
    try std.testing.expectError(error.MissingRequestEvidence, obs.correlate(a, &calls, &report));
}

test "reports preserve native extraction reconciliation authoring coverage specification and review failures after source release" {
    const reference_fixture = @import("../../../src/reference_reconciliation_test.zig");
    const references = @import("../../../src/test_fixtures/reference_reconciliation.zig");
    const Diagnostic = @import("../../../src/domain/candidate_validation_diagnostic.zig").Diagnostic;
    const Origin = @import("../../../src/domain/model_candidate_origin.zig").Origin;
    const origin: Origin = .{ .request = .{ .value = 3 }, .attempt = .{ .value = 2 } };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var retained: [7]Diagnostic = undefined;
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
        var omission_inputs = review_inputs;
        omission_inputs.review_origin = origin;
        retained[4] = try (Diagnostic{ .support_findings = .from(.source, omission_inputs, .unlocalized_omission) }).copy(a);
        const missing = (try @import("../../../src/domain/specification_support.zig").Source.validate(scratch, review_inputs, context.inputs, .{
            .review = .{ .entries = &.{} },
            .origin = origin,
            .origins = &.{},
            .omission_conflict_claims = context.references.records.assignments.checked.prior.prior.source.omission_conflict_claims,
        })).rejected;
        try std.testing.expect(missing.rejection.diagnostics.len > 1);
        retained[3] = try (Diagnostic{ .support = missing.rejection }).copy(a);
        const registry = @import("../../../src/domain/principle_registry.zig");
        const policies = try @import("../../../src/test_fixtures/principles.zig").registry(scratch, "Use UTC timestamps.\n");
        const selection = try registry.select(scratch, policies, .{ .stage = .spec, .environment = null, .fileKind = null });
        const citation = (try registry.validateCitation(policies, selection, .{ .chunk = .{ .ordinal = 8 }, .first_line = 1, .last_line = 1 })).?;
        retained[5] = try (Diagnostic{ .principle_review = .{ .diagnostics = &.{.{ .issue = .invalid_evidence, .requirement = .{ .kind = .policy_predicate, .unit = .{ .decision = .{ .ordinal = 8 } }, .slot = .compliance }, .ordinal = 8, .revision = 1, .origin = origin, .entry_index = 7, .evidence = .{ .issue = .invalid_principle_citation, .rule = .{ .citations_required = true, .permitted_chunks = selection.chunks }, .citation = .{ .index = 0, .diagnostic = citation } } }} } }).copy(a);
        var current = (try @import("../../../src/domain/specification_session.zig").initialize(scratch, .{ .bytes = "chosen" }, context)).ready;
        current.completed = 1;
        const action = @import("../../../src/actions/specification/validate_specification_unit.zig").Action{ .validator = @import("../../../src/test_fixtures/reference_text.zig").validator };
        const groups = try @import("../../../src/domain/specification_source_binding.zig").catalogue(scratch, @import("../../../src/domain/reference_support.zig").records(accounted), .content);
        try std.testing.expect(groups.len > 0);
        const spec = (try action.execute(scratch, current, context, .{ .origins = .{ .initial = origin }, .response = .{ .content = .{ .primary_user_story = .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "A reservation is confirmed." } }} }, .source_group_ids = &.{groups[0].signal_id}, .provenance = .{ .claim_ids = &.{.{ .ordinal = 999 }}, .clarification_response_ids = &.{} } } } } })).invalid;
        retained[1] = try (Diagnostic{ .specification = spec }).copy(a);
        const extraction_action = @import("../../../src/actions/reference/validate_reference_extraction_text.zig").Action{ .validator = @import("../../../src/test_fixtures/reference_text.zig").validator };
        const lexical = (try extraction_action.execute(scratch, context.registry, context.current, input.inputs, .{ .entries = &.{.{ .scope = .{ .state_id = input.inputs.corpus.state_id, .chunk_id = input.inputs.chunks.entries[0].id }, .origin = origin, .token_classifications = &.{}, .outcome = .{ .no_feature_claim = .{ .nodes = &.{.{ .literal = .{ .value = "Invalid\x01text" } }} } } }} })).invalid;
        retained[2] = try (Diagnostic{ .extraction_text = lexical }).copy(a);
        var partial = context;
        partial.references.records.signals = &.{};
        partial.references.records.assignments.checked.prior.prior.source.fields = &.{.{ .unit = .signals, .field = .record, .origin = origin }};
        const gap = (try @import("../../../src/domain/specification_session.zig").initialize(scratch, .{ .bytes = "chosen" }, partial)).blocked;
        retained[6] = try (Diagnostic{ .source_catalogue = gap }).copy(a);
    }
    for (retained) |diagnostic| {
        const report: c.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "", .status = if (diagnostic == .source_catalogue) .workflow_blocked else .workflow_failed, .workflow_outcome = if (diagnostic == .source_catalogue) .blocked else .invalid, .terminal_step = "native-validation", .candidate_error = diagnostic };
        const decoded = try @import("../contracts.zig").decode(c.Report, a, try std.json.Stringify.valueAlloc(a, report, .{}));
        try std.testing.expectEqualDeep(report, decoded);
        try std.testing.expectEqualDeep(origin, decoded.candidate_error.?.origin().?);
        const bytes = try std.json.Stringify.valueAlloc(a, diagnostic, .{});
        for ([_][]const u8{ try @import("../e2e/report.zig").renderMarkdown(a, decoded), try @import("../e2e/report.zig").terminal(a, decoded, "runs", "case") }) |output| {
            try std.testing.expect(std.mem.indexOf(u8, output, bytes) != null);
            try std.testing.expect(std.mem.indexOf(u8, output, "native-validation") != null);
            if (diagnostic == .support_findings) try std.testing.expect(std.mem.indexOf(u8, output, "No upstream repair target can be authorized") != null);
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
        signals[0].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Invalid\x01text" } }} } } };
        proposal.signals = signals;
        const candidate: reference.r.Parsed = .{ .input = current, .proposal = .{ .global = proposal } };
        const rejected = (try reference.validate_signals.execute(scratch, (try reference.validate_dispositions.execute(scratch, candidate)).valid, inputs.context())).invalid;
        const authorization = (try repair.authorize(scratch, candidate, inputs.context(), rejected)).model;
        for (0..2) |index| {
            const value = try repair.merge(scratch, try @import("../../../src/domain/typed_text.zig").CanonicalText.fromInputs(scratch, @import("../../../src/test_fixtures/reference_text.zig").normalizer, inputs.inputs), candidate, inputs.context(), authorization, if (index == 0) authorization.operation.replace else .{ .content = good }, .{ .request = .{ .value = 5 }, .attempt = .{ .value = 2 } });
            merged[index] = try value.source.last_repair.?.copy(a);
            const validation = try reference.validate_signals.execute(scratch, (try reference.validate_dispositions.execute(scratch, value)).valid, inputs.context());
            if (index == 0) retained = try (Diagnostic{ .reconciliation = validation.invalid }).copy(a) else try std.testing.expect(validation == .valid);
        }
    }
    try std.testing.expectEqual(.invalid_scalar, retained.reconciliation.issue.expected.text_issue.reason);
    for (merged, 0..) |merge, index| {
        const report: c.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "", .status = .workflow_failed, .workflow_outcome = if (index == 0) .invalid else .ok, .terminal_step = "validate-signals", .candidate_error = if (index == 0) retained else null, .repairs = &.{merge} };
        const decoded = try @import("../contracts.zig").decode(c.Report, a, try std.json.Stringify.valueAlloc(a, report, .{}));
        try std.testing.expectEqualDeep(report, decoded);
        try std.testing.expectEqual(index == 1, decoded.repairs[0].changed);
        try std.testing.expectEqual(@as(u64, 1), merge.revision_before);
        try std.testing.expectEqual(@as(u64, 2), merge.revision_after);
        const bytes = try std.json.Stringify.valueAlloc(a, report.repairs, .{});
        for ([_][]const u8{ try @import("../e2e/report.zig").renderMarkdown(a, decoded), try @import("../e2e/report.zig").terminal(a, decoded, "runs", "case") }) |output| try std.testing.expect(std.mem.indexOf(u8, output, bytes) != null);
        const event = try @import("../e2e/trace.zig").Trace.stepEvent(a, index + 1, .{ .bytes = "validate-signals" }, .{ .outcome = report.workflow_outcome.? }, decoded);
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

test "capture failure report retains the failing boundary and subsequent logging failure" {
    const native: @import("../../../src/domain/workflow_execution.zig").Rejection = .{ .model_capture = .{
        .code = .LOG_SERIALIZATION_FAILURE,
        .stage = .source_snapshot,
        .cause = .{ .source_snapshot = .missing_source_chain },
        .origin = .{ .request = .{ .value = 4 }, .kind = .inference, .attempt = .{ .value = 2 } },
        .direction = .request,
        .subsequent_logging_failure = .LOG_SINK_FAILURE,
    } };
    const value = c.TerminalRejection.fromNative(native);
    const bytes = try std.json.Stringify.valueAlloc(std.testing.allocator, value, .{});
    defer std.testing.allocator.free(bytes);
    var decoded = try std.json.parseFromSlice(c.TerminalRejection, std.testing.allocator, bytes, .{});
    defer decoded.deinit();
    try std.testing.expectEqual(.model_capture, decoded.value.kind);
    try std.testing.expectEqualStrings("MODEL_CAPTURE_SOURCE_SNAPSHOT_FAILURE", decoded.value.detail.?);
    try std.testing.expectEqualDeep(native.model_capture, decoded.value.capture_failure.?);
}

test "provider content rejection survives retirement and projects exact native event evidence" {
    const obs = @import("../e2e/observation.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var retained: obs.LastModelRejection = .{};
    defer retained.deinit(std.testing.allocator);
    var reason = "missing_final_text".*;
    const origin: @import("../../../src/domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 8 }, .attempt = .{ .value = 2 } };
    const observed: c.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "", .status = .workflow_failed, .last_model_origin = origin, .provider_origin = origin, .provider_diagnostic = &reason, .provider_content_diagnostic = .missing_final_text };
    try retained.observe(std.testing.allocator, 11, observed);
    @memset(&reason, 'x');
    var terminal: c.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "", .status = .workflow_failed };
    try retained.observe(std.testing.allocator, 12, terminal);
    try retained.project(a, 12, &terminal);
    retained.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("missing_final_text", terminal.last_provider_rejection.?.reason);
    try std.testing.expectEqualDeep(origin, terminal.last_provider_rejection.?.origin.?);
    try std.testing.expectEqual(@as(usize, 11), terminal.last_provider_rejection.?.call.?);
    try std.testing.expect(terminal.last_protocol_rejection == null);
    const event = try @import("../e2e/trace.zig").Trace.stepEvent(a, 14, .{ .bytes = "observe-provider" }, .{ .outcome = .failed }, observed);
    const tree = try std.json.parseFromSlice(std.json.Value, a, event, .{});
    try std.testing.expectEqualStrings("missing_final_text", tree.value.object.get("provider_content_diagnostic").?.string);
    // Pre-call authorization never inherits the previous exchange's origin.
    for ([_]usize{ 0, 12 }) |prior_calls| {
        terminal.provider_diagnostic = "authentication_failed";
        terminal.last_model_origin = if (prior_calls == 0) null else origin;
        try retained.observe(std.testing.allocator, prior_calls, terminal);
        try retained.project(a, prior_calls, &terminal);
        try std.testing.expect(terminal.last_provider_rejection.?.call == null);
        try std.testing.expect(terminal.last_provider_rejection.?.origin == null);
    }
    var calls = [_]obs.Call{.{ .origin = origin, .step = "prior-call", .provider_diagnostic = "missing_final_text" }};
    try obs.correlate(a, &calls, &terminal);
    try std.testing.expectEqualStrings("missing_final_text", calls[0].provider_diagnostic.?);
    try std.testing.expectEqualStrings("authentication_failed", terminal.provider_diagnostic.?);
    try std.testing.expect(terminal.provider_origin == null);
}

test "native correction links retain first observation invalidation rebuild and unresolved work" {
    const execution = @import("../../../src/domain/workflow_execution.zig");
    const Progress = @import("../e2e/progress.zig").Progress;
    var progress = Progress.init(std.testing.allocator);
    defer progress.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var report: c.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "", .status = .workflow_failed, .last_operation_rejection = .{ .cause = .UnsafeSpecificationRepair, .outcome = .blocked } };
    try progress.observe(2, "authorize", report, null);
    report.last_operation_rejection = null;
    const permit: @import("../../../src/domain/workflow_retry.zig").Permit = .{ .key = .{ .scope = @splat(1), .target = @splat(2), .family = @splat(3) }, .authorization = @splat(4), .revision = 1, .maximum_targets = 1 };
    try progress.observe(3, "merge", report, execution.AppliedEffects{ .invalidations = .initMany(&.{ .identified_specification_content, .specification_support_review }), .repair = .{ .merged = .{ .permit = permit, .changed = true, .revision_after = 2, .validation = .dependent_review } } });
    try progress.observe(4, "rebuild-content", report, execution.AppliedEffects{ .writes = .initOne(.identified_specification_content) });
    try progress.observe(5, "failed-merge", report, null);
    try progress.project(a, &report);
    progress.deinit();
    progress = Progress.init(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), report.first_native_rejection.?.sequence);
    try std.testing.expectEqualStrings("authorize", report.first_native_rejection.?.step);
    try std.testing.expectEqual(.UnsafeSpecificationRepair, report.first_native_rejection.?.evidence.operation.cause);
    try std.testing.expectEqual(@as(usize, 2), report.corrections.len);
    try std.testing.expectEqualDeep(permit, report.corrections[0].repair.?.merged.permit);
    try std.testing.expectEqual(@as(u64, 2), report.corrections[0].repair.?.merged.revision_after);
    try std.testing.expectEqualDeep(c.WorkLink{ .key = .identified_specification_content, .invalidated_at = 3 }, report.corrections[1].rebuilt[0]);
    try std.testing.expectEqualDeep(&[_]c.WorkLink{.{ .key = .specification_support_review, .invalidated_at = 3 }}, report.outstanding_work);
    const readback = try @import("../contracts.zig").decode(c.Report, a, try std.json.Stringify.valueAlloc(a, report, .{}));
    try std.testing.expectEqualDeep(report.corrections, readback.corrections);
    const renamed = try std.json.Stringify.valueAlloc(a, report, .{});
    try std.testing.expect(std.mem.indexOf(u8, renamed, "\"first_native_rejection\"") != null);
    const removed_label = "first_" ++ "observed_defect";
    const obsolete = try std.mem.replaceOwned(u8, a, renamed, "first_native_rejection", removed_label);
    try std.testing.expectError(error.InvalidEvaluationContract, @import("../contracts.zig").decode(c.Report, a, obsolete));
    const old_version = try std.mem.replaceOwned(u8, a, renamed, "spec-e2e-report/v9", "spec-e2e-report/v2");
    try std.testing.expectError(error.InvalidEvaluationContract, @import("../contracts.zig").decode(c.Report, a, old_version));
    const previous_version = try std.mem.replaceOwned(u8, a, renamed, "spec-e2e-report/v9", "spec-e2e-report/v8");
    try std.testing.expectError(error.InvalidEvaluationContract, @import("../contracts.zig").decode(c.Report, a, previous_version));
    const missing_version = try std.mem.replaceOwned(u8, a, renamed, "\"schema\":\"spec-e2e-report/v9\",", "");
    try std.testing.expectError(error.InvalidEvaluationContract, @import("../contracts.zig").decode(c.Report, a, missing_version));
    const text = try @import("../e2e/report.zig").renderMarkdown(a, readback);
    try std.testing.expect(std.mem.indexOf(u8, text, "First native rejection") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "not proven root cause") != null);
    var fresh: c.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "", .status = .workflow_failed };
    try progress.project(a, &fresh);
    try std.testing.expect(fresh.first_native_rejection == null and fresh.corrections.len == 0 and fresh.outstanding_work.len == 0);
}

test "build evidence preserves bytes deletion and incompleteness and marks credential redaction" {
    const provenance = @import("../../../build/provenance.zig");
    const save = @import("../e2e/build_evidence.zig").save;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for (0..3) |example| {
        var destination = std.testing.tmpDir(.{});
        defer destination.cleanup();
        const store: @import("../evidence.zig").Store = .{ .io = std.testing.io, .allocator = a, .run = destination.dir, .secrets = &.{"MOCK_CREDENTIAL"} };
        const bundle: provenance.Bundle = .{ .identity = .{ .revision = "MOCK_REVISION", .source_sha256 = "MOCK_HASH", .modified = true }, .inputs = &.{ .{ .path = "src/untracked.zig", .state = .captured, .bytes = if (example == 1) "MOCK_CREDENTIAL" else "new source" }, .{ .path = "src/deleted.zig", .state = .deleted } }, .complete = example != 2 };
        const state = try save(store, try std.json.Stringify.valueAlloc(a, bundle, .{}));
        try std.testing.expectEqual(@as(@TypeOf(state), if (example == 0) .captured else if (example == 1) .redacted else .incomplete), state);
        const bytes = try @import("../files.zig").read(std.testing.io, a, destination.dir, "build-inputs.json");
        try std.testing.expect(std.mem.indexOf(u8, bytes, "MOCK_CREDENTIAL") == null);
        const readback = try @import("../contracts.zig").decode(provenance.Bundle, a, bytes);
        try std.testing.expectEqualStrings(if (example == 1) "[REDACTED_CREDENTIAL]" else "new source", readback.inputs[0].bytes.?);
        try std.testing.expectEqual(.deleted, readback.inputs[1].state);
        try std.testing.expectEqual(example == 0, readback.complete);
        try std.testing.expectError(error.PathAlreadyExists, save(store, bytes));
        var invalid = bundle;
        invalid.schema = "build-inputs/v2";
        try std.testing.expectError(error.InvalidBuildInputs, save(store, try std.json.Stringify.valueAlloc(a, invalid, .{})));
        invalid = bundle;
        invalid.inputs = &.{.{ .path = "src/missing.zig", .state = .captured }};
        try std.testing.expectError(error.InvalidBuildInputs, save(store, try std.json.Stringify.valueAlloc(a, invalid, .{})));
    }
}

const AdviceProductionRun = struct {
    const Runner = @import("../../../src/application/workflow_pipeline_runner.zig").Runner;
    const Bindings = @import("../../../src/application/workflow_engine_child_bindings.zig");
    const execution = @import("../../../src/domain/workflow_execution.zig");
    const workflow = @import("../../../src/domain/workflow.zig");
    const admission = @import("../baseline/admission.zig");
    const provider = @import("../../../src/domain/llm_provider_operation.zig");
    const Mode = enum { source_output_limit, global_budget, malformed_source_protocol, advisory_repair_output_limit, advisory_repair_protocol, required_output_limit, required_source_output_limit };
    allocator: std.mem.Allocator,
    runner: *Runner,
    base: Bindings.ChildBindings,
    fake: *@import("../../../src/adapters/provider/fake_llm_provider.zig").FakeLLMProvider,
    tracker: *admission.Tracker,
    mode: Mode,
    sequence: usize = 0,
    exchanges: std.ArrayList(admission.Exchange) = .empty,
    source_sends: usize = 0,
    source_origins: std.ArrayList(@import("../../../src/domain/model_candidate_origin.zig").Origin) = .empty,
    required_source_sends: usize = 0,
    protocol_closures: usize = 0,
    protocol_limit: ?u32 = null,
    repair_sends: usize = 0,
    repair_origins: std.ArrayList(@import("../../../src/domain/model_candidate_origin.zig").Origin) = .empty,
    repair_stops: usize = 0,
    repair_permit: ?@import("../../../src/domain/workflow_retry.zig").Permit = null,
    injected_findings: usize = 0,
    generated_content: ?[]const u8 = null,
    principle_sends: usize = 0,
    principle_attempts: usize = 0,
    budget_before_stop: ?u128 = null,
    budget_stop_call: ?usize = null,
    stop_sends: usize = 0,
    failure: ?anyerror = null,

    fn consumeLease(context: *@import("../../../src/ports/provider_authorization_lease.zig").Context, reference: *const provider.ValidatedProviderAuthorizationLeaseRef, binding: *const @import("../../../src/domain/llm_provider_binding.zig").ValidatedProviderModelBinding, request: *const provider.IdentifiedProviderNeutralModelRequest, invoked: *const provider.InvokedProviderOperation, now: @import("../../../src/ports/provider_authorization_lease.zig").Error!u64) @import("../../../src/ports/provider_authorization_lease.zig").Error!@import("../../../src/ports/provider_authorization_lease.zig").Capability {
        const runner: *Runner = @ptrCast(@alignCast(context));
        const state = if (runner.model_accounting) |*value| value else return error.AuthorizationDenied;
        const port = state.authorization_leases.port(runner.provider_clock.?, runner.runtime);
        return port.consume_fn(port.context, reference, binding, request, invoked, now);
    }

    fn bindings(self: *@This()) Bindings.ChildBindings {
        return .{ .context = self, .vtable = &.{ .validate_operation_registry = selectValid, .parse_invocation = selectValid, .select_workflow = selectValid, .prepare_workflow = ready, .selected_graph = graph, .invoke_invocation = invocation, .invoke_step = step, .finalize = finalize } };
    }
    fn cast(context: *anyopaque) *@This() {
        return @ptrCast(@alignCast(context));
    }
    fn selectValid(_: *anyopaque) Bindings.SelectionStepOutcome {
        return .ok;
    }
    fn ready(_: *anyopaque) Bindings.PreparationOutcome {
        return .ok;
    }
    fn graph(context: *const anyopaque) *const @import("../../../src/domain/workflow_compilation.zig").CompiledWorkflow {
        const self: *const @This() = @ptrCast(@alignCast(context));
        return self.runner.selected.graph;
    }
    fn invocation(context: *anyopaque) execution.Applied {
        return cast(context).base.invokeInvocation();
    }
    fn finalize(context: *anyopaque, outcome: @import("../../../src/domain/run_outcome.zig").Outcome) @import("../../../src/domain/run_outcome.zig").Outcome {
        return cast(context).base.finalizeOutcome(outcome);
    }
    fn invalidPositiveDetail(a: std.mem.Allocator, body: []const u8) ![]const u8 {
        var parsed = try std.json.parseFromSlice(std.json.Value, a, body, .{});
        defer parsed.deinit();
        var value = &parsed.value;
        if (value.object.getPtr("findings")) |findings| value = findings.array.items[0].object.getPtr("value").?;
        const decision = value.object.get("kind") orelse value.object.get("decision").?;
        try std.testing.expect(std.mem.eql(u8, decision.string, "supported") or std.mem.eql(u8, decision.string, "compatible"));
        // JSON/schema allow the escaped scalar; native review detail admission
        // rejects the control and authorizes its exact detail-only repair.
        value.object.getPtr("detail").?.* = .{ .string = "Invalid review\x01detail" };
        return std.json.Stringify.valueAlloc(a, parsed.value, .{});
    }
    fn step(context: *anyopaque, id: workflow.WorkflowStepId) execution.Applied {
        const self = cast(context);
        const data = @import("../../../src/domain/pipeline_data.zig");
        const requests = @import("../../../src/application/model_request_workflow.zig");
        const Origin = @import("../../../src/domain/model_candidate_origin.zig").Origin;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        var origin: ?Origin = null;
        var projection: ?@FieldType(@import("../../../src/domain/model_input_packet.zig").AdvisoryAssessment, "projection") = null;
        var usage: ?provider.ProviderUsage = null;
        var stopped = false;
        var required_source = false;
        var protocol_closure = false;
        var repair_request = false;
        var repair_stop = false;
        for (self.runner.selected.graph.authority.steps) |entry| if (std.mem.eql(u8, entry.id.bytes, id.bytes)) {
            protocol_closure = std.mem.eql(u8, entry.operation_id.bytes, "complete-advisory-protocol-request");
            repair_stop = std.mem.eql(u8, entry.operation_id.bytes, "stop-specification-repair-advice") or std.mem.eql(u8, entry.operation_id.bytes, "stop-specification-protocol-repair-advice");
            if (!std.mem.eql(u8, entry.operation_id.bytes, "invoke-model")) break;
            const view: data.View = .{ .slots = self.runner.envelope.slots };
            const request = requests.readCurrent(&view, requests.prepared_schema) catch unreachable;
            const attempt = @import("../../../src/domain/model_attempt_accounting.zig").latestAttempt(self.runner.model_accounting.?.attempts).ordinal();
            origin = .{ .request = request.ledger().indexOf(request.id()).?, .attempt = attempt };
            if (request.packet()) |packet| if (packet.advisoryAssessment()) |advice| {
                projection = advice.projection;
            };
            repair_request = projection != null and request.id().purpose == .atomic_repair;
            if (projection != null and self.generated_content == null) {
                const support = @import("../../../src/application/specification_support_workflow.zig");
                const source = support.inputs(&view, support.progress(&view) catch unreachable) catch unreachable;
                const content = source.specification orelse source.principle_context.?.business.content;
                self.generated_content = @import("../../../src/domain/canonical_json.zig").encode(@import("../../../src/domain/specification.zig").IdentifiedContent, self.allocator, content) catch unreachable;
            }
            if (repair_request) {
                const permit = request.packet().?.repairPermit().?;
                std.testing.expectEqualDeep(permit, self.runner.repair_retry.currentPermit().?) catch unreachable;
                if (self.repair_permit) |prior| std.testing.expectEqualDeep(prior, permit) catch unreachable else self.repair_permit = permit;
                const owned = @import("../../../src/application/required_authority_values.zig");
                const repair_state = @import("../../../src/application/pipeline_values.zig").read(&view, @import("../../../src/application/specification_support_repair_workflow.zig").schema, owned.Value) catch unreachable;
                std.testing.expectEqual(if (projection == .source) @as(std.meta.Tag(owned.Payload), .support_repair) else .principle_support_repair, std.meta.activeTag(owned.payload(repair_state).*)) catch unreachable;
            }
            required_source = projection == null and request.id().purpose == .semantic_review;
            // Every request carries the configured model's registered controls,
            // whichever provider the shipped case selects.
            std.testing.expectEqual(request.binding().registry_entry.capabilities.inferenceControls(), request.prepared().?.controls) catch unreachable;
            if (projection == .principles) self.principle_attempts += 1;
            var body = if (repair_request) "{}" else @import("../../../src/test_fixtures/spec_generation_responses.zig").build(arena.allocator(), view, .{ .attempt = attempt.value, .entities_required = self.mode == .global_budget }) catch |err| std.debug.panic("offline production candidate: {s}", .{@errorName(err)});
            if (self.injected_findings == 0 and !repair_request and
                ((self.mode == .advisory_repair_output_limit and projection == .source) or (self.mode == .advisory_repair_protocol and projection == .principles)))
            {
                body = invalidPositiveDetail(arena.allocator(), body) catch unreachable;
                self.injected_findings += 1;
            }
            self.fake.invocation_plan = .{ .complete = .{ .content = body, .input_tokens = 5, .output_tokens = 2 } };
            if ((self.mode == .source_output_limit and projection == .source) or
                (self.mode == .advisory_repair_output_limit and repair_request) or
                (self.mode == .required_output_limit and request.id().immutable_unit_owner_id == .specification_unit) or
                (self.mode == .required_source_output_limit and required_source))
            {
                self.fake.invocation_plan = .{ .stopped = .{ .reason = .output_limit, .input_tokens = 5, .output_tokens = 2048 } };
                stopped = true;
                usage = provider.ProviderUsage.init(5, 2048, 2053).?;
            } else if (self.mode == .global_budget and projection == .source and self.source_sends == 0) {
                const tokens = self.runner.tokenLedger().snapshot();
                std.testing.expect(tokens.total_tokens < tokens.total_budget.value) catch unreachable;
                self.budget_before_stop = tokens.total_tokens;
                const crossing_usage = std.math.cast(u64, @as(u128, tokens.total_budget.value) + 1 - tokens.total_tokens).?;
                self.fake.invocation_plan.complete.input_tokens = crossing_usage - 1;
                self.fake.invocation_plan.complete.output_tokens = 1;
                usage = provider.ProviderUsage.init(crossing_usage - 1, 1, crossing_usage).?;
            } else {
                if ((self.mode == .malformed_source_protocol and projection == .source) or (self.mode == .advisory_repair_protocol and repair_request)) self.fake.invocation_plan.complete.content = "{";
                usage = provider.ProviderUsage.init(5, 2, 7).?;
            }
            break;
        };
        const before = self.fake.invocation_call_count;
        const result = self.base.invokeStep(id);
        if (self.fake.invocation_call_count != before) {
            std.testing.expectEqual(before + 1, self.fake.invocation_call_count) catch unreachable;
            self.exchanges.append(self.allocator, .{ .call = self.fake.invocation_call_count, .origin = origin.?, .usage = usage }) catch unreachable;
            if (projection) |purpose| switch (purpose) {
                .source => {
                    self.source_sends += 1;
                    self.source_origins.append(self.allocator, origin.?) catch unreachable;
                },
                .principles => self.principle_sends += 1,
            };
            if (self.mode == .global_budget and projection == .source) {
                std.testing.expect(self.budget_stop_call == null) catch unreachable;
                self.budget_stop_call = self.fake.invocation_call_count;
            }
            if (required_source) self.required_source_sends += 1;
            if (repair_request) {
                self.repair_sends += 1;
                self.repair_origins.append(self.allocator, origin.?) catch unreachable;
            }
            if (stopped) self.stop_sends += 1;
        }
        self.sequence += 1;
        const current: data.View = .{ .slots = self.runner.envelope.slots };
        if (protocol_closure) {
            const request = requests.readCurrent(&current, requests.prepared_schema) catch unreachable;
            const ledger = @import("../../../src/application/pipeline_values.zig").read(&current, requests.ledger_schema, @import("../../../src/domain/model_request_identity.zig").ModelRequestIdentityLedger) catch unreachable;
            const record = ledger.record(request.id()).?;
            std.testing.expectEqual(.terminal, record.status) catch unreachable;
            std.testing.expectEqual(.failed, record.terminal_reason.?) catch unreachable;
            const receipt = @import("../../../src/application/workflow_model_accounting.zig").readAdvisoryStop(&current) catch unreachable;
            self.protocol_limit = receipt.exhaustion().limit.value;
            std.testing.expectEqual(if (self.mode == .advisory_repair_protocol) self.repair_sends else self.source_sends, receipt.exhaustion().completed_executions) catch unreachable;
            self.protocol_closures += 1;
        }
        if (repair_stop and result == .outcome and result.outcome == .ok) {
            std.testing.expect(!current.contains(.specification_support_repair)) catch unreachable;
            std.testing.expect(self.runner.repair_retry.currentPermit() == null) catch unreachable;
            self.repair_stops += 1;
        }
        self.tracker.observe(&current, self.sequence, self.fake.invocation_call_count) catch |err| {
            self.failure = err;
            return .{ .rejected = .{ .operation_failed = error.OperationExecutionFailed } };
        };
        return result;
    }
};

/// Counts production feature-log event rows containing both fragments.
fn featureLogRows(io: std.Io, a: std.mem.Allocator, project: std.Io.Dir, event: []const u8, code: []const u8) !usize {
    var specs = try project.openDir(io, "specs", .{ .iterate = true });
    defer specs.close(io);
    var walker = try specs.walk(a);
    defer walker.deinit();
    var count: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".log") or std.mem.indexOf(u8, entry.path, "logs/events/") == null) continue;
        const bytes = try entry.dir.readFileAlloc(io, entry.basename, a, .limited(64 * 1024 * 1024));
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, event) != null and std.mem.indexOf(u8, line, code) != null) count += 1;
        }
    }
    return count;
}

test "production workflow retains typed advice stops and enforces one global token budget" {
    const Runtime = @import("../../../src/composition/root.zig").Runtime;
    const Mode = AdviceProductionRun.Mode;
    const admission = @import("../baseline/admission.zig");
    const io = std.testing.io;
    for ([_]Mode{ .source_output_limit, .global_budget, .malformed_source_protocol, .advisory_repair_output_limit, .advisory_repair_protocol, .required_output_limit, .required_source_output_limit }) |mode| {
        errdefer std.debug.print("offline advice production scenario: {s}\n", .{@tagName(mode)});
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const choice = try c.parse(a, if (mode == .global_budget) @embedFile("../../e2e/wf-002-loan-renewal/workflow.case.json") else @embedFile("../../e2e/wf-001-hello-world/node-vitest/workflow.case.json"));
        var captured = try fixture.capture(io, a, .cwd(), choice);
        if (mode == .required_source_output_limit) {
            captured.config = try std.mem.replaceOwned(u8, a, captured.config, "\"sourcePreservationCheck\": false", "\"sourcePreservationCheck\": true");
            try std.testing.expect(std.mem.indexOf(u8, captured.config, "\"sourcePreservationCheck\": true") != null);
        }
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try fixture.materialize(io, project.dir, captured);
        var runtime: Runtime = undefined;
        runtime.init(io, std.testing.allocator, project.dir, .{});
        defer runtime.deinit();
        try std.testing.expect(runtime.boot == .ready);
        var invocation = runtime.invocation(&.{ choice.workflow_id, "--feature", choice.feature, "--reference", choice.reference }, .{ .snapshots = try familySnapshots((try configured(a, captured)).family, "offline-advisory-credential") });
        defer invocation.deinit();
        const bindings = invocation.bindings();
        try std.testing.expectEqual(.ok, bindings.invokeValidateOperationRegistry());
        try std.testing.expectEqual(.ok, bindings.invokeParseInvocation());
        try std.testing.expectEqual(.ok, bindings.invokeSelectWorkflow());
        try std.testing.expectEqual(.ok, bindings.invokePrepareWorkflow());
        const runner = &invocation.pipeline_runner.?;
        var clock: @import("../../../src/provider_authorization_test_fixture.zig").TestClock = .{};
        runner.provider_clock = clock.port();
        var authorization: @import("../../../src/adapters/provider/fake_provider_authorization.zig").FakeProviderAuthorization = .{ .allocator = std.testing.allocator };
        runtime.native.model_requests.prepare_authorization.action = .{ .authorization = authorization.port() };
        var fake: @import("../../../src/adapters/provider/fake_llm_provider.zig").FakeLLMProvider = .{
            .allocator = std.testing.allocator,
            .authorization_leases = .{ .context = @ptrCast(runner), .clock = runner.provider_clock.?, .runtime = runner.runtime, .consume_fn = AdviceProductionRun.consumeLease },
            .invocation_plan = .{ .complete = .{ .content = "{}", .input_tokens = 5, .output_tokens = 2 } },
        };
        runtime.native.model_requests.invoke_model.action = .{ .provider = fake.interface() };
        var tracker: admission.Tracker = .init(std.testing.allocator);
        defer tracker.deinit();
        var scripted: AdviceProductionRun = .{ .allocator = a, .runner = runner, .base = bindings, .fake = &fake, .tracker = &tracker, .mode = mode };
        const outcome = @import("../../../src/application/workflow_engine_orchestrator.zig").run(scripted.bindings());
        if (scripted.failure) |err| return err;
        // ADR 0011: every provider-applied stop, required or advisory, reaches the
        // production feature log with its exact reason; nothing else emits it.
        const provider_stops = try featureLogRows(io, a, project.dir, "|model.provider_stopped|", "|OUTPUT_LIMIT|");
        switch (mode) {
            .source_output_limit, .advisory_repair_output_limit, .required_output_limit, .required_source_output_limit => try std.testing.expect(provider_stops >= 1),
            .global_budget, .malformed_source_protocol, .advisory_repair_protocol => try std.testing.expectEqual(@as(usize, 0), provider_stops),
        }
        const audit = tracker.snapshot(true);
        try admission.validate(a, audit, scripted.exchanges.items);
        const escaped = try admission.measure(audit, scripted.exchanges.items);
        try std.testing.expectEqual(.measured, escaped.status);
        try std.testing.expectEqual(@as(u64, 0), escaped.escaped_values);
        try std.testing.expectEqual(@as(u64, 0), escaped.escaped_origins);
        try std.testing.expect(escaped.admitted_values > 0);
        const tokens = runner.tokenLedger().snapshot();
        const required_stop = mode == .required_output_limit or mode == .required_source_output_limit;
        var actual_tokens: u128 = 0;
        for (scripted.exchanges.items) |exchange| actual_tokens += exchange.usage.?.total_tokens;
        try std.testing.expectEqual(actual_tokens, tokens.total_tokens);
        try std.testing.expectEqual(@as(u64, 100_000), tokens.total_budget.value);
        const roots = runtime.boot.ready.roots.registry();
        const selected_feature = try @import("../../../src/domain/feature_directory.zig").validate(a, .{ .bytes = choice.feature }, roots.featureDirectoryRoots());
        const paths = try artifacts.resolveFeaturePaths(a, roots.featureArtifactRoots(), selected_feature);
        if (mode == .global_budget) {
            try std.testing.expect(outcome == .execution_rejected);
            try std.testing.expect(outcome.execution_rejected == .token_budget);
            try std.testing.expectEqual(error.WorkflowTokenBudgetExceeded, outcome.execution_rejected.token_budget);
            try std.testing.expectEqual(@as(u128, 100_001), tokens.total_tokens);
            try std.testing.expect(scripted.budget_before_stop.? > 0);
            const last = scripted.exchanges.items[scripted.exchanges.items.len - 1];
            try std.testing.expectEqual(tokens.total_tokens, scripted.budget_before_stop.? + last.usage.?.total_tokens);
            try std.testing.expectEqual(scripted.budget_stop_call.?, scripted.exchanges.items.len);
            try std.testing.expectEqual(fake.invocation_call_count, scripted.budget_stop_call.?);
            try std.testing.expectEqual(@as(usize, 1), scripted.source_sends);
            try std.testing.expectEqual(@as(usize, 0), scripted.principle_sends + scripted.principle_attempts);
            const view: @import("../../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            const support = @import("../../../src/application/specification_support_workflow.zig");
            const progress = try support.progress(&view);
            const inputs = try support.inputs(&view, progress);
            try std.testing.expect(inputs.advice_stop == null);
            try std.testing.expect(!view.contains(.published_workflow_output));
            var entity_fields: usize = 0;
            for (audit.checks) |check| if (check.subject == .specification and check.subject.specification.unit == .entities and check.subject.specification.record_kind == .entity) {
                entity_fields += 1;
            };
            try std.testing.expect(entity_fields >= 2);
            try std.testing.expectError(error.FileNotFound, project.dir.access(io, paths.get(.specification).project_relative, .{}));
            try std.testing.expectError(error.FileNotFound, project.dir.access(io, paths.get(.workflow_state).project_relative, .{}));
            continue;
        }
        if (required_stop) {
            try std.testing.expect(outcome == .execution);
            try std.testing.expectEqual(.failed, outcome.executionStatus().?);
            try std.testing.expectEqual(@as(usize, 1), scripted.stop_sends);
            try std.testing.expectEqual(@as(usize, 0), scripted.source_sends + scripted.principle_sends);
            if (mode == .required_source_output_limit) {
                try std.testing.expectEqual(@as(usize, 1), scripted.required_source_sends);
                const view: @import("../../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
                const support = @import("../../../src/application/specification_support_workflow.zig");
                const progress = try support.progress(&view);
                try std.testing.expect(progress == .initial);
                const inputs = try support.inputs(&view, progress);
                try std.testing.expect(inputs.advice_stop == null);
            }
            try std.testing.expectError(error.FileNotFound, project.dir.access(io, paths.get(.specification).project_relative, .{}));
            try std.testing.expectError(error.FileNotFound, project.dir.access(io, paths.get(.workflow_state).project_relative, .{}));
            continue;
        }
        try std.testing.expectEqual(.ok, outcome.executionStatus().?);
        if (mode == .advisory_repair_protocol) {
            try std.testing.expect(scripted.source_sends > 0);
            for (scripted.source_origins.items, 0..) |origin, index| {
                try std.testing.expectEqual(@as(u32, 1), origin.attempt.value);
                for (scripted.source_origins.items[0..index]) |prior| try std.testing.expect(prior.request.value != origin.request.value);
            }
        } else try std.testing.expectEqual(switch (mode) {
            .malformed_source_protocol => @as(usize, scripted.protocol_limit.?) + 1,
            .advisory_repair_output_limit => @as(usize, 2),
            else => @as(usize, 1),
        }, scripted.source_sends);
        try std.testing.expectEqual(@as(usize, 1) + (if (mode == .advisory_repair_protocol) scripted.repair_sends else 0), scripted.principle_attempts);
        try std.testing.expectEqual(@as(usize, 1) + (if (mode == .advisory_repair_protocol) scripted.repair_sends else 0), scripted.principle_sends);
        const state_bytes = try project.dir.readFileAlloc(io, paths.get(.workflow_state).project_relative, a, .limited(64 * 1024 * 1024));
        const restored = try @import("../../../src/domain/specification_state.zig").parse(a, state_bytes, .{ .bytes = choice.feature }, runtime.boot.ready.workflows.registry().contractSource());
        const state = restored.specified().?;
        try std.testing.expectEqualStrings(scripted.generated_content.?, try @import("../../../src/domain/canonical_json.zig").encode(@import("../../../src/domain/specification.zig").IdentifiedContent, a, state.content));
        const stop = if (mode == .advisory_repair_protocol) state.principle_assessment.advice_stop.? else state.review.advice_stop.?;
        const result = if (mode == .advisory_repair_protocol) state.principle_assessment.result else state.review.result;
        try std.testing.expectEqual(@as(@import("../../../src/domain/required_authority.zig").AdviceStop.Reason, switch (mode) {
            .source_output_limit, .advisory_repair_output_limit => .provider_output_limit,
            .malformed_source_protocol, .advisory_repair_protocol => .protocol_exhausted,
            .global_budget, .required_output_limit, .required_source_output_limit => unreachable,
        }), stop.reason);
        try std.testing.expect(stop.origin != null);
        try std.testing.expect(stop.unassessed.len > 0);
        try std.testing.expectEqual(state.review.candidate_revision, stop.candidate_revision);
        var incomplete: usize = 0;
        for (result.entries) |entry| if (entry.outcome == .assessment_incomplete) {
            incomplete += 1;
        };
        try std.testing.expectEqual(stop.unassessed.len, incomplete);
        if (mode == .malformed_source_protocol) {
            try std.testing.expectEqual(@as(usize, 1), scripted.protocol_closures);
            for (scripted.source_origins.items, 0..) |source_origin, index| {
                try std.testing.expectEqualDeep(scripted.source_origins.items[0].request, source_origin.request);
                try std.testing.expectEqual(index + 1, source_origin.attempt.value);
            }
            try std.testing.expectEqualDeep(scripted.source_origins.items[scripted.source_origins.items.len - 1], state.review.advice_stop.?.origin.?);
        } else if (mode == .advisory_repair_protocol) {
            try std.testing.expectEqual(@as(usize, 1), scripted.protocol_closures);
            try std.testing.expectEqual(@as(usize, scripted.protocol_limit.?) + 1, scripted.repair_sends);
            for (scripted.repair_origins.items, 0..) |origin, index| {
                try std.testing.expectEqualDeep(scripted.repair_origins.items[0].request, origin.request);
                try std.testing.expectEqual(index + 1, origin.attempt.value);
            }
            try std.testing.expectEqualDeep(scripted.repair_origins.items[scripted.repair_origins.items.len - 1], stop.origin.?);
            try std.testing.expect(state.review.advice_stop == null);
        } else try std.testing.expectEqual(@as(usize, 0), scripted.protocol_closures);
        const repair_mode = mode == .advisory_repair_output_limit or mode == .advisory_repair_protocol;
        try std.testing.expectEqual(@as(usize, @intFromBool(repair_mode)), scripted.injected_findings);
        try std.testing.expectEqual(@as(usize, @intFromBool(repair_mode)), scripted.repair_stops);
        try std.testing.expect(runner.repair_retry.currentPermit() == null);
        try std.testing.expect(!(@import("../../../src/domain/pipeline_data.zig").View{ .slots = runner.envelope.slots }).contains(.specification_support_repair));
        if (mode == .advisory_repair_output_limit) {
            try std.testing.expectEqual(@as(usize, 1), scripted.repair_sends);
            try std.testing.expectEqualDeep(scripted.repair_origins.items[0], stop.origin.?);
        } else if (!repair_mode) try std.testing.expectEqual(@as(usize, 0), scripted.repair_sends);
        if (mode != .advisory_repair_protocol) try std.testing.expect(state.principle_assessment.advice_stop == null);
        try std.testing.expect(state.coverage.obligations.len > 0);
        for (state.coverage.obligations) |obligation| try std.testing.expect(obligation.exact_targets.len > 0);
        try project.dir.access(io, paths.get(.specification).project_relative, .{});
        try project.dir.access(io, paths.get(.reference_context).project_relative, .{});
        try std.testing.expectEqual(fake.invocation_call_count, scripted.exchanges.items.len);
    }
}

const provider_keys = @import("../../../src/adapters/provider/provider_api_key.zig");
const provider_transport = @import("../../../src/adapters/provider/model_http_transport.zig");

/// The provider and model the shipped case's generation slot configures, so
/// these tests follow the case instead of naming a provider.
const Configured = struct { family: provider_keys.Family, provider: []const u8, model: []const u8 };

fn configured(a: std.mem.Allocator, captured: fixture.Capture) !Configured {
    const config = try std.json.parseFromSliceLeaky(std.json.Value, a, captured.config, .{});
    const slot = config.object.get("models").?.object.get("slots").?.object.get("spec_generation").?;
    const provider = slot.object.get("provider").?.string;
    for (std.enums.values(provider_keys.Family)) |family| {
        if (std.mem.eql(u8, family.configSchema().providerId().?, provider)) return .{ .family = family, .provider = provider, .model = slot.object.get("model").?.string };
    }
    return error.UnknownConfiguredProvider;
}

/// A harness-supplied key for one family and none for any other.
fn familySnapshots(family: provider_keys.Family, raw: ?[]const u8) !provider_keys.Supplied {
    var supplied: provider_keys.Supplied = .initFill(null);
    supplied.set(family, try provider_keys.Snapshot.capture(std.testing.allocator, raw));
    return supplied;
}

/// Answers each request in its own family's wire shape: one fixed text, or
/// reasoning alone when `text` is null, with usage of 884 input and 48 output.
const ProviderWire = struct {
    allocator: std.mem.Allocator,
    model: []const u8,
    text: ?[]const u8,
    calls: usize = 0,
    last_body: []const u8 = "",

    fn port(self: *ProviderWire) provider_transport.Port {
        return .{ .context = @ptrCast(self), .exchange_fn = exchange };
    }

    fn exchange(context: *provider_transport.Context, _: std.mem.Allocator, request: provider_transport.Request) provider_transport.Error!provider_transport.Response {
        const self: *ProviderWire = @ptrCast(@alignCast(context));
        self.calls += 1;
        self.last_body = switch (request.target) {
            .aws_bedrock => if (self.text) |text| try std.json.Stringify.valueAlloc(self.allocator, .{
                .output = .{ .message = .{ .role = "assistant", .content = .{.{ .text = text }} } },
                .stopReason = "end_turn",
                .usage = .{ .inputTokens = 884, .outputTokens = 48, .totalTokens = 932 },
            }, .{}) else "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"reasoningContent\":{\"reasoningText\":{\"text\":\"metadata\"}}}]}},\"stopReason\":\"end_turn\",\"usage\":{\"inputTokens\":884,\"outputTokens\":48,\"totalTokens\":932}}",
            .anthropic => try messagesBody(self.allocator, self.model, self.text),
        };
        return .{ .received = .{ .status = 200, .body = self.last_body } };
    }

    fn messagesBody(allocator: std.mem.Allocator, model: []const u8, text: ?[]const u8) std.mem.Allocator.Error![]const u8 {
        const Usage = struct { input_tokens: u64 = 884, output_tokens: u64 = 48, cache_creation_input_tokens: ?u64 = null, cache_read_input_tokens: ?u64 = null, cache_creation: ?u8 = null, output_tokens_details: ?u8 = null, server_tool_use: ?u8 = null, service_tier: []const u8 = "standard", inference_geo: ?[]const u8 = null, speed: ?[]const u8 = null };
        const Envelope = struct { id: []const u8 = "msg_offline", type: []const u8 = "message", role: []const u8 = "assistant", model: []const u8, content: []const u8, stop_reason: []const u8 = "end_turn", stop_sequence: ?u8 = null, stop_details: ?u8 = null, usage: Usage = .{}, container: ?u8 = null, diagnostics: ?u8 = null };
        const content = if (text) |value| try std.json.Stringify.valueAlloc(allocator, .{.{ .type = "text", .text = value, .citations = null }}, .{}) else "[{\"type\":\"thinking\",\"thinking\":\"metadata\",\"signature\":\"offline\"}]";
        const placeholder = "@@CONTENT@@";
        const shell = try std.json.Stringify.valueAlloc(allocator, Envelope{ .model = model, .content = placeholder }, .{});
        return std.mem.replaceOwned(u8, allocator, shell, "\"" ++ placeholder ++ "\"", content);
    }
};

/// A two-provider catalogue: both Claude models the slots below may select,
/// and the case's Bedrock model.
const two_provider_catalogue =
    \\{"providers":[
    \\{"provider":"anthropic","models":[
    \\{"model":"claude-haiku-5-5","json":false,"config":{"maxOutputTokens":128000}},
    \\{"model":"claude-opus-5-5","json":true,"config":{"maxOutputTokens":128000}}]},
    \\{"provider":"aws-bedrock","models":[
    \\{"model":"openai.gpt-oss-20b-1:0","json":true,"config":{"region":"ap-southeast-2","family":"gpt-oss","maxOutputTokens":16384}}]}]}
;

const claude_slot = "{\"provider\":\"anthropic\",\"model\":\"claude-haiku-5-5\",\"reasoningEffort\":\"low\"}";
const bedrock_slot = "{\"provider\":\"aws-bedrock\",\"model\":\"openai.gpt-oss-20b-1:0\",\"reasoningEffort\":\"low\"}";

/// Materialize the hello-world case with the two-provider catalogue, binding
/// the Spec workflow's generation and repair slots as given. The other slots,
/// which the Spec workflow never calls, stay on Bedrock.
fn twoProviderProject(io: std.Io, a: std.mem.Allocator, project: std.Io.Dir, captured: fixture.Capture, generation: []const u8, repair: []const u8) !void {
    try fixture.materialize(io, project, captured);
    var config = try std.json.parseFromSliceLeaky(std.json.Value, a, captured.config, .{});
    const slots = config.object.getPtr("models").?.object.getPtr("slots").?;
    for (slots.object.keys(), slots.object.values()) |name, *value| {
        const binding = if (std.mem.eql(u8, name, "spec_generation")) generation else if (std.mem.eql(u8, name, "repair")) repair else bedrock_slot;
        value.* = try std.json.parseFromSliceLeaky(std.json.Value, a, binding, .{});
    }
    try project.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = try std.json.Stringify.valueAlloc(a, config, .{}) });
    try project.writeFile(io, .{ .sub_path = ".sddtoolkit/providers/.sddproviders.json", .data = two_provider_catalogue });
}

test "configuration alone selects Claude, Bedrock or both per slot and reads only their keys" {
    const Runtime = @import("../../../src/composition/root.zig").Runtime;
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const choice = try c.parse(a, @embedFile("../../e2e/wf-001-hello-world/node-vitest/workflow.case.json"));
    const captured = try fixture.capture(io, a, .cwd(), choice);
    const Layout = struct { generation: []const u8, repair: []const u8, anthropic: bool, bedrock: bool };
    for ([_]Layout{
        // Claude only: no Bedrock key is read even though unused slots name Bedrock.
        .{ .generation = claude_slot, .repair = claude_slot, .anthropic = true, .bedrock = false },
        // Mixed: each family's key is read once.
        .{ .generation = claude_slot, .repair = bedrock_slot, .anthropic = true, .bedrock = true },
        // An unused Claude catalogue entry reads no Anthropic key.
        .{ .generation = bedrock_slot, .repair = bedrock_slot, .anthropic = false, .bedrock = true },
    }) |layout| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try twoProviderProject(io, a, project.dir, captured, layout.generation, layout.repair);
        var environment: std.process.Environ.Map = .init(std.testing.allocator);
        defer environment.deinit();
        try environment.put("AWS_BEARER_TOKEN_BEDROCK", "bedrock-credential");
        try environment.put("ANTHROPIC_API_KEY", "anthropic-credential");
        var runtime: Runtime = undefined;
        runtime.init(io, std.testing.allocator, project.dir, .{});
        defer runtime.deinit();
        try std.testing.expect(runtime.boot == .ready);
        var invocation = runtime.invocation(&.{ choice.workflow_id, "--feature", choice.feature, "--reference", choice.reference }, .{ .environment = &environment });
        defer invocation.deinit();
        const bindings = invocation.bindings();
        try std.testing.expectEqual(.ok, bindings.invokeValidateOperationRegistry());
        try std.testing.expectEqual(.ok, bindings.invokeParseInvocation());
        try std.testing.expectEqual(.ok, bindings.invokeSelectWorkflow());
        try std.testing.expectEqual(.ok, bindings.invokePrepareWorkflow());
        try std.testing.expect(runtime.provider_runtime.provider != null);
        const materials = &runtime.provider_runtime.authorization.materials;
        try std.testing.expectEqual(layout.anthropic, materials.get(.anthropic).* == .ready);
        try std.testing.expectEqual(layout.bedrock, materials.get(.aws_bedrock).* == .ready);
        if (layout.anthropic) try std.testing.expectEqualStrings("anthropic-credential", materials.get(.anthropic).ready.bytes);
        if (layout.bedrock) try std.testing.expectEqualStrings("bedrock-credential", materials.get(.aws_bedrock).ready.bytes);
    }
}

/// Answers every Messages request with one valid envelope and records targets.
const MessagesWire = struct {
    calls: usize = 0,
    foreign_targets: usize = 0,
    bodies: std.ArrayList([]u8) = .empty,
    text: []const u8,

    fn port(self: *MessagesWire) @import("../../../src/adapters/provider/model_http_transport.zig").Port {
        return .{ .context = @ptrCast(self), .exchange_fn = exchange };
    }

    fn deinit(self: *MessagesWire) void {
        for (self.bodies.items) |body| std.testing.allocator.free(body);
        self.bodies.deinit(std.testing.allocator);
    }

    fn exchange(context: *@import("../../../src/adapters/provider/model_http_transport.zig").Context, allocator: std.mem.Allocator, request: @import("../../../src/adapters/provider/model_http_transport.zig").Request) @import("../../../src/adapters/provider/model_http_transport.zig").Error!@import("../../../src/adapters/provider/model_http_transport.zig").Response {
        const self: *MessagesWire = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (request.target != .anthropic) self.foreign_targets += 1;
        try self.bodies.append(std.testing.allocator, try std.testing.allocator.dupe(u8, request.body));
        const body = try std.json.Stringify.valueAlloc(allocator, .{
            .id = "msg_offline",
            .type = "message",
            .role = "assistant",
            .model = "claude-haiku-5-5",
            .content = .{.{ .type = "text", .text = self.text, .citations = null }},
            .stop_reason = "end_turn",
            .stop_sequence = null,
            .stop_details = null,
            .usage = .{ .input_tokens = 884, .output_tokens = 48, .cache_creation_input_tokens = null, .cache_read_input_tokens = null, .cache_creation = null, .output_tokens_details = null, .server_tool_use = null, .service_tier = "standard", .inference_geo = null, .speed = null },
            .container = null,
            .diagnostics = null,
        }, .{});
        return .{ .received = .{ .status = 200, .request_id = "req_offline", .body = body } };
    }
};

test "a Claude-only Spec run sends every call through the shared adapter to the Messages endpoint" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const choice = try c.parse(a, @embedFile("../../e2e/wf-001-hello-world/node-vitest/workflow.case.json"));
    const captured = try fixture.capture(io, a, .cwd(), choice);
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try twoProviderProject(io, a, project.dir, captured, claude_slot, claude_slot);
    var runtime: @import("../../../src/composition/root.zig").Runtime = undefined;
    runtime.init(io, std.testing.allocator, project.dir, .{});
    defer runtime.deinit();
    try std.testing.expect(runtime.boot == .ready);
    const keys = @import("../../../src/adapters/provider/provider_api_key.zig");
    var supplied: keys.Supplied = .initFill(null);
    supplied.set(.anthropic, try keys.Snapshot.capture(std.testing.allocator, "offline-anthropic-credential"));
    var invocation = runtime.invocation(&.{ choice.workflow_id, "--feature", choice.feature, "--reference", choice.reference }, .{ .snapshots = supplied });
    defer invocation.deinit();
    const bindings = invocation.bindings();
    try std.testing.expectEqual(.ok, bindings.invokeValidateOperationRegistry());
    try std.testing.expectEqual(.ok, bindings.invokeParseInvocation());
    try std.testing.expectEqual(.ok, bindings.invokeSelectWorkflow());
    try std.testing.expectEqual(.ok, bindings.invokePrepareWorkflow());
    // Every candidate is malformed JSON, so the first request exhausts its retries.
    var wire: MessagesWire = .{ .text = "{" };
    defer wire.deinit();
    runtime.provider_runtime.provider.?.transport = wire.port();
    const Prepared = struct {
        fn selected(_: *anyopaque) @import("../../../src/application/workflow_engine_child_bindings.zig").SelectionStepOutcome {
            return .ok;
        }
        fn ready(_: *anyopaque) @import("../../../src/application/workflow_engine_child_bindings.zig").PreparationOutcome {
            return .ok;
        }
    };
    var prepared = bindings.vtable.*;
    prepared.validate_operation_registry = Prepared.selected;
    prepared.parse_invocation = Prepared.selected;
    prepared.select_workflow = Prepared.selected;
    prepared.prepare_workflow = Prepared.ready;
    const outcome = @import("../../../src/application/workflow_engine_orchestrator.zig").run(.{ .context = bindings.context, .vtable = &prepared });
    try std.testing.expectEqual(.failed, outcome.executionStatus().?);
    try std.testing.expectEqual(@as(usize, 3), wire.calls);
    try std.testing.expectEqual(@as(usize, 0), wire.foreign_targets);
    for (wire.bodies.items) |body| {
        var sent = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{});
        defer sent.deinit();
        try std.testing.expectEqualStrings("claude-haiku-5-5", sent.value.object.get("model").?.string);
        try std.testing.expectEqual(@as(i64, 128000), sent.value.object.get("max_tokens").?.integer);
        try std.testing.expectEqualStrings("low", sent.value.object.get("output_config").?.object.get("effort").?.string);
        // The catalogue selects prompt-only for this model: no native format.
        try std.testing.expect(sent.value.object.get("output_config").?.object.get("format") == null);
        try std.testing.expect(std.mem.indexOf(u8, body, "offline-anthropic-credential") == null);
    }
    try std.testing.expectEqual(@as(u64, 3), outcome.execution_rejected.retry_limit.completed_executions);
    // Captured prompt logs never hold the key.
    const log_runtime = &runtime.logging.?;
    const log_artifacts = @import("../../../src/domain/workflow_artifact_registry.zig");
    const log_paths = log_artifacts.bindFeatureLogSinkAdapter(log_artifacts.registry(log_runtime.artifact_owner.?), @import("../../../src/domain/feature_log_binding.zig").binding(log_runtime.binding_owner.?)).?;
    const prompt_path = try std.fmt.allocPrint(a, "{s}/{s}/0001.log", .{ log_paths.specs_root_path, log_paths.prompt_binding_path });
    const prompt_bytes = try project.dir.readFileAlloc(io, prompt_path, a, .limited(8 * 1024 * 1024));
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, prompt_bytes, "inference-request-provider_body-utf8-00000000000000000000"));
    try std.testing.expect(std.mem.indexOf(u8, prompt_bytes, "offline-anthropic-credential") == null);
    try std.testing.expect(std.mem.indexOf(u8, prompt_bytes, "\"model\":\"claude-haiku-5-5\"") != null);
}
