//! Offline assessment of native acquisitions. No credential lookup, dispatch,
//! generation input construction from evaluator labels, or workflow authority.
const std = @import("std");
const comparison = @import("../generation_comparison.zig");
const assessment = @import("assessment.zig");
const acquisition = @import("acquisition.zig");
const frozen_inputs = @import("freeze.zig");
const files = @import("../files.zig");
const directories = @import("../../../src/adapters/filesystem/directory_access.zig");
const evidence = @import("../evidence.zig");
const native = @import("../e2e/contracts.zig");
const trace = @import("../e2e/trace.zig");
const operation = @import("../../../src/domain/llm_provider_operation.zig");
const build = @import("../../../build/provenance.zig");
const stages = @import("stages.zig");
const reviews = @import("reviews.zig");
const finding_metrics = @import("finding_accuracy.zig");
const final_metrics = @import("final_fidelity.zig");
const useful_metrics = @import("useful_completion.zig");
const experiment = @import("experiment.zig");
const qualification_budget = @import("qualification_budget.zig");
const phase2 = @import("phase2_decision.zig");
const upstream = @import("upstream.zig");
const admission = @import("admission.zig");

pub const StageResources = struct {
    stage: stages.Stage,
    physical_sends: u64 = 0,
    known_actual_tokens: u64 = 0,
    known_input_tokens: u64 = 0,
    known_output_tokens: u64 = 0,
    actual_tokens: ?u64 = 0,
    actual_input_tokens: ?u64 = 0,
    actual_output_tokens: ?u64 = 0,
    usage_complete: bool = true,
    send_share: ?f64 = null,
    /// Denominator covers known consumption only when usage is incomplete.
    known_accounted_token_share: ?f64 = null,
    actual_token_share: ?f64 = null,
};
pub const FeatureResources = struct { feature_id: []const u8, stages: []const StageResources };

pub const Row = struct {
    trial: comparison.Trial,
    acquisition_sha256: []const u8,
    evidence: assessment.Evidence,
    provenance: ?assessment.Provenance,
    supplied_assessment: ?assessment.Entry,
    native_status: ?native.Status,
    native_outcome: ?@import("../../../src/domain/workflow.zig").OutcomeTag,
    terminal_step: ?[]const u8,
    /// Chronological evidence only; this is not the supplied semantic cause.
    first_native_rejection: ?native.NativeRejection,
    diagnostic: ?[]const u8,
    initial_output_ids: []const []const u8,
    final_output_ids: []const []const u8,
    supplied_failure_stage: ?comparison.FailureStage,
    physical_sends: u32,
    usage: ?comparison.Usage,
    elapsed_ns: ?u64,
    native_invocation_elapsed_ns: ?u64,
    stage_resources: []const StageResources,
    finding_assessments: []const assessment.FindingResult,
    review_coverage: []const assessment.ReviewCoverage,
    final_current_fidelity: ?bool,
    published_output_assessment: useful_metrics.Evaluation,
    upstream_assessment: upstream.Assessment,
    admission_escape: admission.Metric,
};
pub const Qualification = struct {
    status: enum { incomplete, infeasible, infeasible_under_declared_cost_envelope, frozen },
    independent_features: ?u32 = null,
    feature_ids: []const []const u8 = &.{},
    case_ids: []const []const u8 = &.{},
    paired_workloads: ?u64 = null,
};
pub const AssessorPacket = struct {
    trial: comparison.Trial,
    source_case: comparison.Case,
    capture: assessment.Capture,
    native_directory: ?[]const u8,
    inputs_sha256: ?[]const u8,
    published_evaluation: ?useful_metrics.Target,
};
pub const AssessmentInputs = struct {
    schema: enum { @"baseline-assessment-inputs/v2" },
    purpose: enum { evaluator_only } = .evaluator_only,
    freeze_sha256: []const u8,
    acquisition_sha256: []const u8,
    inventory_sha256: []const u8,
    workflow_authority: bool = false,
    qualification_sources_exported: bool = false,
    trials: []const AssessorPacket,
};
pub const Report = struct {
    schema: enum { @"baseline-score/v3" },
    build: build.Identity,
    toolchain: frozen_inputs.Toolchain,
    freeze_sha256: []const u8,
    inventory_sha256: []const u8,
    acquisition_sha256: []const u8,
    assessments_sha256: []const u8,
    acquisition_scope: enum { full_workflow } = .full_workflow,
    predecessor_origin: enum { actual_production } = .actual_production,
    assessment_scope: enum { diagnostic_supplied_judgment } = .diagnostic_supplied_judgment,
    corrective_send_measure: enum { native_later_attempts_and_atomic_repair_purpose } = .native_later_attempts_and_atomic_repair_purpose,
    native_capture_complete: bool,
    acquisition_source_error: ?[]const u8,
    native_budget: @import("dispatch.zig").Snapshot,
    budget_feasibility_frozen: ?@import("feasibility.zig").Report,
    budget_visibility: enum { one_shot_baseline_with_reserved_future_phases } = .one_shot_baseline_with_reserved_future_phases,
    experiment_claim: experiment.Claim,
    experiment_allowance: experiment.Allowance,
    semantic_evidence_complete: bool,
    rows: []const Row,
    scorecard: comparison.Scorecard,
    qualification: Qualification,
    stage_resources: []const StageResources,
    finding_type_accuracy: finding_metrics.Report,
    correction_assisted_fidelity: final_metrics.Report,
    failure_attribution_complete: bool,
    qualification_scope_covered: bool,
    feature_stage_resources: []const FeatureResources,
    useful_completion: useful_metrics.Report,
    qualification_budget: qualification_budget.Report,
    phase2_decision: phase2.Report,
    failure_classes: []const phase2.FailureClass,
    original_upstream_evidence_complete: bool,
    admission_escape: admission.Summary,
};

pub fn command(io: std.Io, a: std.mem.Allocator, repository: std.Io.Dir, freeze_path: []const u8, cases_path: []const u8, acquisition_path: []const u8, assessments_path: []const u8, current_build: build.Identity) !bool {
    const freeze_bytes = try files.read(io, a, repository, freeze_path);
    const frozen = try frozen_inputs.decode(a, freeze_bytes);
    try frozen_inputs.verifyBuild(frozen.build, current_build);
    try frozen_inputs.verifySources(io, a, repository, frozen);
    const freeze_sha256 = try frozen_inputs.hash(a, freeze_bytes);
    const inventory_bytes = try files.read(io, a, repository, cases_path);
    if (!std.mem.eql(u8, try frozen_inputs.hash(a, inventory_bytes), frozen.inventory_sha256)) return error.BaselineInventoryChanged;
    const inventory = try comparison.parseInventory(a, inventory_bytes);
    const trials = try comparison.plan(a, inventory, frozen.protocol, .baseline);
    try sameTrials(trials, frozen.trials);
    const acquisition_bytes = try files.read(io, a, repository, acquisition_path);
    const acquired = try acquisition.decode(a, acquisition_bytes, frozen, freeze_sha256);
    try experiment.verify(io, a, repository, acquired.experiment_claim);
    const assessment_bytes = try files.read(io, a, repository, assessments_path);
    const supplied = try assessment.parse(a, assessment_bytes);
    const parent_path = std.fs.path.dirname(acquisition_path);
    const parent = if (parent_path) |path| try directories.open(io, repository, path) else repository;
    defer if (parent_path != null) parent.close(io);
    const captures = try a.alloc(assessment.Capture, acquired.records.len);
    const rows = try a.alloc(Row, acquired.records.len);
    const observations = try a.alloc(comparison.Observation, acquired.records.len);
    const packets = try a.alloc(AssessorPacket, acquired.records.len);
    const finding_workloads = try a.alloc(finding_metrics.Workload, acquired.records.len);
    const final_workloads = try a.alloc(final_metrics.Workload, acquired.records.len);
    const useful_workloads = try a.alloc(useful_metrics.Workload, acquired.records.len);
    const upstream_workloads = try a.alloc(phase2.UpstreamWorkload, acquired.records.len);
    const admission_workloads = try a.alloc(admission.Workload, acquired.records.len);
    var complete = true;
    var original_upstream_complete = true;
    for (acquired.records, captures) |record, *capture| {
        const raw_outputs = try verifyRecord(io, a, parent, frozen, record);
        capture.* = try projectCapture(a, record, raw_outputs);
        capture.project_documents = try projectDocuments(a, frozen, record.facts.trial);
    }
    try assessment.validateAssociations(supplied, captures);
    var attribution_complete = true;
    for (acquired.records, captures, rows, observations, packets, finding_workloads, final_workloads, useful_workloads, upstream_workloads, admission_workloads) |record, capture, *row, *observation, *packet, *finding_workload, *final_workload, *useful_workload, *upstream_workload, *admission_workload| {
        const example = try caseFor(inventory, record.facts.trial.case_id);
        if (example.partition != .development) return error.AcquisitionMismatch;
        const published_target = if (example.expected_terminal == .completed) try publishedTarget(a, frozen, record, capture) else null;
        packet.* = .{ .trial = record.facts.trial, .source_case = example, .capture = capture, .native_directory = record.facts.directory, .inputs_sha256 = record.facts.inputs_sha256, .published_evaluation = published_target };
        const entry = assessment.entryFor(supplied, record.facts.trial.ordinal);
        const result = try assessment.evaluate(a, example, capture, entry);
        if (!result.upstream.original_evidence_complete) {
            complete = false;
            original_upstream_complete = false;
        }
        upstream_workload.* = .{ .trial_ordinal = record.facts.trial.ordinal, .results = result.upstream.results };
        const published_assessment = try useful_metrics.evaluate(a, capture.status != .unattempted, capture.published and example.expected_terminal == .completed, result.final_current_fidelity, published_target, if (entry) |value| value.published_rubric else null);
        if (!published_assessment.evidence_complete) complete = false;
        useful_workload.* = try usefulWorkload(record.facts, example, published_assessment);
        // All projected labels live in the command's arena through serialization.
        observation.* = result.observation;
        if (result.evidence != .complete) complete = false;
        finding_workload.* = .{ .findings = result.findings, .coverage = capture.review_coverage };
        final_workload.* = .{ .feature_id = record.facts.trial.feature_id, .well_posed = example.expected_terminal == .completed, .attempted = capture.status != .unattempted, .final_fidelity = result.final_current_fidelity };
        if (!attributionComplete(example, result.observation)) attribution_complete = false;
        const workflow = record.facts.workflow;
        const admission_metric = try admissionMetric(a, record.facts);
        admission_workload.* = .{ .attempted = acquisition.nativeInvocationObserved(record.facts), .metric = admission_metric };
        row.* = .{
            .trial = record.facts.trial,
            .acquisition_sha256 = record.sha256,
            .evidence = result.evidence,
            .provenance = result.provenance,
            .supplied_assessment = assessment.entryFor(supplied, record.facts.trial.ordinal),
            .native_status = if (workflow) |value| value.status else null,
            .native_outcome = if (workflow) |value| value.workflow_outcome else null,
            .terminal_step = if (workflow) |value| value.terminal_step else null,
            .first_native_rejection = if (workflow) |value| value.first_native_rejection else null,
            .diagnostic = record.facts.diagnostic orelse if (workflow) |value| value.diagnostic else null,
            .initial_output_ids = capture.initial_output_ids,
            .final_output_ids = capture.final_output_ids,
            .supplied_failure_stage = observation.failure_stage,
            .physical_sends = observation.physical_sends,
            .usage = observation.usage,
            .elapsed_ns = observation.elapsed_ns,
            .native_invocation_elapsed_ns = record.facts.elapsed_ns,
            .stage_resources = try resourceStages(a, record.facts.receipts),
            .finding_assessments = result.findings,
            .review_coverage = capture.review_coverage,
            .final_current_fidelity = result.final_current_fidelity,
            .published_output_assessment = published_assessment,
            .upstream_assessment = result.upstream,
            .admission_escape = admission_metric,
        };
    }
    const admission_summary = try admission.summarize(admission_workloads);
    if (!admission_summary.evidence_complete) complete = false;
    const finding_accuracy = try finding_metrics.summarize(a, finding_workloads);
    if (finding_accuracy.status != .complete) complete = false;
    const final_fidelity = try final_metrics.summarize(a, final_workloads);
    if (!final_fidelity.evidence_complete) complete = false;
    const scorecard = try comparison.aggregate(a, inventory, frozen.protocol, .baseline, trials, observations, .diagnostic);
    const useful_completion = try useful_metrics.summarize(a, useful_workloads);
    if (!useful_completion.completion.evidence_complete or !useful_completion.rubric_evidence_complete) complete = false;
    var qualification_scope = false;
    if (frozen.admission == .frozen) {
        for (frozen.admission.frozen.feasibility.plan.phases) |phase| if (phase == .qualification) {
            qualification_scope = true;
        };
    }
    const qualification_cost = try qualification_budget.evaluate(a, frozen.protocol, if (frozen.admission == .frozen) frozen.admission.frozen.feasibility.plan.phases else &.{}, acquired.budget, scorecard.baseline.?.qualification.required_features, observations);
    var selected = try selectQualification(a, inventory, scorecard, complete and acquired.complete and qualification_scope and attribution_complete and qualification_cost.status == .fits);
    if (qualification_cost.status == .exceeds and complete and acquired.complete and attribution_complete and qualification_scope) selected = .{ .status = .infeasible_under_declared_cost_envelope, .independent_features = scorecard.baseline.?.qualification.required_features, .paired_workloads = scorecard.baseline.?.qualification.paired_workloads };
    const failure_classes = try phase2.failureClasses(a, inventory, trials, observations, upstream_workloads);
    const decision = phase2.decide(frozen.protocol, scorecard.baseline, .{
        .native_capture_complete = acquired.complete,
        .admission_audit_complete = admission_summary.evidence_complete,
        .admission_escapes = admission_summary.escaped_values,
        .semantic_evidence_complete = complete,
        .upstream_evidence_complete = original_upstream_complete,
        .finding_accuracy_complete = finding_accuracy.status == .complete,
        .failure_attribution_complete = attribution_complete,
        .useful_completion_complete = useful_completion.completion.evidence_complete and useful_completion.rubric_evidence_complete,
        .useful_completion_rate = useful_completion.completion.rate,
        .qualification = switch (selected.status) {
            .incomplete => .incomplete,
            .infeasible, .infeasible_under_declared_cost_envelope => .infeasible,
            .frozen => .frozen,
        },
        .qualification_budget = switch (qualification_cost.status) {
            .incomplete => .incomplete,
            .fits => .fits,
            .exceeds => .exceeds,
            .outside_declared_scope => .outside_declared_scope,
        },
    }, failure_classes);
    const report: Report = .{
        .schema = .@"baseline-score/v3",
        .build = frozen.build,
        .toolchain = frozen.toolchain,
        .freeze_sha256 = freeze_sha256,
        .inventory_sha256 = frozen.inventory_sha256,
        .acquisition_sha256 = try frozen_inputs.hash(a, acquisition_bytes),
        .assessments_sha256 = try frozen_inputs.hash(a, assessment_bytes),
        .semantic_evidence_complete = complete,
        .native_capture_complete = acquired.complete,
        .acquisition_source_error = acquired.source_error,
        .native_budget = acquired.budget,
        .experiment_claim = acquired.experiment_claim,
        .experiment_allowance = acquired.allowance,
        .budget_feasibility_frozen = if (frozen.admission == .frozen) frozen.admission.frozen.feasibility else null,
        .rows = rows,
        .scorecard = scorecard,
        .qualification = selected,
        .stage_resources = try combineStages(a, rows),
        .finding_type_accuracy = finding_accuracy,
        .correction_assisted_fidelity = final_fidelity,
        .failure_attribution_complete = attribution_complete,
        .qualification_scope_covered = qualification_scope,
        .feature_stage_resources = try featureResources(a, rows),
        .useful_completion = useful_completion,
        .qualification_budget = qualification_cost,
        .phase2_decision = decision,
        .failure_classes = failure_classes,
        .original_upstream_evidence_complete = original_upstream_complete,
        .admission_escape = admission_summary,
    };
    const output_parent = try directories.ensure(io, repository, @import("cli.zig").output_root);
    defer output_parent.close(io);
    const run = try @import("../e2e/run_directory.zig").Run.create(io, output_parent);
    defer run.close(io);
    const assessor_inputs: AssessmentInputs = .{ .schema = .@"baseline-assessment-inputs/v2", .freeze_sha256 = report.freeze_sha256, .acquisition_sha256 = report.acquisition_sha256, .inventory_sha256 = report.inventory_sha256, .trials = packets };
    try @import("../output.zig").write(io, run.dir, "assessment-inputs.json", try std.json.Stringify.valueAlloc(a, assessor_inputs, .{ .whitespace = .indent_2 }));
    try @import("../output.zig").write(io, run.dir, "score.json", try std.json.Stringify.valueAlloc(a, report, .{ .whitespace = .indent_2 }));
    try @import("../output.zig").write(io, run.dir, "report.md", try render(a, report));
    try std.Io.File.stdout().writeStreamingAll(io, try std.fmt.allocPrint(a, "Baseline score: {s}/{s}/score.json\nSemantic evidence complete: {}; qualification: {s}. No inference or workflow continuation performed.\n", .{ @import("cli.zig").output_root, &run.name, complete, @tagName(report.qualification.status) }));
    return complete and acquired.complete and attribution_complete and !scorecard.inconclusive and decision.decision != .inconclusive;
}

fn attributionComplete(example: comparison.Case, observation: comparison.Observation) bool {
    if (observation.status == .unattempted) return true;
    var loss = observation.scoring_disputed or comparison.initialOutcome(example, observation) != .semantic_success;
    loss = loss or (observation.initial.status != .completed and observation.initial.status != .clarification) or
        (observation.status != .completed and observation.status != .clarification) or
        ((example.expected_terminal == .completed) != (observation.status == .completed));
    loss = loss or (example.expected_terminal == .clarification and observation.status == .clarification and !observation.questions_correct);
    for (observation.initial.duties) |duty| if (!duty.preserved) {
        loss = true;
    };
    for (observation.duties) |duty| if (!duty.preserved) {
        loss = true;
    };
    inline for (std.meta.fields(comparison.Issues)) |field| if (@field(observation.issues, field.name) != 0) {
        loss = true;
    };
    if (!loss) return true;
    return observation.failure_stage != null and observation.failure_stage.? != .unknown;
}

fn publishedTarget(a: std.mem.Allocator, frozen: frozen_inputs.Freeze, record: acquisition.Record, capture: assessment.Capture) !?useful_metrics.Target {
    if (!capture.published) return null;
    const workflow = record.facts.workflow orelse return error.CaptureMismatch;
    const publication = record.facts.published_output orelse return error.CaptureMismatch;
    if (capture.final_output_ids.len != 1) return error.CaptureMismatch;
    const output = for (capture.outputs) |value| {
        if (std.mem.eql(u8, value.id, capture.final_output_ids[0])) break value;
    } else return error.CaptureMismatch;
    if (!std.mem.eql(u8, output.text, publication)) return error.CaptureMismatch;
    const project = try frozen_inputs.project(a, frozen, record.facts.trial);
    const evaluation = try @import("../e2e/evaluation.zig").inputs(a, workflow, project.captured.evaluation, publication, workflow.execution_id orelse return error.CaptureMismatch);
    return .{ .output_id = output.id, .output_sha256 = output.sha256, .rubric_sha256 = try frozen_inputs.hash(a, evaluation.rubric_bytes), .capture = evaluation };
}
fn usefulWorkload(facts: acquisition.Facts, example: comparison.Case, evaluation: useful_metrics.Evaluation) !useful_metrics.Workload {
    var input: u64 = 0;
    var output: u64 = 0;
    var complete = true;
    for (facts.receipts) |receipt| {
        if (receipt.usage) |usage| {
            input = try std.math.add(u64, input, usage.input_tokens);
            output = try std.math.add(u64, output, usage.output_tokens);
        } else complete = false;
    }
    return .{ .feature_id = example.feature_id, .well_posed = example.expected_terminal == .completed, .attempted = facts.receipts.len != 0, .evaluation = evaluation, .physical_sends = facts.receipts.len, .known_input_tokens = input, .known_output_tokens = output, .usage_complete = complete, .elapsed_ns = if (facts.receipts.len != 0) facts.elapsed_ns else null };
}

fn sameTrials(actual: []const comparison.Trial, expected: []const comparison.Trial) !void {
    if (actual.len != expected.len) return error.AcquisitionMismatch;
    for (actual, expected) |left, right| {
        if (left.ordinal != right.ordinal or left.arm != right.arm or left.repetition != right.repetition or
            !std.mem.eql(u8, left.case_id, right.case_id) or !std.mem.eql(u8, left.feature_id, right.feature_id)) return error.AcquisitionMismatch;
    }
}
fn caseFor(inventory: comparison.Inventory, id: []const u8) !comparison.Case {
    for (inventory.cases) |example| if (std.mem.eql(u8, example.id, id)) return example;
    return error.AcquisitionMismatch;
}
fn verifyBytes(expected: [32]u8, bytes: []const u8) !void {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    if (!std.mem.eql(u8, &hash, &expected)) return error.CaptureMismatch;
}
fn sameJson(comptime T: type, a: std.mem.Allocator, expected: T, bytes: []const u8) !void {
    const current = if (T == native.Report)
        try @import("../../../src/domain/strict_json.zig").decode(T, a, bytes, .{ .maximum_depth = 128 })
    else
        try @import("../contracts.zig").decode(T, a, bytes);
    if (!std.mem.eql(u8, try std.json.Stringify.valueAlloc(a, expected, .{}), try std.json.Stringify.valueAlloc(a, current, .{}))) return error.CaptureMismatch;
}

/// Verify disk material independently of assessor labels. The retained native
/// prompt archive joins request/context identity; receipt hashes bind bytes at
/// the original transport observation. No replay response becomes an origin.
fn verifyRecord(io: std.Io, a: std.mem.Allocator, parent: std.Io.Dir, frozen: frozen_inputs.Freeze, record: acquisition.Record) ![]const assessment.Output {
    const facts = record.facts;
    // Setup may fail between reserving the directory and materializing inputs.
    // No generation occurred, so retain its diagnostic without certifying any
    // partial files. Any native exchange/candidate still requires full readback.
    if (try invocationUnstarted(facts)) return &.{};
    if (facts.directory == null) {
        if (facts.inputs_sha256 != null or facts.workflow != null or facts.receipts.len != 0 or facts.first_candidate != null or facts.final_candidate != null or facts.published_output != null or facts.clarification_outputs.len != 0 or facts.elapsed_ns != null) return error.AcquisitionMismatch;
        return &.{};
    }
    const run_path = facts.directory.?;
    const run = try directories.open(io, parent, run_path);
    defer run.close(io);
    const project = try frozen_inputs.project(a, frozen, facts.trial);
    try sameJson(@import("../e2e/contracts.zig").Case, a, project.selected, try files.read(io, a, run, "case.json"));
    const native_inputs = try files.read(io, a, run, "inputs.json");
    const input_sha = facts.inputs_sha256 orelse return error.AcquisitionMismatch;
    if (!std.mem.eql(u8, try frozen_inputs.hash(a, native_inputs), input_sha) or
        !std.mem.eql(u8, try frozen_inputs.hash(a, try std.json.Stringify.valueAlloc(a, project.captured, .{})), input_sha)) return error.BaselineInputsChanged;
    try sameJson(@import("../e2e/fixture.zig").Capture, a, project.captured, native_inputs);
    const target = try directories.open(io, run, "project");
    defer target.close(io);
    if (!std.mem.eql(u8, try files.read(io, a, target, ".sddtoolkit.json"), project.captured.config)) return error.BaselineInputsChanged;
    for (project.captured.files) |file| {
        if (!std.mem.eql(u8, try files.read(io, a, target, file.mapping.destination), file.bytes)) return error.BaselineInputsChanged;
    }
    const workflow = facts.workflow orelse {
        if (facts.receipts.len != 0) return error.AcquisitionMismatch;
        return &.{};
    };
    var expected_config = try (@import("../../../src/actions/config/decode_sddtoolkit_config.zig").Action{}).execute(a, project.captured.config);
    defer expected_config.deinit();
    if (workflow.admission_audit) |audit| for (audit.sources) |source| {
        try @import("../contracts.zig").path(source.path);
        const reference_root = (try frozen_inputs.configuredRoot(a, frozen, .references, expected_config.value().paths.references)).relative_path;
        const original_path = try std.fs.path.join(a, &.{ reference_root, project.selected.reference, source.path });
        const original = for (project.captured.files) |file| {
            if (std.mem.eql(u8, original_path, file.mapping.destination)) break file.bytes;
        } else return error.CaptureMismatch;
        if (!std.mem.eql(u8, source.bytes, original)) return error.CaptureMismatch;
    };
    try sameJson(native.Report, a, workflow, try files.read(io, a, run, "report.json"));
    if (workflow.case_id == null or !std.mem.eql(u8, workflow.case_id.?, facts.trial.case_id) or workflow.workflow_id == null or
        !std.mem.eql(u8, workflow.workflow_id.?, project.selected.workflow_id)) return error.AcquisitionMismatch;
    if (facts.published_output) |published| {
        if (workflow.publication_check != .passed or workflow.specification == null) return error.AcquisitionMismatch;
        if (!std.mem.eql(u8, published, try files.read(io, a, target, workflow.specification.?))) return error.CaptureMismatch;
    }
    if (facts.clarification_outputs.len != 0) {
        if (workflow.workflow_outcome != .needs_user or workflow.publication_check != .passed or (workflow.clarifications.len != facts.clarification_outputs.len and facts.diagnostic == null)) return error.AcquisitionMismatch;
        for (facts.clarification_outputs, 0..) |form, index| {
            for (facts.clarification_outputs[0..index]) |prior| if (std.mem.eql(u8, prior.path, form.path)) return error.AcquisitionMismatch;
            for (workflow.clarifications) |clarification| {
                if (std.mem.eql(u8, clarification.path.project_relative, form.path)) break;
            } else return error.AcquisitionMismatch;
            if (!std.mem.eql(u8, try frozen_inputs.hash(a, form.bytes), form.sha256) or
                !std.mem.eql(u8, form.bytes, try files.read(io, a, target, form.path))) return error.CaptureMismatch;
        }
    } else if (workflow.workflow_outcome == .needs_user and workflow.publication_check == .passed and workflow.clarifications.len != 0 and facts.diagnostic == null) return error.AcquisitionMismatch;
    // Every operation is checked against its actual frozen model slot. The
    // selected generation allowance cannot stand in for a different role's
    // configured controls, including a deliberately absent provider allowance.
    var outputs: std.ArrayList(assessment.Output) = .empty;
    for (facts.receipts, 0..) |receipt, index| {
        if (receipt.call != index + 1) return error.AcquisitionMismatch;
        const ordinal = std.math.cast(u32, receipt.call) orelse return error.AcquisitionMismatch;
        var captured = try @import("../call/capture.zig").load(io, a, parent, run_path, project.selected.workflow_id, ordinal);
        defer captured.deinit();
        if (!std.meta.eql(receipt.origin, captured.context.origin) or !std.mem.eql(u8, receipt.request_step, captured.context.request_step)) return error.CaptureMismatch;
        try verifyBytes(receipt.context_sha256, try files.read(io, a, parent, captured.context_path));
        try verifyBytes(receipt.request_sha256, captured.call.request.?);
        const expected_usage = try @import("../e2e/observation.zig").usageFor(workflow.attempts, receipt.origin);
        if (!std.meta.eql(expected_usage, receipt.usage)) return error.CaptureMismatch;
        try verifyExchange(io, a, run, receipt, captured, &expected_config.value().models, &outputs);
    }
    return outputs.toOwnedSlice(a);
}

/// The native capture owns admitted-value observations. Recompute mechanical
/// issues and chronological consumption independently of assessor labels.
pub fn admissionMetric(a: std.mem.Allocator, facts: acquisition.Facts) !admission.Metric {
    const workflow = facts.workflow orelse return .{ .status = .unavailable };
    const exchanges = try a.alloc(admission.Exchange, facts.receipts.len);
    defer a.free(exchanges);
    for (facts.receipts, exchanges) |receipt, *exchange| exchange.* = .{ .call = receipt.call, .origin = receipt.origin, .usage = receipt.usage, .uncertain_delivery = receipt.uncertain_delivery };
    if (workflow.admission_audit) |audit| try admission.validate(a, audit, exchanges);
    const metric = try admission.measure(workflow.admission_audit, exchanges);
    if (workflow.admission_escape) |captured| {
        if (!std.meta.eql(captured, metric)) return error.CaptureMismatch;
    } else if (workflow.admission_audit != null) return error.CaptureMismatch;
    return metric;
}

fn invocationUnstarted(facts: acquisition.Facts) !bool {
    if (facts.workflow != null) return false;
    if (facts.receipts.len != 0 or facts.first_candidate != null or facts.final_candidate != null or facts.published_output != null or
        facts.clarification_outputs.len != 0 or facts.review_findings.len != 0 or facts.review_coverage.len != 0) return error.AcquisitionMismatch;
    return true;
}

const Offline = struct {
    marker: u8 = 0,
    fn exchange(_: *@import("../../../src/adapters/provider/bedrock_transport.zig").Context, _: std.mem.Allocator, _: @import("../../../src/adapters/provider/bedrock_transport.zig").Request) @import("../../../src/adapters/provider/bedrock_transport.zig").Error!@import("../../../src/adapters/provider/bedrock_transport.zig").Response {
        return error.Cancelled;
    }
    fn now(_: *@import("../../../src/ports/provider_authorization_lease.zig").Context) error{ClockUnavailable}!u64 {
        return error.ClockUnavailable;
    }
};

fn verifyExchange(io: std.Io, a: std.mem.Allocator, run: std.Io.Dir, receipt: trace.Receipt, captured: @import("../call/capture.zig").Captured, expected_models: *const @import("../../../src/domain/config.zig").ModelsConfig, outputs: *std.ArrayList(assessment.Output)) !void {
    const description = captured.call.description.?;
    const binding = @import("../diagnostic_binding.zig");
    _ = try binding.rebind(a, description, captured.provider_catalogue, description.model, description.reasoning_effort);
    if (description.provider_config != .aws_bedrock) return error.FrozenBindingRejected;
    try @import("../frozen_binding.zig").validateDescription(a, description, .{
        .region = description.provider_config.aws_bedrock.region,
        .model = @import("../../../src/domain/llm_provider_identity.zig").ModelId.parse(description.model) orelse return error.FrozenBindingRejected,
        .kind = .inference,
        .body = captured.call.request.?,
        .api_key = "",
        .deadline_monotonic_ms = 0,
    }, expected_models);
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    var authority: binding.Authorization = .{ .binding = description };
    var offline: Offline = .{};
    var parser: @import("../../../src/adapters/parsers/model_result_schemas.zig").Adapter = .{};
    var provider: @import("../../../src/adapters/provider/request_replay.zig").Adapter = .{
        .authorization = .{ .context = @ptrCast(&authority), .authorize_fn = binding.Authorization.authorize },
        .environment = &environment,
        .transport = .{ .context = @ptrCast(&offline), .exchange_fn = Offline.exchange },
        .clock = .{ .context = @ptrCast(&offline), .now_fn = Offline.now },
        .compiler = parser.compiler(),
    };
    if (!std.mem.eql(u8, try provider.provider().prepare(a, description), captured.call.request.?)) return error.CaptureMismatch;
    const outcome_path = try evidence.Store.path(a, .generation, receipt.call, .outcome);
    const outcome = try @import("../contracts.zig").decode(trace.TransportOutcome, a, try files.read(io, a, run, outcome_path));
    const status: ?u16 = if (outcome == .received) outcome.received.status else null;
    if (status != receipt.status or (captured.call.response_status != null and captured.call.response_status != receipt.status)) return error.CaptureMismatch;
    var model_output: ?[]const u8 = null;
    if (receipt.model_output_available) {
        const expected = receipt.model_output_sha256 orelse return error.CaptureMismatch;
        const text = try files.read(io, a, run, try evidence.Store.path(a, .generation, receipt.call, .model_output));
        try verifyBytes(expected, text);
        model_output = text;
        try outputs.append(a, .{ .id = try std.fmt.allocPrint(a, "call-{d:0>6}", .{receipt.call}), .attempt = receipt.origin.attempt.value, .text = text, .sha256 = try frozen_inputs.hash(a, text) });
    } else if (receipt.model_output_sha256 != null) return error.CaptureMismatch;
    if (receipt.raw_response_available) {
        const expected = receipt.response_sha256 orelse return error.CaptureMismatch;
        const raw = try files.read(io, a, run, try evidence.Store.path(a, .generation, receipt.call, .response));
        try verifyBytes(expected, raw);
        const archived = captured.call.response orelse return error.CaptureMismatch;
        if (!std.mem.eql(u8, raw, archived) or !std.mem.eql(u8, captured.call.response_encoding, "utf8")) return error.CaptureMismatch;
        const provenance = captured.call.response_provenance orelse return error.CaptureMismatch;
        if (!std.mem.eql(u8, provenance, "provider_body") and !std.mem.eql(u8, provenance, "partial_provider_body")) return error.CaptureMismatch;
        if (status == 200 and !receipt.uncertain_delivery and std.mem.eql(u8, provenance, "provider_body")) {
            const inspected = try provider.provider().inspect(a, description, raw);
            if (inspected.input_tokens) |input| {
                const output = inspected.output_tokens orelse return error.CaptureMismatch;
                const usage = operation.ProviderUsage.init(input, output, std.math.add(u64, input, output) catch return error.CaptureMismatch) orelse return error.CaptureMismatch;
                if (receipt.usage == null or !std.meta.eql(usage, receipt.usage.?)) return error.CaptureMismatch;
            } else if (receipt.usage != null) return error.CaptureMismatch;
            if (model_output) |text| {
                if (inspected.model_text == null or !std.mem.eql(u8, text, inspected.model_text.?)) return error.CaptureMismatch;
            }
        }
    } else if (model_output != null) return error.CaptureMismatch;
}

fn addSnapshot(a: std.mem.Allocator, outputs: *std.ArrayList(assessment.Output), id: []const u8, snapshot: @import("candidates.zig").Snapshot) !void {
    if (!std.mem.eql(u8, try frozen_inputs.hash(a, snapshot.json), &snapshot.sha256)) return error.CaptureMismatch;
    try outputs.append(a, .{ .id = id, .attempt = if (snapshot.first_pass) 1 else 2, .text = snapshot.json, .sha256 = try a.dupe(u8, &snapshot.sha256) });
}

fn nativeStatus(facts: acquisition.Facts) comparison.Status {
    if (facts.receipts.len == 0) return .unattempted;
    if (facts.diagnostic != null) return .blocked;
    const workflow = facts.workflow orelse return .blocked;
    if (workflow.status == .awaiting_clarification and workflow.workflow_outcome == .needs_user and workflow.publication_check == .passed) return .clarification;
    if (workflow.status == .generated and workflow.workflow_outcome == .ok and workflow.publication_check == .passed and facts.published_output != null) return .completed;
    if (workflow.last_provider_rejection != null or workflow.provider_diagnostic != null) {
        if (workflow.provider_diagnostic) |diagnostic| {
            if (std.meta.stringToEnum(operation.ProviderNonCandidateStopReason, diagnostic)) |reason| if (reason == .output_limit) return .truncated;
        }
        if (workflow.last_provider_rejection) |rejection| {
            if (std.meta.stringToEnum(operation.ProviderNonCandidateStopReason, rejection.reason)) |reason| if (reason == .output_limit) return .truncated;
        }
        return .provider_failed;
    }
    if (workflow.last_protocol_rejection != null or workflow.json_error != null or workflow.schema_error != null) return .malformed;
    return .blocked;
}

pub fn projectCapture(a: std.mem.Allocator, record: acquisition.Record, raw_outputs: []const assessment.Output) !assessment.Capture {
    const facts = record.facts;
    const status = nativeStatus(facts);
    if (status == .unattempted) return .{
        .trial_ordinal = facts.trial.ordinal,
        .case_id = facts.trial.case_id,
        .acquisition_sha256 = record.sha256,
        .scope = .workflow,
        .initial_status = .unattempted,
        .status = .unattempted,
        .initial_structural_valid = false,
        .structural_valid = false,
        .published = false,
        .corrective_sends = 0,
        .physical_sends = 0,
        .usage = null,
        .elapsed_ns = null,
        .uncertain_delivery = false,
        .outputs = &.{},
        .initial_output_ids = &.{},
        .final_output_ids = &.{},
    };
    var outputs: std.ArrayList(assessment.Output) = .empty;
    try outputs.appendSlice(a, raw_outputs);
    var initial_ids: []const []const u8 = &.{};
    var final_ids: []const []const u8 = &.{};
    var initial_status: comparison.Status = .blocked;
    if (facts.first_candidate) |snapshot| {
        try addSnapshot(a, &outputs, "initial-candidate", snapshot);
        if (snapshot.first_pass) {
            initial_ids = &.{"initial-candidate"};
            initial_status = .completed;
        }
    }
    if (facts.final_candidate) |snapshot| {
        try addSnapshot(a, &outputs, "final-candidate", snapshot);
        final_ids = &.{"final-candidate"};
    }
    if (facts.published_output) |published| {
        const text = if (status == .clarification) try std.json.Stringify.valueAlloc(a, .{ .specification = published, .clarifications = facts.clarification_outputs }, .{}) else published;
        const original_clarification = initial_ids.len == 0 and status == .clarification and uncorrectedClarification(facts);
        try outputs.append(a, .{ .id = "published-specification", .attempt = if (original_clarification) 1 else 2, .text = text, .sha256 = try frozen_inputs.hash(a, text) });
        final_ids = &.{"published-specification"};
        if (original_clarification) {
            initial_ids = final_ids;
            initial_status = .clarification;
        }
    }
    var input: u64 = 0;
    var output: u64 = 0;
    var usage_complete = true;
    var uncertain = false;
    var corrective: u32 = 0;
    for (facts.receipts) |receipt| {
        uncertain = uncertain or receipt.uncertain_delivery;
        if (receipt.usage) |usage| {
            if (operation.ProviderUsage.init(usage.input_tokens, usage.output_tokens, usage.total_tokens) == null) return error.CaptureMismatch;
            input = std.math.add(u64, input, usage.input_tokens) catch return error.AccountingOverflow;
            output = std.math.add(u64, output, usage.output_tokens) catch return error.AccountingOverflow;
        } else usage_complete = false;
        const is_corrective = receipt.origin.attempt.value > 1 or receipt.purpose == .atomic_repair;
        if (is_corrective) corrective = std.math.add(u32, corrective, 1) catch return error.AccountingOverflow;
    }
    const sends = std.math.cast(u32, facts.receipts.len) orelse return error.AccountingOverflow;
    if (corrective >= sends) return error.CaptureMismatch;
    const review_views = try reviewViews(a, facts, outputs.items);
    const upstream_targets = try upstreamTargets(a, facts, outputs.items);
    return .{
        .trial_ordinal = facts.trial.ordinal,
        .case_id = facts.trial.case_id,
        .acquisition_sha256 = record.sha256,
        .scope = .workflow,
        .initial_status = initial_status,
        .status = status,
        .initial_structural_valid = initial_status == .completed or initial_status == .clarification,
        .structural_valid = status == .completed or status == .clarification,
        .published = status == .completed,
        .corrective_sends = corrective,
        .physical_sends = sends,
        .usage = if (usage_complete) .{ .input_tokens = input, .output_tokens = output } else null,
        .elapsed_ns = facts.elapsed_ns,
        .uncertain_delivery = uncertain,
        .outputs = try outputs.toOwnedSlice(a),
        .initial_output_ids = initial_ids,
        .final_output_ids = final_ids,
        .final_content_valid = final_ids.len != 0 and facts.diagnostic == null,
        .findings = review_views.findings,
        .review_coverage = review_views.coverage,
        .upstream_targets = upstream_targets,
    };
}

fn upstreamTargets(a: std.mem.Allocator, facts: acquisition.Facts, outputs: []const assessment.Output) ![]const upstream.Target {
    var targets: std.ArrayList(upstream.Target) = .empty;
    errdefer targets.deinit(a);
    for (facts.receipts) |receipt| {
        switch (receipt.owner_kind) {
            .reference_chunk, .reference_global => {},
            .workflow_step, .specification_unit, .plan_unit, .task_cluster, .implementation_operation, .semantic_review => continue,
        }
        switch (receipt.purpose) {
            .initial_generation, .atomic_repair, .context_followup => {},
            .semantic_review, .clarification_resolution => continue,
        }
        const id = try rawOutputId(a, receipt, outputs);
        const output: ?assessment.Output = if (id) |selected| selected_output: {
            for (outputs) |output| if (std.mem.eql(u8, output.id, selected)) break :selected_output output;
            return error.CaptureMismatch;
        } else null;
        try targets.append(a, .{
            .call = receipt.call,
            .origin = receipt.origin,
            .purpose = receipt.purpose,
            .owner_kind = receipt.owner_kind,
            .output_id = id,
            .text = if (output) |value| value.text else null,
            .sha256 = if (output) |value| value.sha256 else null,
            .mechanical_failure = upstreamMechanicalFailure(receipt),
            .usage = if (receipt.usage) |usage| .{ .input_tokens = usage.input_tokens, .output_tokens = usage.output_tokens } else null,
            .uncertain_delivery = receipt.uncertain_delivery,
        });
    }
    return targets.toOwnedSlice(a);
}
fn upstreamMechanicalFailure(receipt: trace.Receipt) bool {
    if (receipt.status) |status| if (status < 200 or status >= 300) return true;
    return receipt.mechanical_rejection != null;
}

const ReviewViews = struct { findings: []const assessment.CapturedFinding, coverage: []const assessment.ReviewCoverage };
fn reviewViews(a: std.mem.Allocator, facts: acquisition.Facts, outputs: []const assessment.Output) !ReviewViews {
    const findings = try a.alloc(assessment.CapturedFinding, facts.review_findings.len);
    errdefer a.free(findings);
    var history: std.ArrayList(reviews.VerifiedFinding) = .empty;
    defer history.deinit(a);
    var at: usize = 0;
    // Native collection order is not a chronology guarantee. Partial repairs
    // inherit a verdict only from their exact, already verified native origin.
    for (facts.receipts) |receipt| for (facts.review_findings) |finding| {
        if (!std.meta.eql(finding.origin, receipt.origin)) continue;
        if (at == findings.len) return error.CaptureMismatch;
        const output_id = try rawOutputId(a, receipt, outputs);
        var verified: reviews.Verification = .unmeasured;
        if (output_id) |id| {
            for (outputs) |output| if (std.mem.eql(u8, output.id, id)) {
                verified = try reviews.verifyWithHistory(a, finding, output.text, receipt.result_definition, receipt.repair_origin, history.items);
                break;
            };
        }
        findings[at] = .{ .native = finding, .purpose = receipt.purpose, .output_id = output_id, .raw_verification = verified };
        at += 1;
        try history.append(a, .{ .finding = finding, .verification = verified });
    };
    if (at != findings.len) return error.CaptureMismatch;
    for (facts.review_coverage) |entry| {
        for (facts.receipts) |receipt| {
            if (std.meta.eql(entry.origin, receipt.origin)) break;
        } else return error.CaptureMismatch;
    }
    var coverage: std.ArrayList(assessment.ReviewCoverage) = .empty;
    errdefer coverage.deinit(a);
    for (facts.receipts) |receipt| {
        var review: ?reviews.Review = null;
        var projected = false;
        var native_coverage = false;
        var expected_findings: ?u32 = null;
        for (facts.review_coverage) |entry| if (std.meta.eql(entry.origin, receipt.origin)) {
            if (native_coverage) return error.CaptureMismatch;
            native_coverage = true;
            review = switch (entry.review) {
                .source => .source,
                .principles => .principles,
                .preservation => .preservation,
            };
            projected = entry.complete;
            expected_findings = entry.expected_findings;
        };
        if (stages.classify(receipt.purpose, receipt.owner_kind) != .review and !native_coverage) continue;
        const output_id = try rawOutputId(a, receipt, outputs);
        for (findings) |finding| if (std.meta.eql(finding.native.origin, receipt.origin) and finding.raw_verification != .complete) {
            projected = false;
        };
        try coverage.append(a, .{ .origin = receipt.origin, .output_id = output_id, .review = review, .projected = projected and output_id != null, .expected_findings = expected_findings });
    }
    return .{ .findings = findings, .coverage = try coverage.toOwnedSlice(a) };
}

fn projectDocuments(a: std.mem.Allocator, frozen: frozen_inputs.Freeze, trial: comparison.Trial) ![]const assessment.ProjectDocument {
    const project = try frozen_inputs.project(a, frozen, trial);
    var config = try (@import("../../../src/actions/config/decode_sddtoolkit_config.zig").Action{}).execute(a, project.captured.config);
    defer config.deinit();
    const principles_root = try frozen_inputs.configuredRoot(a, frozen, .principles, config.value().paths.principles);
    var result: std.ArrayList(assessment.ProjectDocument) = .empty;
    for (project.captured.files) |file| {
        if (!@import("../../../src/domain/relative_directory_path.zig").contains(principles_root.relative_path, file.mapping.destination)) continue;
        // Native semantic principle capture already requires UTF-8. Other
        // frozen files remain available in inputs.json, not guessed as prose.
        if (!std.unicode.utf8ValidateSlice(file.bytes)) continue;
        try result.append(a, .{ .path = file.mapping.destination, .text = file.bytes });
    }
    return result.toOwnedSlice(a);
}
fn rawOutputId(a: std.mem.Allocator, receipt: trace.Receipt, outputs: []const assessment.Output) !?[]const u8 {
    if (!receipt.model_output_available) return null;
    const id = try std.fmt.allocPrint(a, "call-{d:0>6}", .{receipt.call});
    for (outputs) |output| if (std.mem.eql(u8, output.id, id)) return output.id;
    return error.CaptureMismatch;
}

fn uncorrectedClarification(facts: acquisition.Facts) bool {
    const workflow = facts.workflow orelse return false;
    if (workflow.repairs.len != 0 or facts.clarification_outputs.len == 0) return false;
    for (workflow.corrections) |correction| if (correction.repair != null) return false;
    for (facts.receipts) |receipt| if (receipt.origin.attempt.value != 1 or receipt.purpose == .atomic_repair) return false;
    return true;
}

fn emptyStages(a: std.mem.Allocator) ![]StageResources {
    const result = try a.alloc(StageResources, std.meta.tags(stages.Stage).len);
    for (std.meta.tags(stages.Stage), result) |stage, *value| value.* = .{ .stage = stage };
    return result;
}
pub fn resourceStages(a: std.mem.Allocator, receipts: []const trace.Receipt) ![]const StageResources {
    const result = try emptyStages(a);
    errdefer a.free(result);
    for (receipts) |receipt| {
        const stage = stages.classify(receipt.purpose, receipt.owner_kind);
        const value = &result[@intFromEnum(stage)];
        value.physical_sends = std.math.add(u64, value.physical_sends, 1) catch return error.AccountingOverflow;
        if (receipt.usage) |usage| {
            if (operation.ProviderUsage.init(usage.input_tokens, usage.output_tokens, usage.total_tokens) == null) return error.CaptureMismatch;
            value.known_actual_tokens = std.math.add(u64, value.known_actual_tokens, usage.total_tokens) catch return error.AccountingOverflow;
            value.known_input_tokens = std.math.add(u64, value.known_input_tokens, usage.input_tokens) catch return error.AccountingOverflow;
            value.known_output_tokens = std.math.add(u64, value.known_output_tokens, usage.output_tokens) catch return error.AccountingOverflow;
        } else value.usage_complete = false;
        value.actual_tokens = if (value.usage_complete) value.known_actual_tokens else null;
        value.actual_input_tokens = if (value.usage_complete) value.known_input_tokens else null;
        value.actual_output_tokens = if (value.usage_complete) value.known_output_tokens else null;
    }
    try stageShares(result);
    return result;
}

fn stageShares(values: []StageResources) !void {
    var sends: u64 = 0;
    var tokens: u64 = 0;
    var usage_complete = true;
    for (values) |value| {
        sends = std.math.add(u64, sends, value.physical_sends) catch return error.AccountingOverflow;
        tokens = std.math.add(u64, tokens, value.known_actual_tokens) catch return error.AccountingOverflow;
        usage_complete = usage_complete and value.usage_complete;
    }
    for (values) |*value| {
        value.send_share = if (sends != 0) @as(f64, @floatFromInt(value.physical_sends)) / @as(f64, @floatFromInt(sends)) else null;
        value.known_accounted_token_share = if (tokens != 0) @as(f64, @floatFromInt(value.known_actual_tokens)) / @as(f64, @floatFromInt(tokens)) else null;
        value.actual_token_share = if (usage_complete) value.known_accounted_token_share else null;
    }
}
fn combineStages(a: std.mem.Allocator, rows: []const Row) ![]const StageResources {
    return combineSelectedStages(a, rows, null);
}
fn combineSelectedStages(a: std.mem.Allocator, rows: []const Row, feature_id: ?[]const u8) ![]const StageResources {
    const result = try emptyStages(a);
    errdefer a.free(result);
    for (rows) |row| {
        if (feature_id) |selected| if (!std.mem.eql(u8, selected, row.trial.feature_id)) continue;
        for (row.stage_resources) |item| {
            const target = &result[@intFromEnum(item.stage)];
            target.physical_sends = std.math.add(u64, target.physical_sends, item.physical_sends) catch return error.AccountingOverflow;
            target.known_actual_tokens = std.math.add(u64, target.known_actual_tokens, item.known_actual_tokens) catch return error.AccountingOverflow;
            target.known_input_tokens = std.math.add(u64, target.known_input_tokens, item.known_input_tokens) catch return error.AccountingOverflow;
            target.known_output_tokens = std.math.add(u64, target.known_output_tokens, item.known_output_tokens) catch return error.AccountingOverflow;
            target.usage_complete = target.usage_complete and item.usage_complete;
            target.actual_tokens = if (target.usage_complete) target.known_actual_tokens else null;
            target.actual_input_tokens = if (target.usage_complete) target.known_input_tokens else null;
            target.actual_output_tokens = if (target.usage_complete) target.known_output_tokens else null;
        }
    }
    try stageShares(result);
    return result;
}
fn featureResources(a: std.mem.Allocator, rows: []const Row) ![]const FeatureResources {
    var result: std.ArrayList(FeatureResources) = .empty;
    for (rows, 0..) |row, index| {
        var seen = false;
        for (rows[0..index]) |prior| if (std.mem.eql(u8, prior.trial.feature_id, row.trial.feature_id)) {
            seen = true;
        };
        if (!seen) try result.append(a, .{ .feature_id = row.trial.feature_id, .stages = try combineSelectedStages(a, rows, row.trial.feature_id) });
    }
    return result.toOwnedSlice(a);
}

pub fn selectQualification(a: std.mem.Allocator, inventory: comparison.Inventory, scorecard: comparison.Scorecard, complete: bool) !Qualification {
    const baseline = scorecard.baseline orelse return .{ .status = .incomplete };
    if (!complete or scorecard.inconclusive or baseline.qualification.status == .insufficient) return .{ .status = .incomplete, .independent_features = baseline.qualification.required_features, .paired_workloads = baseline.qualification.paired_workloads };
    if (baseline.qualification.status == .infeasible) return .{ .status = .infeasible, .independent_features = baseline.qualification.required_features, .paired_workloads = baseline.qualification.paired_workloads };
    switch (baseline.qualification.observed_cost_budget) {
        .exceeds => return .{ .status = .infeasible_under_declared_cost_envelope, .independent_features = baseline.qualification.required_features, .paired_workloads = baseline.qualification.paired_workloads },
        .unavailable => return .{ .status = .incomplete, .independent_features = baseline.qualification.required_features, .paired_workloads = baseline.qualification.paired_workloads },
        .fits => {},
    }
    const count = baseline.qualification.required_features orelse return error.InvalidQualificationSelection;
    var feature_ids: std.ArrayList([]const u8) = .empty;
    for (inventory.cases) |example| {
        if (example.partition == .qualification and example.variant == .base and feature_ids.items.len < count) try feature_ids.append(a, example.feature_id);
    }
    if (feature_ids.items.len != count) return error.InvalidQualificationSelection;
    var case_ids: std.ArrayList([]const u8) = .empty;
    for (inventory.cases) |example| {
        if (example.partition != .qualification) continue;
        for (feature_ids.items) |id| if (std.mem.eql(u8, id, example.feature_id)) {
            try case_ids.append(a, example.id);
            break;
        };
    }
    return .{ .status = .frozen, .independent_features = count, .feature_ids = try feature_ids.toOwnedSlice(a), .case_ids = try case_ids.toOwnedSlice(a), .paired_workloads = baseline.qualification.paired_workloads };
}

fn render(a: std.mem.Allocator, report: Report) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(a);
    defer out.deinit();
    const w = &out.writer;
    try w.writeAll("# Baseline assessment\n\nAcquisition scope: unchanged A through full production workflows with actual predecessors. Attempted and unattempted workloads are counted below. This offline report applies supplied source-backed semantic judgments to captured outputs. Model-assisted judgments remain assessments, not deterministic proof. This report grants no workflow, publication, or qualification authority.\n\n");
    try w.print("Native capture complete: **{}**; semantic evidence complete: **{}**. Planned: {d}; attempted generation workloads: {d}; unattempted: {d}. Physical sends: {d}; known accounted tokens: {d}; usage complete: {}. Qualification selection: **{s}**.\n\nTotal actual tokens: ", .{ report.native_capture_complete, report.semantic_evidence_complete, report.scorecard.planned, report.scorecard.attempted, report.scorecard.unattempted, report.scorecard.physical_sends, report.native_budget.total_accounted_tokens, report.native_budget.usage_complete, @tagName(report.qualification.status) });
    try std.json.Stringify.value(report.native_budget.total_actual_tokens, .{}, w);
    try w.writeAll(". Null means at least one send has unknown usage; known consumption remains accounted.\n\n");
    if (report.acquisition_source_error) |diagnostic| try w.print("Post-acquisition source verification failed: {s}. The panel remains incomplete; the original transport stop is retained independently.\n\n", .{diagnostic});
    try w.print("Phase 2 decision: **{s}**; reason: **{s}**; follow-up: **{s}**. Reproduced failure classes: {d}/{d}. This recommendation grants no workflow authority. Missing evidence: ", .{ @tagName(report.phase2_decision.decision), @tagName(report.phase2_decision.reason), @tagName(report.phase2_decision.follow_up), report.phase2_decision.reproduced_failure_classes, report.failure_classes.len });
    try std.json.Stringify.value(report.phase2_decision.missing, .{}, w);
    try w.print(".\n\nThe frozen feasibility report retains declared phase coverage and the worst-observed workflow cost assumption. The exclusive experiment claim admits this baseline once; its actual consumption and remaining allowance are retained independently. Later phases remain reserved and cannot dispatch through this command. Reforecast of all declared future phases: **{s}**. A sized sample outside this envelope remains infeasible with its required count retained and no holdout IDs selected.\n\n", .{@tagName(report.qualification_budget.status)});
    try w.print("Finding-type accuracy: **{s}**. Correct: {d}; incorrect: {d}; unknown: {d}. Native review-bearing sends: {d}; unmeasured review responses: {d}. Only typed native source, principle and preservation-comparison findings with source-backed expected-kind judgments contribute known correctness. Native admission does not prove a finding true. Unsupported or incomplete review contracts stay unmeasured; harmful-diagnosis issue counts are not substituted for finding-type accuracy. Original, latest per native subject, all corrective and complete-chain confusion counts and per-kind precision/recall remain separate in score.json. Evaluator-only source cases and exact native semantic targets are retained in assessment-inputs.json; none are generation inputs.\n\n", .{ @tagName(report.finding_type_accuracy.status), report.finding_type_accuracy.all.counts.correct, report.finding_type_accuracy.all.counts.incorrect, report.finding_type_accuracy.all.counts.unknown, report.finding_type_accuracy.native_review_bearing_sends, report.finding_type_accuracy.unmeasured_review_responses });
    try w.print("Original upstream extraction/reconciliation evidence complete: **{}**. Every original native upstream assignment requires its own exact-response source-backed judgment, independently of specification-generation fidelity. Corrective and context-follow-up targets retain separate unknown counts; their later success cannot replace an original loss. Per-send native origins, output hashes, purpose/owner, usage and correction facts are exported for evaluators. Missing original labels block the Phase 2 decision and qualification selection without erasing independently known generation fidelity.\n\n", .{report.original_upstream_evidence_complete});
    try w.print("Current-content fidelity after the correction chain: known successes {d}, known failures {d}, unknown {d}; complete: {}. Independent-feature rate: ", .{ report.correction_assisted_fidelity.successes, report.correction_assisted_fidelity.failures, report.correction_assisted_fidelity.unknown, report.correction_assisted_fidelity.evidence_complete });
    try std.json.Stringify.value(report.correction_assisted_fidelity.rate, .{}, w);
    try w.print(". Current issue state is assessed separately from cumulative harmful events; later recovery cannot erase those events. Failure attribution complete: {}. Unknown causes require investigation even when fidelity labels are complete. Qualification phase covered by the frozen cost plan: {}.\n\n", .{ report.failure_attribution_complete, report.qualification_scope_covered });
    try w.print("Native useful completion: known successes {d}, known failures {d}, unknown {d}; independent-feature rate: ", .{ report.useful_completion.completion.successes, report.useful_completion.completion.failures, report.useful_completion.completion.unknown });
    try std.json.Stringify.value(report.useful_completion.completion.rate, .{}, w);
    try w.print(". Frozen-rubric evidence complete: {}. A success requires the actual native publication, complete current source fidelity and the frozen rubric threshold; it makes no Phase 5 qualification claim. Exact criterion judgments, provenance and published-output/rubric hashes are retained in score.json.\n\n", .{report.useful_completion.rubric_evidence_complete});
    try w.writeAll("Resource distributions retain median and observed worst sends, input/output/total tokens and elapsed time for all dispatched workloads and known useful workloads separately. Amortized cost per useful completion includes failed and genuine-gap workload costs in its numerator. Missing usage or a missing useful-completion denominator stays null; known partial consumption remains explicit.\n\n");
    try w.print("Native admission escapes: {d}/{d} invoked native workloads; {d} measured, {d} unknown, {d} never invoked. Workload incidence: ", .{ report.admission_escape.escaped_workloads, report.admission_escape.attempted_workloads, report.admission_escape.measured_workloads, report.admission_escape.unknown_workloads, report.admission_escape.unattempted_workloads });
    try std.json.Stringify.value(report.admission_escape.workload_escape_rate, .{}, w);
    try w.print(". Secondary model/native producer diagnostic: {d}/{d}. Downstream chronological exposure after the first escaped admission in each workload: {d} sends, {d} known actual tokens; complete usage: {}. These resources remain included in their native paid stages and are not a causal cost estimate.\n\n", .{ report.admission_escape.escaped_origins, report.admission_escape.admitted_origins, report.admission_escape.downstream.physical_sends, report.admission_escape.downstream.known_actual_tokens, report.admission_escape.downstream.usage_complete });
    try w.writeAll("Missing or disputed labels remain incomplete; absent duty judgments are not invented omissions. Native terminal stages and first native rejections describe chronology. Supplied loss-stage attributions, including representation_admission, are separate semantic judgments. A native invocation that fails before its first physical model send is retained below but has no attempted generation workload. All physical sends and actual usage, including corrections and rejected outputs, contribute to resources. Correction sends are native later attempts or explicitly atomic-repair requests, including failed repairs. Per-stage sends and tokens use native purpose/owner categories, not semantic loss attribution; latency remains a measured whole-workload value. feature_stage_resources preserves known partial consumption when a workload has unknown usage; actual_tokens:null never means zero spent.\n\n");
    try w.writeAll("| Trial | Case | Native result | Assessment | Supplied loss stage | Sends |\n| --- | --- | --- | --- | --- | --- |\n");
    for (report.rows) |row| try w.print("| {d} | {s} | {s} | {s} | {s} | {d} |\n", .{ row.trial.ordinal, row.trial.case_id, if (row.native_status) |value| @tagName(value) else "unattempted", @tagName(row.evidence), if (row.supplied_failure_stage) |value| @tagName(value) else "unknown", row.physical_sends });
    try w.writeAll("\nPer-feature fidelity, robustness, representation sensitivity, repeat variability, native status counts, supplied failure-stage counts and resource totals are retained in score.json. Qualification exposes selected IDs only; its source material and expected duties are not exported.\n");
    try w.writeAll("\n| Feature | Original fidelity | Robust bundles | Repeat inconsistent | Material workloads |\n| --- | --- | --- | --- | --- |\n");
    for (report.scorecard.features) |feature| try w.print("| {s} | {d}/{d} | {d}/{d} | {} | {d} |\n", .{ feature.feature_id, feature.first_pass_successes, feature.well_posed_attempted, feature.robust_bundles, feature.total_bundles, feature.repeat_inconsistent, feature.material_workloads });
    try w.writeAll("\nSource-backed error examples below retain supplied semantic explanations. Citation occurrence is checked mechanically; relevance and preservation remain supplied judgments.\n\n");
    for (report.rows) |row| if (row.supplied_assessment) |entry| {
        if (entry.initial) |labels| try renderErrors(w, row.trial, "initial", labels);
        if (entry.final) |labels| try renderErrors(w, row.trial, "final", labels);
    };
    return out.toOwnedSlice();
}

fn renderErrors(w: *std.Io.Writer, trial: comparison.Trial, phase: []const u8, labels: assessment.Labels) !void {
    for (labels.duties) |duty| if (!duty.preserved) {
        try w.print("- Trial {d}, {s}, {s} duty {s}: ", .{ trial.ordinal, trial.case_id, phase, duty.id });
        try std.json.Stringify.value(duty.explanation, .{}, w);
        try w.writeAll(". Source evidence: ");
        try std.json.Stringify.value(duty.source_refs, .{}, w);
        try w.writeAll(".\n");
    };
    for (labels.issues) |issue| {
        try w.print("- Trial {d}, {s}, {s} issue {s} ({s}): ", .{ trial.ordinal, trial.case_id, phase, issue.id, @tagName(issue.kind) });
        try std.json.Stringify.value(issue.explanation, .{}, w);
        try w.writeAll(". Source evidence: ");
        try std.json.Stringify.value(issue.source_refs, .{}, w);
        try w.writeAll(".\n");
    }
}

test "native projection retains original generation independently of later blocking and sums every usage receipt" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = "{\"candidate\":\"original supported behavior\"}";
    const final = "{\"candidate\":\"later unsupported repair\"}";
    var first_hash: [32]u8 = undefined;
    var last_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(original, &first_hash, .{});
    std.crypto.hash.sha2.Sha256.hash(final, &last_hash, .{});
    const receipts = [_]trace.Receipt{
        .{ .call = 1, .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } }, .experiment_send = .{ .ordinal = 1 }, .purpose = .initial_generation, .owner_kind = .specification_unit, .request_step = "generate", .context_sha256 = @splat(0), .request_sha256 = @splat(0), .usage = .{ .input_tokens = 10, .output_tokens = 7, .total_tokens = 17 } },
        .{ .call = 2, .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 2 } }, .experiment_send = .{ .ordinal = 2 }, .purpose = .initial_generation, .owner_kind = .specification_unit, .request_step = "generate", .context_sha256 = @splat(0), .request_sha256 = @splat(0), .usage = .{ .input_tokens = 13, .output_tokens = 9, .total_tokens = 22 } },
    };
    var facts: acquisition.Facts = .{
        .trial = .{ .ordinal = 1, .case_id = "test-base", .feature_id = "test", .arm = .A, .repetition = 1 },
        .freeze_sha256 = "freeze",
        .workflow = .{ .schema = .@"spec-e2e-report/v3", .started_at_utc = "", .status = .workflow_blocked, .workflow_outcome = .blocked },
        .receipts = &receipts,
        .first_candidate = .{ .json = original, .sha256 = std.fmt.bytesToHex(first_hash, .lower), .first_pass = true },
        .final_candidate = .{ .json = final, .sha256 = std.fmt.bytesToHex(last_hash, .lower), .first_pass = false },
        .elapsed_ns = 100,
    };
    const projected = try projectCapture(a, try acquisition.record(a, facts), &.{});
    try std.testing.expectEqual(comparison.Status.completed, projected.initial_status);
    try std.testing.expectEqual(comparison.Status.blocked, projected.status);
    try std.testing.expectEqual(@as(u64, 23), projected.usage.?.input_tokens);
    try std.testing.expectEqual(@as(u64, 16), projected.usage.?.output_tokens);
    try std.testing.expectEqual(@as(u32, 2), projected.physical_sends);
    try std.testing.expectEqual(@as(u32, 1), projected.corrective_sends);
    try std.testing.expectEqualStrings("initial-candidate", projected.initial_output_ids[0]);
    try std.testing.expectEqualStrings("final-candidate", projected.final_output_ids[0]);
    try std.testing.expect(!projected.published);
    facts.first_candidate.?.first_pass = false;
    const corrected = try projectCapture(a, try acquisition.record(a, facts), &.{});
    try std.testing.expectEqual(comparison.Status.blocked, corrected.initial_status);
    try std.testing.expectEqual(@as(usize, 0), corrected.initial_output_ids.len);
    facts.first_candidate.?.sha256[0] = 'x';
    try std.testing.expectError(error.CaptureMismatch, projectCapture(a, try acquisition.record(a, facts), &.{}));
}

test "receipt hashes reject changed bytes and unknown usage never becomes zero consumption" {
    var expected: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("original provider bytes", &expected, .{});
    try verifyBytes(expected, "original provider bytes");
    try std.testing.expectError(error.CaptureMismatch, verifyBytes(expected, "replaced provider bytes"));
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const facts: acquisition.Facts = .{
        .trial = .{ .ordinal = 1, .case_id = "test-base", .feature_id = "test", .arm = .A, .repetition = 1 },
        .freeze_sha256 = "freeze",
        .elapsed_ns = 1,
        .workflow = .{ .schema = .@"spec-e2e-report/v3", .started_at_utc = "", .status = .workflow_failed, .workflow_outcome = .failed, .provider_diagnostic = "unknown usage" },
        .receipts = &.{.{ .call = 1, .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } }, .experiment_send = .{ .ordinal = 1 }, .purpose = .initial_generation, .owner_kind = .specification_unit, .request_step = "generate", .context_sha256 = @splat(0), .request_sha256 = @splat(0), .uncertain_delivery = true }},
    };
    const projected = try projectCapture(a, try acquisition.record(a, facts), &.{});
    try std.testing.expectEqual(comparison.Status.provider_failed, projected.status);
    try std.testing.expect(projected.usage == null);
    try std.testing.expect(projected.uncertain_delivery);
    try std.testing.expectEqual(@as(u32, 1), projected.physical_sends);
}

test "native genuine clarification targets include registered question bytes without useful completion authority" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const question = "Who authorizes ordinary requests?";
    const facts: acquisition.Facts = .{
        .trial = .{ .ordinal = 1, .case_id = "approval-gap", .feature_id = "approval", .arm = .A, .repetition = 1 },
        .freeze_sha256 = "freeze",
        .elapsed_ns = 1,
        .workflow = .{ .schema = .@"spec-e2e-report/v3", .started_at_utc = "", .status = .awaiting_clarification, .workflow_outcome = .needs_user, .publication_check = .passed },
        .receipts = &.{.{ .call = 1, .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } }, .experiment_send = .{ .ordinal = 1 }, .purpose = .initial_generation, .owner_kind = .reference_chunk, .request_step = "understand", .context_sha256 = @splat(0), .request_sha256 = @splat(0), .usage = .{ .input_tokens = 5, .output_tokens = 3, .total_tokens = 8 } }},
        .published_output = "Urgent requests require manager sign-off. Ordinary approval remains unresolved.",
        .clarification_outputs = &.{.{ .path = "specs/approval/clarify/spec-01.md", .bytes = question, .sha256 = try frozen_inputs.hash(a, question) }},
    };
    const projected = try projectCapture(a, try acquisition.record(a, facts), &.{});
    try std.testing.expectEqual(comparison.Status.clarification, projected.status);
    try std.testing.expectEqual(comparison.Status.clarification, projected.initial_status);
    try std.testing.expectEqualStrings(projected.initial_output_ids[0], projected.final_output_ids[0]);
    try std.testing.expect(std.mem.indexOf(u8, projected.outputs[0].text, question) != null);
    try std.testing.expect(!projected.published);
    var corrected = facts;
    var receipt = facts.receipts[0];
    receipt.origin.attempt.value = 2;
    corrected.receipts = &.{receipt};
    // Include the original failed send: a correction cannot be the sole send.
    const both = [_]trace.Receipt{ facts.receipts[0], receipt };
    corrected.receipts = &both;
    const later = try projectCapture(a, try acquisition.record(a, corrected), &.{});
    try std.testing.expectEqual(comparison.Status.blocked, later.initial_status);
    try std.testing.expectEqual(@as(usize, 0), later.initial_output_ids.len);
    try std.testing.expectEqual(comparison.Status.clarification, later.status);
}

test "qualification selection freezes first sized feature IDs only and refuses incomplete evidence" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try comparison.parseInventory(a, @embedFile("../../calibration/semantic-simplicity/cases.json"));
    const protocol = try comparison.parseProtocol(a, @embedFile("../../calibration/semantic-simplicity/protocol.json"));
    const trials = try comparison.plan(a, inventory, protocol, .baseline);
    const observations = try a.alloc(comparison.Observation, trials.len);
    for (trials, observations) |trial, *observation| {
        const example = try caseFor(inventory, trial.case_id);
        const duties = try a.alloc(comparison.DutyAssessment, example.duties.len);
        for (example.duties, duties) |duty, *label| label.* = .{ .id = duty.id, .preserved = true };
        const status: comparison.Status = if (example.expected_terminal == .completed) .completed else .clarification;
        observation.* = .{
            .trial_ordinal = trial.ordinal,
            .initial = .{ .status = status, .duties = duties, .questions_correct = status == .clarification, .structural_valid = true, .issues = .{} },
            .status = status,
            .duties = duties,
            .questions_correct = status == .clarification,
            .structural_valid = true,
            .published = false,
            .corrective_sends = 0,
            .physical_sends = 1,
            .issues = .{},
            .usage = .{ .input_tokens = 10, .output_tokens = 5 },
            .elapsed_ns = 100,
            .uncertain_delivery = false,
            .scoring_disputed = false,
        };
    }
    var scorecard = try comparison.aggregate(a, inventory, protocol, .baseline, trials, observations, .diagnostic);
    const selected = try selectQualification(a, inventory, scorecard, true);
    try std.testing.expectEqual(.frozen, selected.status);
    try std.testing.expectEqual(@as(usize, protocol.qualification.minimum_features), selected.feature_ids.len);
    try std.testing.expectEqual(selected.feature_ids.len * 3, selected.case_ids.len);
    var first: ?[]const u8 = null;
    for (inventory.cases) |example| if (example.partition == .qualification and example.variant == .base) {
        first = example.feature_id;
        break;
    };
    try std.testing.expectEqualStrings(first.?, selected.feature_ids[0]);
    const bytes = try std.json.Stringify.valueAlloc(a, selected, .{});
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"sources\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"duties\"") == null);
    const missing = try selectQualification(a, inventory, scorecard, false);
    try std.testing.expectEqual(.incomplete, missing.status);
    try std.testing.expectEqual(@as(usize, 0), missing.feature_ids.len);
    scorecard.baseline.?.qualification.observed_cost_budget = .exceeds;
    const over_budget = try selectQualification(a, inventory, scorecard, true);
    try std.testing.expectEqual(.infeasible_under_declared_cost_envelope, over_budget.status);
    try std.testing.expectEqual(selected.independent_features, over_budget.independent_features);
    try std.testing.expectEqual(@as(usize, 0), over_budget.feature_ids.len);
    scorecard.baseline.?.qualification.status = .infeasible;
    const infeasible = try selectQualification(a, inventory, scorecard, true);
    try std.testing.expectEqual(.infeasible, infeasible.status);
    try std.testing.expectEqual(@as(usize, 0), infeasible.feature_ids.len);
}

test "native purposes count failed first repair sends and preserve unknown per-stage consumption" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const receipts = [_]trace.Receipt{
        .{ .call = 1, .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } }, .purpose = .initial_generation, .owner_kind = .reference_chunk, .experiment_send = .{ .ordinal = 1 }, .request_step = "extract", .context_sha256 = @splat(0), .request_sha256 = @splat(0), .usage = .{ .input_tokens = 3, .output_tokens = 2, .total_tokens = 5 } },
        .{ .call = 2, .origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } }, .purpose = .initial_generation, .owner_kind = .specification_unit, .experiment_send = .{ .ordinal = 2 }, .request_step = "author", .context_sha256 = @splat(0), .request_sha256 = @splat(0), .usage = .{ .input_tokens = 4, .output_tokens = 3, .total_tokens = 7 } },
        .{ .call = 3, .origin = .{ .request = .{ .value = 3 }, .attempt = .{ .value = 1 } }, .purpose = .atomic_repair, .owner_kind = .specification_unit, .experiment_send = .{ .ordinal = 3 }, .request_step = "replace", .context_sha256 = @splat(0), .request_sha256 = @splat(0), .usage = .{ .input_tokens = 6, .output_tokens = 5, .total_tokens = 11 } },
        .{ .call = 4, .origin = .{ .request = .{ .value = 4 }, .attempt = .{ .value = 1 } }, .purpose = .semantic_review, .owner_kind = .semantic_review, .experiment_send = .{ .ordinal = 4 }, .request_step = "assess", .context_sha256 = @splat(0), .request_sha256 = @splat(0) },
    };
    const resources = try resourceStages(a, &receipts);
    try std.testing.expectEqual(@as(u64, 1), resources[@intFromEnum(stages.Stage.repair)].physical_sends);
    try std.testing.expectEqual(@as(?u64, 11), resources[@intFromEnum(stages.Stage.repair)].actual_tokens);
    try std.testing.expectEqual(@as(u64, 1), resources[@intFromEnum(stages.Stage.review)].physical_sends);
    try std.testing.expect(resources[@intFromEnum(stages.Stage.review)].actual_tokens == null);
    try std.testing.expect(!resources[@intFromEnum(stages.Stage.review)].usage_complete);
    const generation_index = @intFromEnum(stages.Stage.generation);
    try std.testing.expectEqual(@as(?u64, 4), resources[generation_index].actual_input_tokens);
    try std.testing.expectEqual(@as(?u64, 3), resources[generation_index].actual_output_tokens);
    try std.testing.expectEqual(@as(?f64, 0.25), resources[generation_index].send_share);
    try std.testing.expectApproxEqAbs(@as(f64, 7.0 / 23.0), resources[generation_index].known_accounted_token_share.?, 0.00001);
    // One unknown stage makes every exact total-token share unknown, even
    // when another stage's own consumption is fully observed.
    try std.testing.expect(resources[generation_index].actual_token_share == null);
    const complete_resources = try resourceStages(a, receipts[0..3]);
    try std.testing.expectApproxEqAbs(@as(f64, 7.0 / 23.0), complete_resources[generation_index].actual_token_share.?, 0.00001);
    const facts: acquisition.Facts = .{
        .trial = .{ .ordinal = 1, .case_id = "test-base", .feature_id = "test", .arm = .A, .repetition = 1 },
        .freeze_sha256 = "freeze",
        .elapsed_ns = 1,
        .workflow = .{ .schema = .@"spec-e2e-report/v3", .started_at_utc = "", .status = .workflow_blocked, .workflow_outcome = .blocked },
        .receipts = &receipts,
    };
    const projected = try projectCapture(a, try acquisition.record(a, facts), &.{});
    try std.testing.expectEqual(@as(u32, 1), projected.corrective_sends);
    try std.testing.expect(projected.usage == null);
    var stopped = facts;
    stopped.workflow.?.provider_diagnostic = "output_limit";
    try std.testing.expectEqual(comparison.Status.truncated, nativeStatus(stopped));
}

test "upstream projection binds original and corrected raw sends and retains native rejection proof" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first: trace.Receipt = .{ .call = 1, .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } }, .purpose = .initial_generation, .owner_kind = .reference_chunk, .experiment_send = null, .request_step = "native-operation", .context_sha256 = @splat(0), .request_sha256 = @splat(0), .model_output_available = true, .status = 200, .usage = .{ .input_tokens = 3, .output_tokens = 2, .total_tokens = 5 } };
    var corrected = first;
    corrected.call = 2;
    corrected.origin.attempt.value = 2;
    var rejected = first;
    rejected.call = 3;
    rejected.origin.request.value = 2;
    rejected.owner_kind = .reference_global;
    rejected.model_output_available = false;
    rejected.status = 400;
    rejected.usage = null;
    var review = first;
    review.call = 4;
    review.origin.request.value = 3;
    review.purpose = .semantic_review;
    const raw = [_]assessment.Output{
        .{ .id = "call-000001", .attempt = 1, .text = "MOCK original upstream output", .sha256 = try frozen_inputs.hash(a, "MOCK original upstream output") },
        .{ .id = "call-000002", .attempt = 2, .text = "MOCK corrected upstream output", .sha256 = try frozen_inputs.hash(a, "MOCK corrected upstream output") },
    };
    const facts: acquisition.Facts = .{ .trial = .{ .ordinal = 1, .case_id = "native-base", .feature_id = "native", .arm = .A, .repetition = 1 }, .freeze_sha256 = "freeze", .receipts = &.{ first, corrected, rejected, review } };
    const targets = try upstreamTargets(a, facts, &raw);
    try std.testing.expectEqual(@as(usize, 3), targets.len);
    try std.testing.expect(upstream.requiredOriginal(targets[0]));
    try std.testing.expect(!upstream.requiredOriginal(targets[1]));
    try std.testing.expectEqualStrings(raw[0].sha256, targets[0].sha256.?);
    try std.testing.expectEqualStrings(raw[1].text, targets[1].text.?);
    try std.testing.expectEqual(@as(u64, 3), targets[0].usage.?.input_tokens);
    try std.testing.expect(targets[2].mechanical_failure and targets[2].text == null);
    rejected.status = 200;
    try std.testing.expect(!upstreamMechanicalFailure(rejected));
    rejected.mechanical_rejection = .{ .protocol = .{ .call = rejected.call, .origin = rejected.origin, .reason = "MOCK native schema rejection", .json_error = null, .schema_error = null } };
    try std.testing.expect(upstreamMechanicalFailure(rejected));
}

fn testRow(feature_id: []const u8, resources: []const StageResources) Row {
    return .{
        .trial = .{ .ordinal = 1, .case_id = feature_id, .feature_id = feature_id, .arm = .A, .repetition = 1 },
        .acquisition_sha256 = "native-record",
        .evidence = .incomplete,
        .provenance = null,
        .supplied_assessment = null,
        .native_status = null,
        .native_outcome = null,
        .terminal_step = null,
        .first_native_rejection = null,
        .diagnostic = null,
        .initial_output_ids = &.{},
        .final_output_ids = &.{},
        .supplied_failure_stage = null,
        .physical_sends = 0,
        .usage = null,
        .elapsed_ns = null,
        .native_invocation_elapsed_ns = null,
        .stage_resources = resources,
        .finding_assessments = &.{},
        .review_coverage = &.{},
        .final_current_fidelity = null,
        .published_output_assessment = .{ .state = .not_required, .useful = null, .evidence_complete = true },
        .upstream_assessment = .{ .results = &.{}, .original = .{}, .corrective = .{}, .evidence_complete = true, .original_evidence_complete = true, .corrective_evidence_complete = true },
        .admission_escape = .{ .status = .unavailable },
    };
}
test "per-feature resources retain known costs alongside unknown sends and isolate unrelated features" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rows = [_]Row{
        testRow("feature-alpha", &.{.{ .stage = .generation, .physical_sends = 2, .known_actual_tokens = 7, .known_input_tokens = 4, .known_output_tokens = 3, .actual_tokens = null, .actual_input_tokens = null, .actual_output_tokens = null, .usage_complete = false }}),
        testRow("feature-alpha", &.{.{ .stage = .generation, .physical_sends = 1, .known_actual_tokens = 5, .known_input_tokens = 3, .known_output_tokens = 2, .actual_tokens = 5, .actual_input_tokens = 3, .actual_output_tokens = 2 }}),
        testRow("feature-beta", &.{.{ .stage = .generation, .physical_sends = 1, .known_actual_tokens = 11, .known_input_tokens = 6, .known_output_tokens = 5, .actual_tokens = 11, .actual_input_tokens = 6, .actual_output_tokens = 5 }}),
    };
    const features = try featureResources(a, &rows);
    try std.testing.expectEqual(@as(usize, 2), features.len);
    const generation_index = @intFromEnum(stages.Stage.generation);
    try std.testing.expectEqual(@as(u64, 12), features[0].stages[generation_index].known_actual_tokens);
    try std.testing.expect(features[0].stages[generation_index].actual_tokens == null);
    try std.testing.expectEqual(@as(u64, 3), features[0].stages[generation_index].physical_sends);
    try std.testing.expectEqual(@as(?u64, 11), features[1].stages[generation_index].actual_tokens);
    const combined = try combineStages(a, &rows);
    try std.testing.expectEqual(@as(u64, 23), combined[generation_index].known_actual_tokens);
    try std.testing.expect(combined[generation_index].actual_tokens == null);
}
test "partial setup without invocation stays unattempted while native exchanges require strict readback" {
    const row = testRow("setup-failure", &.{});
    var facts: acquisition.Facts = .{ .trial = row.trial, .freeze_sha256 = "freeze", .directory = "trials/0001/partial", .inputs_sha256 = "reserved-input-identity", .diagnostic = "InputUnavailable" };
    try std.testing.expect(try invocationUnstarted(facts));
    try std.testing.expectEqual(comparison.Status.unattempted, nativeStatus(facts));
    facts.workflow = .{ .schema = .@"spec-e2e-report/v3", .started_at_utc = "", .status = .input_invalid };
    try std.testing.expect(!try invocationUnstarted(facts));
    facts.workflow = null;
    facts.receipts = &.{.{ .call = 1, .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } }, .purpose = .initial_generation, .owner_kind = .reference_chunk, .experiment_send = .{ .ordinal = 1 }, .request_step = "extract", .context_sha256 = @splat(0), .request_sha256 = @splat(0) }};
    try std.testing.expectError(error.AcquisitionMismatch, invocationUnstarted(facts));
}

test "recovered initial false gaps and wrong genuine-gap questions still require causal attribution" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try comparison.parseInventory(a, @embedFile("../../calibration/semantic-simplicity/cases.json"));
    for (inventory.cases) |example| {
        if (example.partition != .development or example.variant != .base) continue;
        const duties = try a.alloc(comparison.DutyAssessment, example.duties.len);
        for (example.duties, duties) |duty, *label| label.* = .{ .id = duty.id, .preserved = true };
        const status: comparison.Status = if (example.expected_terminal == .completed) .completed else .clarification;
        var observation: comparison.Observation = .{ .trial_ordinal = 1, .initial = .{ .status = status, .duties = duties, .questions_correct = true, .structural_valid = true, .issues = .{} }, .status = status, .duties = duties, .questions_correct = true, .structural_valid = true, .published = false, .corrective_sends = 0, .physical_sends = 1, .issues = .{}, .usage = .{ .input_tokens = 1, .output_tokens = 1 }, .elapsed_ns = 1, .uncertain_delivery = false, .scoring_disputed = false };
        try std.testing.expect(attributionComplete(example, observation));
        if (example.expected_terminal == .completed) {
            observation.initial.status = .clarification;
        } else observation.initial.questions_correct = false;
        try std.testing.expect(!attributionComplete(example, observation));
        observation.failure_stage = .extraction_grouping;
        try std.testing.expect(attributionComplete(example, observation));
        observation.failure_stage = null;
        observation.initial.status = status;
        observation.initial.questions_correct = true;
        if (example.expected_terminal == .clarification) {
            observation.questions_correct = false;
            try std.testing.expect(!attributionComplete(example, observation));
        }
    }
}

test "representation attribution stays separate from native paid-resource stages and audit proof" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expect(std.meta.stringToEnum(stages.Stage, "representation_admission") == null);
    try std.testing.expectEqual(comparison.FailureStage.representation_admission, std.meta.stringToEnum(comparison.FailureStage, "representation_admission").?);
    const receipt: trace.Receipt = .{ .call = 1, .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } }, .purpose = .initial_generation, .owner_kind = .specification_unit, .experiment_send = .{ .ordinal = 1 }, .request_step = "generation", .context_sha256 = @splat(0), .request_sha256 = @splat(0), .usage = operation.ProviderUsage.init(4, 3, 7) };
    const resources = try resourceStages(a, &.{receipt});
    try std.testing.expectEqual(@as(?u64, 7), resources[@intFromEnum(stages.Stage.generation)].actual_tokens);
    var facts: acquisition.Facts = .{ .trial = testRow("audit", &.{}).trial, .freeze_sha256 = "freeze", .receipts = &.{receipt}, .workflow = .{ .schema = .@"spec-e2e-report/v3", .started_at_utc = "", .status = .workflow_failed, .admission_audit = .{ .sources = &.{}, .checks = &.{}, .complete = true }, .admission_escape = .{ .status = .measured } } };
    const metric = try admissionMetric(a, facts);
    try std.testing.expectEqual(.measured, metric.status);
    facts.workflow.?.admission_escape.?.escaped_values = 1;
    try std.testing.expectError(error.CaptureMismatch, admissionMetric(a, facts));
}

test "native admission workload incidence includes zero-send invocations and excludes never-invoked setup" {
    const a = std.testing.allocator;
    const row = testRow("admission-invocation", &.{});
    var never_invoked: acquisition.Facts = .{ .trial = row.trial, .freeze_sha256 = "freeze", .directory = "trials/0001/partial", .diagnostic = "InputUnavailable" };
    try std.testing.expect(!acquisition.nativeInvocationObserved(never_invoked));
    try std.testing.expectEqual(comparison.Status.unattempted, nativeStatus(never_invoked));
    var invoked = never_invoked;
    invoked.workflow = .{ .schema = .@"spec-e2e-report/v3", .started_at_utc = "", .status = .input_invalid };
    try std.testing.expect(acquisition.nativeInvocationObserved(invoked));
    const missing = try admissionMetric(a, invoked);
    try std.testing.expectEqual(.unavailable, missing.status);
    const unknown = try admission.summarize(&.{ .{ .attempted = acquisition.nativeInvocationObserved(never_invoked), .metric = try admissionMetric(a, never_invoked) }, .{ .attempted = acquisition.nativeInvocationObserved(invoked), .metric = missing } });
    try std.testing.expectEqual(@as(u64, 1), unknown.attempted_workloads);
    try std.testing.expectEqual(@as(u64, 1), unknown.unattempted_workloads);
    try std.testing.expectEqual(@as(u64, 1), unknown.unknown_workloads);
    try std.testing.expect(!unknown.evidence_complete and unknown.workload_escape_rate == null);
    invoked.workflow.?.admission_audit = .{ .sources = &.{}, .checks = &.{}, .complete = true };
    invoked.workflow.?.admission_escape = .{ .status = .measured };
    const complete = try admission.summarize(&.{.{ .attempted = acquisition.nativeInvocationObserved(invoked), .metric = try admissionMetric(a, invoked) }});
    try std.testing.expectEqual(@as(u64, 1), complete.attempted_workloads);
    try std.testing.expectEqual(@as(u64, 1), complete.measured_workloads);
    try std.testing.expectEqual(@as(?f64, 0), complete.workload_escape_rate);
    try std.testing.expectEqual(@as(u64, 0), complete.downstream.physical_sends);
    // This diagnostic denominator does not redefine dispatched-arm scoring.
    try std.testing.expectEqual(comparison.Status.unattempted, nativeStatus(invoked));
    const dispatched = [_]trace.Receipt{.{ .call = 1, .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } }, .purpose = .initial_generation, .owner_kind = .reference_chunk, .experiment_send = .{ .ordinal = 1 }, .request_step = "extract", .context_sha256 = @splat(0), .request_sha256 = @splat(0) }};
    never_invoked.receipts = &dispatched;
    try std.testing.expect(acquisition.nativeInvocationObserved(never_invoked));
}
