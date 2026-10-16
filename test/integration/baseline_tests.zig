//! Offline Phase 2 production-boundary evidence. Fake exchanges establish
//! wiring and rejection only; no authentic execution or semantic benefit.
const std = @import("std");
const comparison = @import("../harness/generation_comparison.zig");
const frozen_inputs = @import("../harness/baseline/freeze.zig");
const acquisition = @import("../harness/baseline/acquisition.zig");
const dispatch = @import("../harness/baseline/dispatch.zig");
const fixture = @import("../harness/e2e/fixture.zig");
const files = @import("../harness/files.zig");
const transport = @import("../../src/adapters/provider/bedrock_transport.zig");
const paths: frozen_inputs.InputPaths = .{
    .protocol = "test/calibration/semantic-simplicity/protocol.json",
    .cases = "test/calibration/semantic-simplicity/cases.json",
    .template_case = "test/e2e/wf-001-hello-world/node-vitest/workflow.case.json",
    .rubric = "test/calibration/semantic-simplicity/rubric.json",
};
const build: @import("../../build/provenance.zig").Identity = .{ .revision = "offline-baseline-boundary", .source_sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", .modified = true };
const key = "MOCK-offline-baseline-key";
const response = "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"{\\\"kind\\\":\\\"claims\\\",\\\"claims\\\":[]}\"}]}},\"stopReason\":\"end_turn\",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12}}";

fn prepare(a: std.mem.Allocator) !frozen_inputs.Freeze {
    const template_bytes = try files.read(std.testing.io, a, .cwd(), paths.template_case);
    const template = try @import("../harness/e2e/contracts.zig").parse(a, template_bytes);
    const path_policy = try @import("../../src/adapters/filesystem/workspace_path_policy.zig").Resolver.init(std.testing.io, .cwd()).resolve(a);
    return frozen_inputs.create(a, build, try files.read(std.testing.io, a, .cwd(), paths.protocol), try files.read(std.testing.io, a, .cwd(), paths.cases), template_bytes, try files.read(std.testing.io, a, .cwd(), paths.rubric), try fixture.capture(std.testing.io, a, .cwd(), template), paths, path_policy);
}

fn firstTrial(frozen: frozen_inputs.Freeze, feature_id: []const u8) !comparison.Trial {
    for (frozen.trials) |trial| if (std.mem.eql(u8, trial.feature_id, feature_id)) return trial;
    return error.MissingBaselineTrial;
}

test "test.integration.baseline reads compiled budget without dispatch and refuses an unresolved preparation" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const frozen = try prepare(a);
    for ([_]@import("../../src/domain/bootstrap_roots.zig").PathKey{ .references, .principles }) |key_kind| {
        const accepted = try frozen_inputs.configuredRoot(a, frozen, key_kind, "declared-root/");
        try std.testing.expectEqualStrings("declared-root", accepted.relative_path);
        try std.testing.expectEqual(key_kind, accepted.path_key);
        for ([_][]const u8{ "a//b", "a/../b", "a/%2f/b", "a\\b", "/absolute" }) |invalid| {
            try std.testing.expectError(error.BootstrapRootResolutionError, frozen_inputs.configuredRoot(a, frozen, key_kind, invalid));
        }
    }
    const projected = try frozen_inputs.project(a, frozen, frozen.trials[0]);
    var target = std.testing.tmpDir(.{});
    defer target.cleanup();
    try fixture.materialize(std.testing.io, target.dir, projected.captured);
    const budget = try @import("../harness/baseline/preflight.zig").workflowBudget(std.testing.io, a, target.dir, projected.selected.workflow_id);
    try std.testing.expectEqual(@as(u64, 100000), budget);
    const feasibility = @import("../harness/baseline/feasibility.zig");
    const plan = try feasibility.parse(a, try files.read(std.testing.io, a, .cwd(), "test/calibration/semantic-simplicity/budget-plan.example.json"));
    const report = try feasibility.evaluate(std.testing.io, a, .cwd(), plan, frozen.protocol, frozen.build, budget);
    try std.testing.expectEqual(.insufficient, report.status);
    try std.testing.expect(report.user_decision_required);
    try std.testing.expect(!report.workflow_authority);
    try std.testing.expectEqual(@as(usize, 0), report.evidence.len);
    try std.testing.expectEqual(@as(usize, 3), report.phases.len);
    try std.testing.expectError(error.BaselineNotFrozen, frozen_inputs.requireExecutable(a, frozen));
    // A forged admitted tag cannot turn insufficient cost evidence into a
    // frozen baseline, even after a claimed clean build is supplied.
    var forged = frozen;
    forged.build.modified = false;
    forged.admission = .{ .frozen = .{ .budget_plan_source = "budget.json", .feasibility = report } };
    try std.testing.expectError(error.BaselineBudgetNotAdmitted, frozen_inputs.requireExecutable(a, forged));
}

test "test.integration.baseline frozen development projects contain original sources without evaluator or holdout inputs" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const frozen = try prepare(a);
    try std.testing.expectEqual(@as(usize, 72), frozen.trials.len);
    try std.testing.expectEqual(@as(usize, 24), frozen.sources.len);
    const rubric_bytes = try files.read(std.testing.io, a, .cwd(), paths.rubric);
    try std.testing.expectEqualStrings(rubric_bytes, frozen.inputs.evaluation.rubric_bytes);
    try std.testing.expectEqualStrings(paths.rubric, frozen.inputs.evaluation.case.rubric);
    try std.testing.expectEqualStrings(try frozen_inputs.hash(a, rubric_bytes), frozen.rubric_sha256);
    const original_template = try @import("../harness/e2e/contracts.zig").parse(a, try files.read(std.testing.io, a, .cwd(), paths.template_case));
    const original_capture = try fixture.capture(std.testing.io, a, .cwd(), original_template);
    try std.testing.expect(!std.mem.eql(u8, original_capture.evaluation.rubric_bytes, frozen.inputs.evaluation.rubric_bytes));
    const inventory = try comparison.parseInventory(a, try files.read(std.testing.io, a, .cwd(), paths.cases));
    try frozen_inputs.verifySources(std.testing.io, a, .cwd(), frozen);
    const serialized = try std.json.Stringify.valueAlloc(a, frozen, .{});
    const decoded = try frozen_inputs.decode(a, serialized);
    try frozen_inputs.verifySources(std.testing.io, a, .cwd(), decoded);
    var original_config = try (@import("../../src/actions/config/decode_sddtoolkit_config.zig").Action{}).execute(a, decoded.inputs.config);
    defer original_config.deinit();
    const with_foreign_reference = try a.alloc(fixture.CapturedFile, decoded.inputs.files.len + 1);
    @memcpy(with_foreign_reference[0..decoded.inputs.files.len], decoded.inputs.files);
    with_foreign_reference[decoded.inputs.files.len] = .{
        .mapping = .{ .source = "baseline-unselected-source.md", .destination = try std.fs.path.join(a, &.{ original_config.value().paths.references, "unselected-feature", "source.md" }) },
        .bytes = "MOCK unselected reference must not enter the project.\n",
    };
    var foreign = decoded;
    foreign.inputs.files = with_foreign_reference;
    try std.testing.expectError(error.UnselectedReferenceInput, frozen_inputs.project(a, foreign, decoded.trials[0]));
    const unversioned = try std.mem.replaceOwned(u8, a, serialized, "\"schema\":\"baseline-freeze/v1\",", "");
    try std.testing.expectError(error.InvalidJsonDocument, frozen_inputs.decode(a, unversioned));
    const wrong_version = try std.mem.replaceOwned(u8, a, serialized, "baseline-freeze/v1", "baseline-freeze/v2");
    try std.testing.expectError(error.InvalidJsonDocument, frozen_inputs.decode(a, wrong_version));
    var features: usize = 0;
    for (inventory.cases) |example| {
        if (example.partition != .development or example.variant != .base) continue;
        const projected = try frozen_inputs.project(a, decoded, try firstTrial(decoded, example.feature_id));
        try std.testing.expectEqualStrings(rubric_bytes, projected.captured.evaluation.rubric_bytes);
        try std.testing.expectEqualStrings(paths.rubric, projected.captured.evaluation.case.rubric);
        var config = try (@import("../../src/actions/config/decode_sddtoolkit_config.zig").Action{}).execute(a, projected.captured.config);
        defer config.deinit();
        const reference_root = try frozen_inputs.configuredRoot(a, frozen, .references, config.value().paths.references);
        const selected_reference_root = try std.fs.path.join(a, &.{ reference_root.relative_path, projected.selected.reference });
        var references: usize = 0;
        for (projected.captured.files) |file| {
            if (@import("../../src/domain/relative_directory_path.zig").contains(selected_reference_root, file.mapping.destination)) {
                references += 1;
                var found = false;
                for (example.sources) |source| if (std.mem.eql(u8, file.bytes, source.text)) {
                    found = true;
                };
                try std.testing.expect(found);
            }
            try std.testing.expect(!std.mem.eql(u8, file.mapping.source, paths.cases));
            try std.testing.expect(!std.mem.eql(u8, file.mapping.source, projected.captured.evaluation.case_source));
            try std.testing.expect(!std.mem.eql(u8, file.mapping.source, projected.captured.evaluation.case.rubric));
            try std.testing.expect(!std.mem.eql(u8, file.bytes, rubric_bytes));
            for (inventory.cases) |holdout| if (holdout.partition == .qualification) for (holdout.sources) |source| {
                try std.testing.expect(std.mem.indexOf(u8, file.bytes, source.text) == null);
            };
        }
        try std.testing.expectEqual(example.sources.len, references);
        // Materialization receives only the source projection plus unchanged
        // production assets. Evaluator fields remain outside target files.
        var target = std.testing.tmpDir(.{});
        defer target.cleanup();
        try fixture.materialize(std.testing.io, target.dir, projected.captured);
        for (projected.captured.files) |file| {
            try std.testing.expectEqualStrings(file.bytes, try files.read(std.testing.io, a, target.dir, file.mapping.destination));
        }
        features += 1;
    }
    try std.testing.expectEqual(@as(usize, 8), features);
    for (inventory.cases) |example| if (example.partition == .qualification) {
        for (example.sources) |source| try std.testing.expect(std.mem.indexOf(u8, serialized, try std.json.Stringify.valueAlloc(a, source.text, .{})) == null);
    };
}

test "test.integration.baseline freezes explicit scored rubric and refuses evaluator inputs in generation files" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const frozen = try prepare(a);
    const template_bytes = try files.read(std.testing.io, a, .cwd(), paths.template_case);
    const protocol_bytes = try files.read(std.testing.io, a, .cwd(), paths.protocol);
    const inventory_bytes = try files.read(std.testing.io, a, .cwd(), paths.cases);
    const rubric_bytes = frozen.inputs.evaluation.rubric_bytes;
    const unscored = try std.mem.replaceOwned(u8, a, rubric_bytes, "\"pass_threshold_percent\": 100", "\"pass_threshold_percent\": null");
    try std.testing.expectError(error.UnscoredBaselineRubric, frozen_inputs.create(a, build, protocol_bytes, inventory_bytes, template_bytes, unscored, frozen.inputs, paths, frozen.path_policy));
    var changed = frozen;
    changed.rubric_sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    try std.testing.expectError(error.InvalidBaselineFreeze, frozen_inputs.decode(a, try std.json.Stringify.valueAlloc(a, changed, .{})));
    try std.testing.expectError(error.FixtureChanged, frozen_inputs.verifySources(std.testing.io, a, .cwd(), changed));
    const files_with_rubric = try a.alloc(fixture.CapturedFile, frozen.inputs.files.len + 1);
    @memcpy(files_with_rubric[0..frozen.inputs.files.len], frozen.inputs.files);
    files_with_rubric[frozen.inputs.files.len] = .{ .mapping = .{ .source = paths.rubric, .destination = "reference-guidance/evaluator.json" }, .bytes = rubric_bytes };
    changed = frozen;
    changed.inputs.files = files_with_rubric;
    try std.testing.expectError(error.EvaluatorInputInProject, frozen_inputs.create(a, build, protocol_bytes, inventory_bytes, template_bytes, rubric_bytes, changed.inputs, paths, frozen.path_policy));
    try std.testing.expectError(error.EvaluatorInputInProject, frozen_inputs.project(a, changed, changed.trials[0]));
}

const Fault = enum { none, source_changed, response_capture_failed };
const Wire = struct {
    native: @import("../../src/bedrock_transport_test_fixture.zig").Wire = .{ .expected_json = true, .inference_body = response },
    parent: std.Io.Dir,
    facts: *acquisition.Facts,
    gate: *dispatch.Gate,
    source_destination: []const u8,
    fault: Fault,

    fn port(self: *Wire) transport.Port {
        return .{ .context = @ptrCast(self), .exchange_fn = exchange };
    }
    fn exchange(context: *transport.Context, a: std.mem.Allocator, request: transport.Request) transport.Error!transport.Response {
        const self: *Wire = @ptrCast(@alignCast(context));
        const io = std.testing.io;
        const run = self.parent.openDir(io, self.facts.directory.?, .{}) catch return error.Cancelled;
        defer run.close(io);
        switch (self.fault) {
            .none => {},
            .source_changed => {
                const project = run.openDir(io, "project", .{}) catch return error.Cancelled;
                defer project.close(io);
                project.writeFile(io, .{ .sub_path = self.source_destination, .data = "MOCK changed source after ingestion.\n" }) catch return error.Cancelled;
            },
            .response_capture_failed => run.createDirPath(io, "evidence/generation/call-000001/response.json") catch return error.Cancelled,
        }
        // A test-only explicit stop bounds this real invocation to its first
        // fake physical exchange without changing the frozen protocol limits.
        self.gate.stop(.operator_stop);
        return self.native.port().exchange(a, request);
    }
};

fn runTrial(a: std.mem.Allocator, parent: std.Io.Dir, frozen: frozen_inputs.Freeze, trial: comparison.Trial, fault: Fault, gate: *dispatch.Gate, facts: *acquisition.Facts) !usize {
    const projected = try frozen_inputs.project(a, frozen, trial);
    var config = try (@import("../../src/actions/config/decode_sddtoolkit_config.zig").Action{}).execute(a, projected.captured.config);
    defer config.deinit();
    const reference_root = try frozen_inputs.configuredRoot(a, frozen, .references, config.value().paths.references);
    const selected_reference_root = try std.fs.path.join(a, &.{ reference_root.relative_path, projected.selected.reference });
    const destination = for (projected.captured.files) |file| {
        if (@import("../../src/domain/relative_directory_path.zig").contains(selected_reference_root, file.mapping.destination)) break file.mapping.destination;
    } else return error.MissingBaselineSource;
    var wire: Wire = .{ .parent = parent, .facts = facts, .gate = gate, .source_destination = destination, .fault = fault };
    try acquisition.execute(std.testing.io, a, frozen, parent, key, gate, facts, wire.port());
    return wire.native.calls;
}

test "test.integration.baseline source-only native acquisition retains exact first exchanges from unrelated panel domains" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const frozen = try prepare(a);
    const freeze_sha256 = try frozen_inputs.hash(a, try std.json.Stringify.valueAlloc(a, frozen, .{}));
    var checked: usize = 0;
    for (frozen.sources) |example| {
        if (example.variant != .base or checked == 2) continue;
        var parent = std.testing.tmpDir(.{});
        defer parent.cleanup();
        const trial = try firstTrial(frozen, example.feature_id);
        var gate = try dispatch.Gate.init(.{ .maximum_sends = frozen.protocol.limits.maximum_sends, .maximum_actual_tokens = frozen.protocol.limits.maximum_actual_tokens });
        var facts: acquisition.Facts = .{ .trial = trial, .freeze_sha256 = freeze_sha256 };
        try std.testing.expectEqual(@as(usize, 1), try runTrial(a, parent.dir, frozen, trial, .none, &gate, &facts));
        try std.testing.expectEqual(@as(?u128, 12), gate.snapshot().total_actual_tokens);
        try std.testing.expectEqual(@as(usize, 1), facts.receipts.len);
        try std.testing.expectEqual(.initial_generation, facts.receipts[0].purpose);
        try std.testing.expectEqual(.reference_chunk, facts.receipts[0].owner_kind);
        try std.testing.expect(facts.published_output == null and facts.first_candidate == null and facts.final_candidate == null);
        try std.testing.expectEqual(.not_run, facts.workflow.?.semantic_quality);
        const run = try parent.dir.openDir(std.testing.io, facts.directory.?, .{});
        defer run.close(std.testing.io);
        const raw = try files.read(std.testing.io, a, run, "evidence/generation/call-000001/response.json");
        try std.testing.expectEqualStrings(response, raw);
        const context = try @import("../harness/e2e/call_context.zig").CallContext.decode(a, try files.read(std.testing.io, a, run, "evidence/generation/call-000001/context.json"));
        try std.testing.expectEqualDeep(facts.receipts[0].origin, context.origin);
        try std.testing.expectEqualStrings("openai.gpt-oss-20b-1:0", context.model);
        try std.testing.expectEqualStrings("low", context.reasoning_effort.?);
        try std.testing.expectEqual(.native_schema, context.response_mode);
        var lines = std.mem.tokenizeScalar(u8, example.sources[0].text, '\n');
        const first_requirement = while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "- ")) break line;
        } else return error.MissingBaselineSourceRequirement;
        const quoted = try std.json.Stringify.valueAlloc(a, first_requirement, .{});
        var source_visible = false;
        for (context.content) |content| if (std.mem.indexOf(u8, content.bytes(), first_requirement) != null or
            std.mem.indexOf(u8, content.bytes(), quoted[1 .. quoted.len - 1]) != null)
        {
            source_visible = true;
        };
        try std.testing.expect(source_visible);
        const records = try a.alloc(acquisition.Record, frozen.trials.len);
        for (records, frozen.trials) |*record, planned| record.* = try acquisition.record(a, if (planned.ordinal == trial.ordinal) facts else .{ .trial = planned, .freeze_sha256 = freeze_sha256 });
        const experiment = @import("../harness/baseline/experiment.zig");
        const claim: experiment.Claim = .{ .schema = .@"baseline-experiment-claim/v1", .experiment_sha256 = try frozen_inputs.experimentHash(a, frozen), .freeze_sha256 = freeze_sha256, .execution_id = "offline-partial-panel", .limits = gate.snapshot().limits, .phases = &.{.baseline} };
        try experiment.consume(std.testing.io, a, parent.dir, claim);
        try experiment.verify(std.testing.io, a, parent.dir, claim);
        const report: acquisition.Report = .{ .schema = .@"baseline-acquisition/v2", .freeze_sha256 = freeze_sha256, .build = frozen.build, .toolchain = frozen.toolchain, .execution_id = "offline-partial-panel", .experiment_claim = claim, .budget = gate.snapshot(), .allowance = try experiment.remaining(a, claim.phases, gate.snapshot()), .records = records, .complete = false };
        const unversioned = try std.mem.replaceOwned(u8, a, try std.json.Stringify.valueAlloc(a, report, .{}), "\"schema\":\"baseline-acquisition/v2\",", "");
        try std.testing.expectError(error.InvalidJsonDocument, acquisition.decode(a, unversioned, frozen, freeze_sha256));
        const old_version = try std.mem.replaceOwned(u8, a, try std.json.Stringify.valueAlloc(a, report, .{}), "baseline-acquisition/v2", "baseline-acquisition/v1");
        try std.testing.expectError(error.InvalidJsonDocument, acquisition.decode(a, old_version, frozen, freeze_sha256));
        _ = try acquisition.decode(a, try std.json.Stringify.valueAlloc(a, report, .{}), frozen, freeze_sha256);
        // Rehashing a changed receipt cannot make it match native evidence.
        const changed = try a.dupe(acquisition.Record, records);
        const index = trial.ordinal - 1;
        const receipts = try a.dupe(@import("../harness/e2e/trace.zig").Receipt, changed[index].facts.receipts);
        receipts[0].origin.request.value += 1;
        var foreign = changed[index].facts;
        foreign.receipts = receipts;
        changed[index] = try acquisition.record(a, foreign);
        var corrupted = report;
        corrupted.records = changed;
        try std.testing.expectError(error.AcquisitionMismatch, acquisition.decode(a, try std.json.Stringify.valueAlloc(a, corrupted, .{}), frozen, freeze_sha256));
        corrupted = report;
        corrupted.budget.physical_sends = 0;
        try std.testing.expectError(error.AcquisitionMismatch, acquisition.decode(a, try std.json.Stringify.valueAlloc(a, corrupted, .{}), frozen, freeze_sha256));
        corrupted = report;
        corrupted.allowance.unspent_physical_sends += 1;
        try std.testing.expectError(error.AcquisitionMismatch, acquisition.decode(a, try std.json.Stringify.valueAlloc(a, corrupted, .{}), frozen, freeze_sha256));
        var restart = claim;
        restart.execution_id = "unapproved-restart";
        const reformatted = try std.json.Stringify.valueAlloc(a, frozen, .{ .whitespace = .indent_2 });
        const same_freeze = try frozen_inputs.decode(a, reformatted);
        restart.freeze_sha256 = try frozen_inputs.hash(a, reformatted);
        restart.experiment_sha256 = try frozen_inputs.experimentHash(a, same_freeze);
        try std.testing.expect(!std.mem.eql(u8, restart.freeze_sha256, claim.freeze_sha256));
        try std.testing.expectEqualStrings(claim.experiment_sha256, restart.experiment_sha256);
        try std.testing.expectError(error.BaselineAlreadyClaimed, experiment.consume(std.testing.io, a, parent.dir, restart));
        checked += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), checked);
}

test "test.integration.baseline detects frozen source and configuration drift without substituting settings" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const frozen = try prepare(a);
    var changed = frozen;
    changed.inputs.config = try std.mem.replaceOwned(u8, a, frozen.inputs.config, "\"reasoningEffort\": \"low\"", "\"reasoningEffort\": \"medium\"");
    try std.testing.expectError(error.InvalidBaselineFreeze, frozen_inputs.verifySources(std.testing.io, a, .cwd(), changed));
    var parent = std.testing.tmpDir(.{});
    defer parent.cleanup();
    var gate = try dispatch.Gate.init(.{ .maximum_sends = frozen.protocol.limits.maximum_sends, .maximum_actual_tokens = frozen.protocol.limits.maximum_actual_tokens });
    var facts: acquisition.Facts = .{ .trial = frozen.trials[0], .freeze_sha256 = try frozen_inputs.hash(a, try std.json.Stringify.valueAlloc(a, frozen, .{})) };
    try std.testing.expectEqual(@as(usize, 0), try runTrial(a, parent.dir, changed, frozen.trials[0], .none, &gate, &facts));
    try std.testing.expectEqual(@as(u64, 0), gate.snapshot().physical_sends);
    try std.testing.expectEqual(@as(?dispatch.Reason, .configuration_drift), gate.snapshot().halt_reason);
    try std.testing.expectEqual(@as(usize, 0), facts.receipts.len);
    try std.testing.expect(facts.published_output == null);
    var changed_build = frozen.build;
    changed_build.source_sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    try std.testing.expectError(error.BaselineBuildChanged, frozen_inputs.verifyBuild(frozen.build, changed_build));
}

test "test.integration.baseline source mutation and response capture failure preserve failed evidence without success" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const frozen = try prepare(a);
    for ([_]Fault{ .source_changed, .response_capture_failed }) |fault| {
        var parent = std.testing.tmpDir(.{});
        defer parent.cleanup();
        var gate = try dispatch.Gate.init(.{ .maximum_sends = frozen.protocol.limits.maximum_sends, .maximum_actual_tokens = frozen.protocol.limits.maximum_actual_tokens });
        var facts: acquisition.Facts = .{ .trial = frozen.trials[0], .freeze_sha256 = try frozen_inputs.hash(a, try std.json.Stringify.valueAlloc(a, frozen, .{})) };
        if (fault == .source_changed) {
            try std.testing.expectError(error.FixtureChanged, runTrial(a, parent.dir, frozen, frozen.trials[0], fault, &gate, &facts));
        } else {
            try std.testing.expectEqual(@as(usize, 1), try runTrial(a, parent.dir, frozen, frozen.trials[0], fault, &gate, &facts));
            try std.testing.expect(facts.workflow.?.evidence_error != null);
            try std.testing.expectEqual(.harness_error, facts.workflow.?.status);
            try std.testing.expect(facts.receipts[0].response_sha256 == null);
            try std.testing.expect(!facts.receipts[0].raw_response_available);
        }
        try std.testing.expectEqual(@as(u64, 1), gate.snapshot().physical_sends);
        try std.testing.expectEqual(@as(?u128, 12), gate.snapshot().total_actual_tokens);
        try std.testing.expect(facts.published_output == null);
        try std.testing.expectError(error.ExperimentHalted, gate.beforeSend());
    }
}
