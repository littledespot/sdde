//! A serial development experiment around the unchanged production invocation.
const std = @import("std");
const comparison = @import("../generation_comparison.zig");
const frozen_inputs = @import("freeze.zig");
const dispatch = @import("dispatch.zig");
const native = @import("../e2e/contracts.zig");
const trace = @import("../e2e/trace.zig");
const candidates = @import("candidates.zig");
const experiment = @import("experiment.zig");
const output = @import("../output.zig");
const strict = @import("../../../src/domain/strict_json.zig");
const json_limits: strict.Limits = .{ .maximum_depth = 128 };

pub const Facts = struct {
    trial: comparison.Trial,
    scope: enum { full_workflow } = .full_workflow,
    freeze_sha256: []const u8,
    directory: ?[]const u8 = null,
    inputs_sha256: ?[]const u8 = null,
    workflow: ?native.Report = null,
    receipts: []const trace.Receipt = &.{},
    first_candidate: ?candidates.Snapshot = null,
    final_candidate: ?candidates.Snapshot = null,
    review_findings: []const @import("reviews.zig").Finding = &.{},
    review_coverage: []const @import("reviews.zig").Coverage = &.{},
    published_output: ?[]const u8 = null,
    clarification_outputs: []const PublishedFile = &.{},
    elapsed_ns: ?u64 = null,
    diagnostic: ?[]const u8 = null,
};
/// Native invocation evidence is distinct from a dispatched comparison arm.
/// A retained native report can describe deterministic failure before any send;
/// a physical receipt also proves invocation when other capture is incomplete.
pub fn nativeInvocationObserved(facts: Facts) bool {
    return facts.workflow != null or facts.receipts.len != 0;
}

pub const PublishedFile = struct { path: []const u8, bytes: []const u8, sha256: []const u8 };
pub const Record = struct { sha256: []const u8, facts: Facts };
pub const Report = struct {
    schema: enum { @"baseline-acquisition/v6" },
    freeze_sha256: []const u8,
    build: @import("../../../build/provenance.zig").Identity,
    toolchain: frozen_inputs.Toolchain,
    scope: enum { full_workflow } = .full_workflow,
    predecessor_origin: enum { actual_production } = .actual_production,
    assessment: enum { not_run } = .not_run,
    execution_id: []const u8,
    experiment_claim: experiment.Claim,
    budget: dispatch.Snapshot,
    allowance: experiment.Allowance,
    /// Post-acquisition source verification is independent of the first
    /// transport stop (which may already be an exact send/token limit).
    source_error: ?[]const u8 = null,
    records: []const Record,
    complete: bool,
};

pub fn record(a: std.mem.Allocator, facts: Facts) !Record {
    return .{ .sha256 = try frozen_inputs.hash(a, try std.json.Stringify.valueAlloc(a, facts, .{})), .facts = facts };
}

pub fn acquire(io: std.Io, a: std.mem.Allocator, transient: std.mem.Allocator, frozen: frozen_inputs.Freeze, freeze_sha256: []const u8, run: @import("../e2e/run_directory.zig").Run, key: []const u8, build_bytes: []const u8, claim: experiment.Claim) !Report {
    try frozen_inputs.requireExecutable(a, frozen);
    try experiment.validate(claim, try frozen_inputs.experimentHash(a, frozen), freeze_sha256, &run.name, frozen.admission.frozen.feasibility.plan.phases, .{ .maximum_sends = frozen.protocol.limits.maximum_sends, .maximum_actual_tokens = frozen.protocol.limits.maximum_actual_tokens });
    var gate = try dispatch.Gate.init(.{ .maximum_sends = frozen.protocol.limits.maximum_sends, .maximum_actual_tokens = frozen.protocol.limits.maximum_actual_tokens });
    const secrets = [_][]const u8{key};
    const store: @import("../evidence.zig").Store = .{ .io = io, .allocator = a, .run = run.dir, .secrets = &secrets };
    if (try @import("../e2e/build_evidence.zig").save(store, build_bytes) != .captured) return error.IncompleteBuildCapture;
    try run.dir.createDirPath(io, "trials");
    var records: std.ArrayList(Record) = .empty;
    for (frozen.trials) |trial| {
        // Release native runtime/request temporaries after each workflow. Only
        // the closed acquisition facts survive for experiment serialization.
        var trial_arena: std.heap.ArenaAllocator = .init(transient);
        defer trial_arena.deinit();
        const trial_allocator = trial_arena.allocator();
        var facts: Facts = .{ .trial = trial, .freeze_sha256 = freeze_sha256 };
        if (gate.snapshot().halt_reason == null) {
            execute(io, trial_allocator, frozen, run.dir, key, &gate, &facts, null) catch |err| {
                facts.diagnostic = @errorName(err);
                gate.stop(if (err == error.FixtureChanged or err == error.FrozenBindingRejected) .configuration_drift else .evidence_failure);
            };
        }
        const retained = try strict.decode(Facts, a, try std.json.Stringify.valueAlloc(trial_allocator, facts, .{}), json_limits);
        try records.append(a, try record(a, retained));
    }
    const snapshot = gate.snapshot();
    var attempted: usize = 0;
    var evidence_complete = true;
    for (records.items) |item| if (item.facts.workflow != null and item.facts.receipts.len != 0) {
        attempted += 1;
    };
    for (records.items) |item| {
        if (item.facts.diagnostic != null) evidence_complete = false;
        if (item.facts.workflow) |result| if (result.evidence_error != null or result.status == .harness_error) {
            evidence_complete = false;
        };
    }
    return .{ .schema = .@"baseline-acquisition/v6", .freeze_sha256 = freeze_sha256, .build = frozen.build, .toolchain = frozen.toolchain, .execution_id = try a.dupe(u8, &run.name), .experiment_claim = claim, .budget = snapshot, .allowance = try experiment.remaining(a, claim.phases, snapshot), .records = try records.toOwnedSlice(a), .complete = panelComplete(frozen.trials.len, attempted, evidence_complete, snapshot, null) };
}

/// The replacement transport is only reachable from offline tests. Production
/// execution enforces its existing TestTransportForbidden check independently.
pub fn execute(io: std.Io, a: std.mem.Allocator, frozen: frozen_inputs.Freeze, parent: std.Io.Dir, key: []const u8, gate: *dispatch.Gate, facts: *Facts, transport: ?@import("../../../src/adapters/provider/bedrock_transport.zig").Port) !void {
    if (!@import("builtin").is_test) try frozen_inputs.requireExecutable(a, frozen);
    const project = try frozen_inputs.project(a, frozen, facts.trial);
    const trial_path = try std.fmt.allocPrint(a, "trials/{d:0>4}", .{facts.trial.ordinal});
    const trials = try @import("../../../src/adapters/filesystem/directory_access.zig").ensure(io, parent, trial_path);
    defer trials.close(io);
    const run = try @import("../e2e/run_directory.zig").Run.create(io, trials);
    defer run.close(io);
    facts.directory = try std.fs.path.join(a, &.{ trial_path, &run.name });
    const native_output = try @import("../e2e/report.zig").Output.reserve(io, run.dir);
    defer native_output.close(io);
    const case_bytes = try std.json.Stringify.valueAlloc(a, project.selected, .{});
    const input_bytes = try std.json.Stringify.valueAlloc(a, project.captured, .{});
    facts.inputs_sha256 = try frozen_inputs.hash(a, input_bytes);
    try output.write(io, run.dir, "case.json", case_bytes);
    try output.write(io, run.dir, "inputs.json", input_bytes);
    try @import("../e2e/fixture.zig").materialize(io, run.project, project.captured);
    const secrets = [_][]const u8{key};
    const store: @import("../evidence.zig").Store = .{ .io = io, .allocator = a, .run = run.dir, .secrets = &secrets };
    var captured: trace.CaptureLog = .init(a);
    defer captured.deinit();
    var report: native.Report = .{ .schema = .@"spec-e2e-report/v8", .started_at_utc = try a.dupe(u8, &run.started_at_utc), .execution_id = try a.dupe(u8, &run.name), .case_id = project.selected.id, .workflow_id = project.selected.workflow_id, .status = .input_invalid };
    const started: std.Io.Clock.Timestamp = .now(io, .awake);
    const published = @import("../e2e/invoke.zig").run(io, a, run.project, project.selected, project.captured, key, store, &report, .{ .purpose = .whole_workflow, .transport = transport, .experiment = gate, .capture = &captured }) catch |err| failed: {
        report.status = .harness_error;
        report.diagnostic = @errorName(err);
        gate.stop(.evidence_failure);
        break :failed null;
    };
    const duration = started.durationTo(.now(io, .awake)).raw.toNanoseconds();
    facts.elapsed_ns = std.math.cast(u64, duration) orelse return error.InvalidElapsedTime;
    try retainInvocation(io, a, facts, report, &captured, native_output);
    facts.published_output = published;
    if (report.workflow_outcome == .needs_user and report.publication_check == .passed) {
        const specification = report.specification orelse return error.MissingClarificationPublication;
        facts.published_output = try @import("../files.zig").read(io, a, run.project, specification);
        const forms = try a.alloc(PublishedFile, report.clarifications.len);
        for (report.clarifications, forms) |clarification, *form| {
            const path = clarification.path.project_relative;
            const bytes = try @import("../files.zig").read(io, a, run.project, path);
            form.* = .{ .path = path, .bytes = bytes, .sha256 = try frozen_inputs.hash(a, bytes) };
        }
        facts.clarification_outputs = forms;
    }
    if (report.evidence_error != null) gate.stop(.evidence_failure);
    // Frozen source inputs remain unchanged even if the workflow published its
    // own outputs. The template's evaluator labels are never copied to project.
    for (project.captured.files) |file| {
        const current = try @import("../files.zig").read(io, a, run.project, file.mapping.destination);
        if (!std.mem.eql(u8, current, file.bytes)) return error.FixtureChanged;
    }
}

fn retainInvocation(io: std.Io, a: std.mem.Allocator, facts: *Facts, report: native.Report, captured: *const trace.CaptureLog, native_output: @import("../e2e/report.zig").Output) !void {
    // Retain the native outcome before any fallible publication/candidate
    // capture. A later evidence failure cannot erase already charged calls.
    facts.workflow = report;
    // Copy before trace-owned receipt slices are released. The caller's arena
    // owns every record retained until final report serialization.
    facts.receipts = try @import("../contracts.zig").decode([]const trace.Receipt, a, try std.json.Stringify.valueAlloc(a, captured.records.items, .{}));
    facts.first_candidate = try @import("../contracts.zig").decode(?candidates.Snapshot, a, try std.json.Stringify.valueAlloc(a, captured.candidates.first, .{}));
    facts.final_candidate = try @import("../contracts.zig").decode(?candidates.Snapshot, a, try std.json.Stringify.valueAlloc(a, captured.candidates.latest, .{}));
    facts.review_findings = try @import("../contracts.zig").decode([]const @import("reviews.zig").Finding, a, try std.json.Stringify.valueAlloc(a, captured.reviews.findings.items, .{}));
    facts.review_coverage = try @import("../contracts.zig").decode([]const @import("reviews.zig").Coverage, a, try std.json.Stringify.valueAlloc(a, captured.reviews.coverage.items, .{}));
    // IO failure must not release the only copies of already charged exchanges.
    // The outer acquisition record retains these facts even when report saving
    // fails, then marks the experiment stopped with an evidence diagnostic.
    try native_output.save(io, a, report);
}

test "native report write failures preserve charged exchanges after trace ownership ends" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const usage = dispatch.ProviderUsage.init(10, 2, 12).?;
    const origin: @import("../../../src/domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    for ([_]enum { json, markdown }{ .json, .markdown }) |failure| {
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "readonly", .data = "" });
        const readonly = try temporary.dir.openFile(std.testing.io, "readonly", .{});
        defer readonly.close(std.testing.io);
        const writable = try temporary.dir.createFile(std.testing.io, "writable", .{ .exclusive = true });
        defer writable.close(std.testing.io);
        const sink: @import("../e2e/report.zig").Output = .{ .json = if (failure == .json) readonly else writable, .markdown = if (failure == .markdown) readonly else writable };
        var gate = try dispatch.Gate.init(.{ .maximum_sends = 10, .maximum_actual_tokens = 100 });
        const send = try gate.beforeSend();
        try gate.reconcile(send, usage, false);
        var captured: trace.CaptureLog = .init(a);
        try captured.records.append(a, .{ .call = 1, .origin = origin, .purpose = .initial_generation, .owner_kind = .reference_chunk, .experiment_send = send, .request_step = try a.dupe(u8, "native-model-call"), .context_sha256 = @splat(1), .request_sha256 = @splat(2), .usage = usage });
        var initial_digest: [32]u8 = undefined;
        var final_digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash("{}", &initial_digest, .{});
        std.crypto.hash.sha2.Sha256.hash("{\"corrected\":true}", &final_digest, .{});
        captured.candidates.first = .{ .json = try a.dupe(u8, "{}"), .sha256 = std.fmt.bytesToHex(initial_digest, .lower), .first_pass = true };
        captured.candidates.latest = .{ .json = try a.dupe(u8, "{\"corrected\":true}"), .sha256 = std.fmt.bytesToHex(final_digest, .lower), .first_pass = false };
        const attempts = [_]native.Attempt{.{ .origin = origin, .step = "native-model-call", .accounting = .exact_usage, .usage = usage }};
        const report: native.Report = .{ .schema = .@"spec-e2e-report/v8", .started_at_utc = "2026-10-16T00:00:00Z", .status = .workflow_cancelled, .workflow_outcome = .cancelled, .model_calls = 1, .total_tokens = 12, .attempts = &attempts };
        var facts: Facts = .{ .trial = .{ .ordinal = 1, .arm = .A, .case_id = "case", .feature_id = "feature", .repetition = 1 }, .freeze_sha256 = "freeze" };
        try std.testing.expectError(error.NotOpenForWriting, retainInvocation(std.testing.io, a, &facts, report, &captured, sink));
        captured.deinit();
        try std.testing.expectEqual(@as(usize, 1), facts.receipts.len);
        try std.testing.expectEqualStrings("native-model-call", facts.receipts[0].request_step);
        try std.testing.expectEqualDeep(origin, facts.receipts[0].origin);
        try std.testing.expectEqual(@as(?dispatch.ProviderUsage, usage), facts.receipts[0].usage);
        try std.testing.expectEqual(@as(u64, 12), facts.workflow.?.total_tokens);
        try std.testing.expectEqual(@as(u64, 1), gate.snapshot().physical_sends);
        try std.testing.expectEqual(@as(?u128, 12), gate.snapshot().total_actual_tokens);
        try std.testing.expectEqualStrings("{}", facts.first_candidate.?.json);
        try std.testing.expectEqualStrings("{\"corrected\":true}", facts.final_candidate.?.json);
        const copied = try strict.decode(Facts, a, try std.json.Stringify.valueAlloc(a, facts, .{}), json_limits);
        try std.testing.expectEqualSlices(u8, &facts.first_candidate.?.sha256, &copied.first_candidate.?.sha256);
        try std.testing.expectEqualSlices(u8, &facts.final_candidate.?.sha256, &copied.final_candidate.?.sha256);
        try std.testing.expectEqualSlices(u8, &facts.receipts[0].context_sha256, &copied.receipts[0].context_sha256);
    }
}

pub fn decode(a: std.mem.Allocator, bytes: []const u8, frozen: frozen_inputs.Freeze, freeze_sha256: []const u8) !Report {
    const value = try strict.decode(Report, a, bytes, json_limits);
    try frozen_inputs.verifyBuild(frozen.build, value.build);
    if (!std.mem.eql(u8, try std.json.Stringify.valueAlloc(a, value.toolchain, .{}), try std.json.Stringify.valueAlloc(a, frozen.toolchain, .{}))) return error.AcquisitionMismatch;
    if (!std.mem.eql(u8, value.freeze_sha256, freeze_sha256) or value.records.len != frozen.trials.len) return error.AcquisitionMismatch;
    const phases = if (frozen.admission == .frozen) frozen.admission.frozen.feasibility.plan.phases else &.{@import("feasibility.zig").Phase.baseline};
    experiment.validate(value.experiment_claim, try frozen_inputs.experimentHash(a, frozen), freeze_sha256, value.execution_id, phases, value.budget.limits) catch return error.AcquisitionMismatch;
    var gate = try dispatch.Gate.init(.{ .maximum_sends = frozen.protocol.limits.maximum_sends, .maximum_actual_tokens = frozen.protocol.limits.maximum_actual_tokens });
    var attempted: usize = 0;
    var evidence_complete = true;
    const external_stop = if (value.budget.halt_reason) |reason| switch (reason) {
        .configuration_drift, .evidence_failure, .scoring_disputed, .operator_stop => reason,
        .send_limit, .token_limit, .usage_unavailable, .uncertain_delivery => null,
    } else null;
    for (value.records, frozen.trials) |item, trial| {
        if (!std.mem.eql(u8, item.facts.freeze_sha256, freeze_sha256) or !std.mem.eql(u8, try frozen_inputs.hash(a, try std.json.Stringify.valueAlloc(a, item.facts, .{})), item.sha256) or
            item.facts.trial.ordinal != trial.ordinal or item.facts.trial.arm != trial.arm or item.facts.trial.repetition != trial.repetition or
            !std.mem.eql(u8, item.facts.trial.case_id, trial.case_id) or !std.mem.eql(u8, item.facts.trial.feature_id, trial.feature_id)) return error.AcquisitionMismatch;
        if (item.facts.directory) |directory| try @import("../contracts.zig").path(directory);
        const facts = item.facts;
        if (facts.diagnostic != null) evidence_complete = false;
        if (facts.workflow) |workflow_report| {
            if (facts.directory == null or facts.inputs_sha256 == null or facts.elapsed_ns == null) return error.AcquisitionMismatch;
            if (!validDigest(facts.inputs_sha256.?)) return error.AcquisitionMismatch;
            try validateNative(workflow_report, facts.receipts);
            if (workflow_report.evidence_error != null or workflow_report.status == .harness_error) evidence_complete = false;
            if (facts.receipts.len != 0) attempted += 1;
            if (facts.published_output != null and ((workflow_report.workflow_outcome != .ok and workflow_report.workflow_outcome != .needs_user) or
                workflow_report.publication_check != .passed or workflow_report.specification == null)) return error.AcquisitionMismatch;
            if (workflow_report.workflow_outcome == .needs_user and workflow_report.publication_check == .passed) {
                if (facts.diagnostic == null and (facts.published_output == null or facts.clarification_outputs.len != workflow_report.clarifications.len)) return error.AcquisitionMismatch;
                for (facts.clarification_outputs, 0..) |form, index| {
                    try @import("../contracts.zig").path(form.path);
                    if (!std.mem.eql(u8, form.sha256, try frozen_inputs.hash(a, form.bytes))) return error.AcquisitionMismatch;
                    var matches: usize = 0;
                    for (workflow_report.clarifications) |clarification| if (std.mem.eql(u8, form.path, clarification.path.project_relative)) {
                        matches += 1;
                    };
                    if (matches != 1) return error.AcquisitionMismatch;
                    for (facts.clarification_outputs[0..index]) |prior| if (std.mem.eql(u8, prior.path, form.path)) return error.AcquisitionMismatch;
                }
            } else if (facts.clarification_outputs.len != 0) return error.AcquisitionMismatch;
        } else if (facts.receipts.len != 0 or facts.first_candidate != null or facts.final_candidate != null or facts.published_output != null or facts.clarification_outputs.len != 0 or facts.review_findings.len != 0 or facts.review_coverage.len != 0) return error.AcquisitionMismatch;
        try validateReviews(facts);
        if ((facts.first_candidate == null) != (facts.final_candidate == null)) return error.AcquisitionMismatch;
        for ([_]?candidates.Snapshot{ facts.first_candidate, facts.final_candidate }) |candidate| if (candidate) |snapshot| {
            if (!std.mem.eql(u8, &snapshot.sha256, try frozen_inputs.hash(a, snapshot.json))) return error.AcquisitionMismatch;
        };
        for (facts.receipts, 0..) |receipt, index| {
            if (receipt.call != index + 1 or receipt.origin.kind != .inference or receipt.origin.request.value == 0 or
                receipt.origin.attempt.value == 0 or receipt.experiment_send == null or
                receipt.raw_response_available != (receipt.response_sha256 != null) or
                receipt.model_output_available != (receipt.model_output_sha256 != null) or
                (receipt.uncertain_delivery and receipt.status != null)) return error.AcquisitionMismatch;
            for (facts.receipts[0..index]) |prior| if (std.meta.eql(prior.origin, receipt.origin)) return error.AcquisitionMismatch;
            if (receipt.repair_origin) |previous| {
                if (receipt.purpose != .atomic_repair or previous.kind != .inference or previous.request.value == 0 or previous.attempt.value == 0) return error.AcquisitionMismatch;
                for (facts.receipts[0..index]) |prior| {
                    if (std.meta.eql(prior.origin, previous)) break;
                } else return error.AcquisitionMismatch;
            }
            if (receipt.mechanical_rejection) |rejection| switch (rejection) {
                .protocol => |proof| if (proof.call != receipt.call or !std.meta.eql(proof.origin, receipt.origin)) return error.AcquisitionMismatch,
                .provider => |proof| if (proof.call != receipt.call or proof.origin == null or !std.meta.eql(proof.origin.?, receipt.origin)) return error.AcquisitionMismatch,
            };
            const sent = gate.beforeSend() catch return error.AcquisitionMismatch;
            if (sent.ordinal != receipt.experiment_send.?.ordinal) return error.AcquisitionMismatch;
            // Explicit external stops may occur during the last physical send.
            // All preceding sends must remain permitted by native accounting.
            if (sent.ordinal == value.budget.physical_sends) if (external_stop) |reason| gate.stop(reason);
            gate.reconcile(sent, receipt.usage, receipt.uncertain_delivery) catch return error.AcquisitionMismatch;
        }
    }
    if (external_stop) |reason| gate.stop(reason);
    if (!std.meta.eql(gate.snapshot(), value.budget)) return error.AcquisitionMismatch;
    if (!std.mem.eql(u8, try std.json.Stringify.valueAlloc(a, value.allowance, .{}), try std.json.Stringify.valueAlloc(a, try experiment.remaining(a, phases, value.budget), .{}))) return error.AcquisitionMismatch;
    const complete = panelComplete(frozen.trials.len, attempted, evidence_complete, value.budget, value.source_error);
    if (value.complete != complete) return error.AcquisitionMismatch;
    return value;
}

fn panelComplete(planned: usize, attempted: usize, evidence_complete: bool, budget: dispatch.Snapshot, source_error: ?[]const u8) bool {
    const evidence_halted = if (budget.halt_reason) |reason| switch (reason) {
        .send_limit, .token_limit => false,
        .usage_unavailable, .uncertain_delivery, .configuration_drift, .evidence_failure, .scoring_disputed, .operator_stop => true,
    } else false;
    return attempted == planned and evidence_complete and source_error == null and budget.usage_complete and
        !budget.uncertain_delivery and !budget.overshot and !evidence_halted;
}

test "post-acquisition source failure prevents exact-limit completion without replacing the native stop" {
    var gate = try dispatch.Gate.init(.{ .maximum_sends = 1, .maximum_actual_tokens = 12 });
    try gate.reconcile(try gate.beforeSend(), @import("../../../src/domain/llm_provider_operation.zig").ProviderUsage.init(10, 2, 12).?, false);
    const snapshot = gate.snapshot();
    try std.testing.expect(panelComplete(1, 1, true, snapshot, null));
    try std.testing.expect(!panelComplete(1, 1, true, snapshot, "FixtureChanged"));
    try std.testing.expect(!panelComplete(2, 1, true, snapshot, null));
    try std.testing.expect(!panelComplete(1, 1, false, snapshot, null));
    try std.testing.expectEqualDeep(snapshot, gate.snapshot());
}

fn validateReviews(facts: Facts) !void {
    const authority = @import("../../../src/domain/required_authority.zig");
    for (facts.review_findings, 0..) |finding, index| {
        if (finding.ordinal == 0 or authority.policy(finding.requirement) == null) return error.AcquisitionMismatch;
        if (finding.kind == .principles and (finding.requirement.kind != .policy_predicate or finding.source_ids.len != 0 or finding.missing_obligation != null or finding.question != null or finding.authority_gap != null)) return error.AcquisitionMismatch;
        if (finding.kind == .source and finding.principle_citations.len != 0) return error.AcquisitionMismatch;
        if (finding.kind == .preservation) {
            const assigned = finding.comparison orelse return error.AcquisitionMismatch;
            if (assigned.omission_ordinal == 0 or assigned.view.id.ordinal != finding.ordinal or
                assigned.view.members.len != assigned.members.len or finding.principle_citations.len != 0 or
                finding.missing_obligation == null or finding.question != null or finding.authority_gap != null) return error.AcquisitionMismatch;
        } else if (finding.comparison != null) return error.AcquisitionMismatch;
        var receipt_matches: usize = 0;
        for (facts.receipts) |receipt| if (std.meta.eql(receipt.origin, finding.origin)) {
            if (receipt.purpose != .semantic_review and receipt.purpose != .atomic_repair) return error.AcquisitionMismatch;
            if (!receipt.model_output_available and facts.workflow.?.evidence_error == null) return error.AcquisitionMismatch;
            receipt_matches += 1;
        };
        if (receipt_matches != 1) return error.AcquisitionMismatch;
        for (facts.review_findings[0..index]) |prior| if (prior.ordinal == finding.ordinal and std.meta.eql(prior.origin, finding.origin)) return error.AcquisitionMismatch;
        var coverage_matches: usize = 0;
        for (facts.review_coverage) |coverage| if (std.meta.eql(coverage.origin, finding.origin)) {
            const purpose: @import("reviews.zig").Review = switch (finding.kind) {
                .source => .source,
                .principles => .principles,
                .preservation => .preservation,
            };
            if (coverage.review != purpose) return error.AcquisitionMismatch;
            coverage_matches += 1;
        };
        if (coverage_matches != 1) return error.AcquisitionMismatch;
    }
    for (facts.review_coverage, 0..) |coverage, index| {
        var receipt_matches: usize = 0;
        for (facts.receipts) |receipt| if (std.meta.eql(receipt.origin, coverage.origin)) {
            if (receipt.purpose != .semantic_review and receipt.purpose != .atomic_repair) return error.AcquisitionMismatch;
            receipt_matches += 1;
        };
        if (receipt_matches != 1) return error.AcquisitionMismatch;
        for (facts.review_coverage[0..index]) |prior| if (std.meta.eql(prior.origin, coverage.origin)) return error.AcquisitionMismatch;
        if (coverage.complete) {
            var count: u32 = 0;
            for (facts.review_findings) |finding| if (std.meta.eql(finding.origin, coverage.origin)) {
                count = std.math.add(u32, count, 1) catch return error.AcquisitionMismatch;
            };
            if (coverage.expected_findings != count or (count == 0 and coverage.review != .preservation)) return error.AcquisitionMismatch;
        }
    }
}

fn validDigest(bytes: []const u8) bool {
    if (bytes.len != 64) return false;
    for (bytes) |byte| if (!std.ascii.isDigit(byte) and (byte < 'a' or byte > 'f')) return false;
    return true;
}

fn validateNative(report: native.Report, receipts: []const trace.Receipt) !void {
    if (report.model_calls != report.attempts.len or report.semantic_quality != .not_run or report.evaluation != null) return error.AcquisitionMismatch;
    var tokens: u128 = 0;
    var usage_complete = true;
    var not_sent_operations: usize = 0;
    for (report.attempts, 0..) |attempt, index| {
        if ((attempt.accounting == .exact_usage) != (attempt.usage != null)) return error.AcquisitionMismatch;
        for (report.attempts[0..index]) |prior| if (std.meta.eql(prior.origin, attempt.origin)) return error.AcquisitionMismatch;
        if (attempt.accounting == .unavailable) usage_complete = false;
        if (attempt.accounting == .not_sent) not_sent_operations += 1;
        if (attempt.usage) |usage| {
            if (@import("../../../src/domain/llm_provider_operation.zig").ProviderUsage.init(usage.input_tokens, usage.output_tokens, usage.total_tokens) == null) return error.AcquisitionMismatch;
            tokens = std.math.add(u128, tokens, usage.total_tokens) catch return error.AcquisitionMismatch;
        }
        var found = false;
        for (receipts) |receipt| if (std.meta.eql(receipt.origin, attempt.origin)) {
            if (found or !std.meta.eql(receipt.usage, attempt.usage) or !std.mem.eql(u8, receipt.request_step, attempt.step)) return error.AcquisitionMismatch;
            found = true;
        };
        // Proven non-delivery may precede transport. An unavailable operation
        // without a physical receipt requires an observed capture failure.
        if (!found and !@import("../e2e/observation.zig").provenNotSent(attempt) and
            (attempt.usage != null or report.evidence_error == null)) return error.AcquisitionMismatch;
    }
    for (receipts) |receipt| {
        var matches: usize = 0;
        for (report.attempts) |attempt| if (std.meta.eql(receipt.origin, attempt.origin)) {
            matches += 1;
        };
        if (matches != 1) return error.AcquisitionMismatch;
    }
    if (tokens != report.total_tokens or usage_complete != report.usage_complete or not_sent_operations != report.not_sent_operations) return error.AcquisitionMismatch;
    if (report.last_model_origin) |origin| {
        var found = false;
        for (report.attempts) |attempt| if (std.meta.eql(attempt.origin, origin)) {
            if (!std.meta.eql(report.last_model_usage, attempt.usage)) return error.AcquisitionMismatch;
            found = true;
        };
        if (!found) return error.AcquisitionMismatch;
    } else if (report.last_model_usage != null or receipts.len != 0) return error.AcquisitionMismatch;
}

test "native advisory non-delivery needs no physical receipt and preserves the prior exchange" {
    const usage = dispatch.ProviderUsage.init(10, 2, 12).?;
    const origin: @import("../../../src/domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const unsent: @TypeOf(origin) = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const attempts = [_]native.Attempt{
        .{ .origin = origin, .step = "required-generation", .accounting = .exact_usage, .usage = usage },
        .{ .origin = unsent, .step = "advisory-review", .accounting = .not_sent, .usage = null },
    };
    const receipts = [_]trace.Receipt{.{ .call = 1, .origin = origin, .purpose = .initial_generation, .owner_kind = .reference_chunk, .experiment_send = null, .request_step = "required-generation", .context_sha256 = @splat(1), .request_sha256 = @splat(2), .usage = usage }};
    const report: native.Report = .{ .schema = .@"spec-e2e-report/v8", .started_at_utc = "2026-10-17T00:00:00Z", .status = .generated, .workflow_outcome = .ok, .model_calls = 2, .not_sent_operations = 1, .total_tokens = 12, .attempts = &attempts, .last_model_origin = origin, .last_model_usage = usage };
    try validateNative(report, &receipts);
    var wrong = report;
    wrong.not_sent_operations = 0;
    try std.testing.expectError(error.AcquisitionMismatch, validateNative(wrong, &receipts));
    wrong = report;
    wrong.last_model_origin = unsent;
    try std.testing.expectError(error.AcquisitionMismatch, validateNative(wrong, &receipts));
    var unproved = attempts;
    unproved[1].accounting = .unavailable;
    wrong = report;
    wrong.attempts = &unproved;
    wrong.not_sent_operations = 0;
    wrong.usage_complete = false;
    try std.testing.expectError(error.AcquisitionMismatch, validateNative(wrong, &receipts));
}
