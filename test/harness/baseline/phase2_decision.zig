//! Evidence-gated Phase 2 recommendations and reproducible failure examples.
//! Recommendations never execute a workflow, change policy, or prove semantics.
const std = @import("std");
const comparison = @import("../generation_comparison.zig");
const upstream = @import("upstream.zig");

pub const Category = union(enum) {
    terminal: comparison.Status,
    material: std.meta.FieldEnum(comparison.Issues),
    duty_loss,
    unexpected_clarification,
    clarification_question,
    upstream_material: upstream.Stage,
    upstream_mechanical: upstream.Stage,
};
pub const UpstreamWorkload = struct { trial_ordinal: u32, results: []const upstream.Result };
pub const FailureClass = struct {
    stage: comparison.FailureStage,
    category: Category,
    workloads: u32,
    feature_ids: []const []const u8,
    domains: []const []const u8,
    trial_ordinals: []const u32,
    repeated_identical_case: bool,
    /// Observed recurrence, not a population reliability/confidence claim.
    reproduced: bool,

    pub fn deinit(self: FailureClass, a: std.mem.Allocator) void {
        a.free(self.feature_ids);
        a.free(self.domains);
        a.free(self.trial_ordinals);
    }
};

const Builder = struct {
    stage: comparison.FailureStage,
    category: Category,
    features: std.ArrayList([]const u8) = .empty,
    domains: std.ArrayList([]const u8) = .empty,
    trials: std.ArrayList(comparison.Trial) = .empty,

    fn deinit(self: *Builder, a: std.mem.Allocator) void {
        self.features.deinit(a);
        self.domains.deinit(a);
        self.trials.deinit(a);
    }
};

fn appendUnique(a: std.mem.Allocator, list: *std.ArrayList([]const u8), value: []const u8) !void {
    for (list.items) |prior| if (std.mem.eql(u8, prior, value)) return;
    try list.append(a, value);
}

fn add(a: std.mem.Allocator, builders: *std.ArrayList(Builder), category: Category, stage: comparison.FailureStage, trial: comparison.Trial, example: comparison.Case) !void {
    const selected: *Builder = found: {
        for (builders.items) |*builder| if (builder.stage == stage and std.meta.eql(builder.category, category)) break :found builder;
        try builders.append(a, .{ .stage = stage, .category = category });
        break :found &builders.items[builders.items.len - 1];
    };
    for (selected.trials.items) |prior| if (prior.ordinal == trial.ordinal) return;
    try appendUnique(a, &selected.features, example.feature_id);
    try appendUnique(a, &selected.domains, example.domain);
    try selected.trials.append(a, trial);
}

pub fn failureClasses(a: std.mem.Allocator, inventory: comparison.Inventory, trials: []const comparison.Trial, observations: []const comparison.Observation, upstream_workloads: []const UpstreamWorkload) ![]const FailureClass {
    var builders: std.ArrayList(Builder) = .empty;
    defer {
        for (builders.items) |*builder| builder.deinit(a);
        builders.deinit(a);
    }
    for (trials) |trial| {
        const example = for (inventory.cases) |example| {
            if (std.mem.eql(u8, example.id, trial.case_id) and std.mem.eql(u8, example.feature_id, trial.feature_id)) break example;
        } else return error.InvalidFailureEvidence;
        const observation = for (observations) |observation| {
            if (observation.trial_ordinal == trial.ordinal) break observation;
        } else return error.InvalidFailureEvidence;
        for (upstream_workloads) |workload| {
            if (workload.trial_ordinal != trial.ordinal) continue;
            for (workload.results) |result| {
                if (!result.original or result.disputed) continue;
                if (result.outcome) |outcome| switch (outcome) {
                    .faithful => {},
                    .material_failure => try add(a, &builders, .{ .upstream_material = result.stage }, .extraction_grouping, trial, example),
                    .mechanical_failure => try add(a, &builders, .{ .upstream_mechanical = result.stage }, .extraction_grouping, trial, example),
                };
            }
        }
        if (observation.status == .unattempted) continue;
        const initial_known = !observation.initial_scoring_disputed;
        const final_known = !observation.scoring_disputed;
        if (!initial_known and !final_known) continue;
        const stage = observation.failure_stage orelse .unknown;
        const expected_status: comparison.Status = switch (example.expected_terminal) {
            .completed => .completed,
            .clarification => .clarification,
        };
        if (final_known and observation.status != expected_status) try add(a, &builders, .{ .terminal = observation.status }, stage, trial, example);
        const initial_material = comparison.initialOutcome(example, observation) == .material_failure;
        if (example.expected_terminal == .completed and
            ((initial_material and observation.initial.status == .clarification) or (final_known and observation.status == .clarification)))
            try add(a, &builders, .unexpected_clarification, stage, trial, example);
        if (example.expected_terminal == .clarification and
            ((initial_material and observation.initial.status == .clarification and !observation.initial.questions_correct) or
                (final_known and observation.status == .clarification and !observation.questions_correct)))
            try add(a, &builders, .clarification_question, stage, trial, example);
        var lost = false;
        for (observation.initial.duties) |duty| if (initial_known and !duty.preserved) {
            lost = true;
        };
        for (observation.duties) |duty| if (final_known and !duty.preserved) {
            lost = true;
        };
        if (lost) try add(a, &builders, .duty_loss, stage, trial, example);
        const issues = if (final_known) observation.issues else observation.initial.issues;
        inline for (std.meta.fields(comparison.Issues)) |field| if (@field(issues, field.name) != 0) {
            try add(a, &builders, .{ .material = @field(std.meta.FieldEnum(comparison.Issues), field.name) }, stage, trial, example);
        };
    }
    const classes = try a.alloc(FailureClass, builders.items.len);
    var initialized: usize = 0;
    errdefer {
        for (classes[0..initialized]) |class| class.deinit(a);
        a.free(classes);
    }
    for (builders.items, classes) |*builder, *class| {
        var repeated = false;
        for (builder.trials.items, 0..) |trial, index| for (builder.trials.items[0..index]) |prior| {
            if (std.mem.eql(u8, trial.case_id, prior.case_id) and trial.repetition != prior.repetition) repeated = true;
        };
        const ordinals = try a.alloc(u32, builder.trials.items.len);
        errdefer a.free(ordinals);
        for (builder.trials.items, ordinals) |trial, *ordinal| ordinal.* = trial.ordinal;
        const features = try a.dupe([]const u8, builder.features.items);
        errdefer a.free(features);
        const domains = try a.dupe([]const u8, builder.domains.items);
        class.* = .{ .stage = builder.stage, .category = builder.category, .workloads = @intCast(builder.trials.items.len), .feature_ids = features, .domains = domains, .trial_ordinals = ordinals, .repeated_identical_case = repeated, .reproduced = repeated or features.len >= 2 };
        initialized += 1;
    }
    return classes;
}

pub const Evidence = struct {
    native_capture_complete: bool,
    admission_audit_complete: bool,
    admission_escapes: u64,
    semantic_evidence_complete: bool,
    upstream_evidence_complete: bool,
    finding_accuracy_complete: bool,
    failure_attribution_complete: bool,
    useful_completion_complete: bool,
    useful_completion_rate: ?f64,
    qualification: enum { incomplete, infeasible, frozen },
    qualification_budget: enum { incomplete, fits, exceeds, outside_declared_scope },
};
pub const Missing = struct {
    native_capture: bool,
    admission_audit: bool,
    semantic_assessment: bool,
    upstream_assessment: bool,
    finding_accuracy: bool,
    failure_attribution: bool,
    published_rubric: bool,
    qualification_count: bool,
    qualification_budget: bool,
};
pub const Report = struct {
    decision: enum { advance, retain_baseline, revise, inconclusive },
    reason: enum { incomplete_evidence, native_admission_escape, qualification_infeasible, adequate_without_meaningful_headroom, non_generation_failure, generation_headroom, unresolved_failure_boundary },
    follow_up: enum { investigate_evidence, budget_decision, stop_redesign, owning_boundary, phase3_diagnostic },
    missing: Missing,
    source_backed_failure_classes: u32,
    reproduced_failure_classes: u32,
    full_workflow_adequate: ?bool,
    workflow_authority: bool = false,
    semantic_benefit_demonstrated: bool = false,
};

pub fn decide(protocol: comparison.Protocol, baseline: ?comparison.BaselineSummary, evidence: Evidence, classes: []const FailureClass) Report {
    var report: Report = .{
        .decision = .inconclusive,
        .reason = .incomplete_evidence,
        .follow_up = .investigate_evidence,
        .missing = .{
            .native_capture = !evidence.native_capture_complete,
            .admission_audit = !evidence.admission_audit_complete,
            .semantic_assessment = !evidence.semantic_evidence_complete,
            .upstream_assessment = !evidence.upstream_evidence_complete,
            .finding_accuracy = !evidence.finding_accuracy_complete,
            .failure_attribution = !evidence.failure_attribution_complete,
            .published_rubric = !evidence.useful_completion_complete or evidence.useful_completion_rate == null,
            .qualification_count = evidence.qualification == .incomplete,
            .qualification_budget = evidence.qualification_budget == .incomplete or evidence.qualification_budget == .outside_declared_scope,
        },
        .source_backed_failure_classes = 0,
        .reproduced_failure_classes = 0,
        .full_workflow_adequate = null,
    };
    if (evidence.admission_escapes != 0) {
        report.decision = .revise;
        report.reason = .native_admission_escape;
        report.follow_up = .owning_boundary;
        return report;
    }
    var reproduced_generation_loss = false;
    var other_loss = false;
    for (classes) |class| {
        if (class.stage == .unknown) report.missing.failure_attribution = true;
        if (class.category != .terminal and class.category != .upstream_mechanical) report.source_backed_failure_classes += 1;
        if (class.reproduced) report.reproduced_failure_classes += 1;
        if (class.stage == .generation) {
            reproduced_generation_loss = reproduced_generation_loss or (class.reproduced and class.category != .terminal);
        } else if (class.stage != .unknown) other_loss = true;
    }
    inline for (std.meta.fields(Missing)) |field| if (@field(report.missing, field.name)) return report;
    const summary = baseline orelse return report;
    if (summary.adequacy == .insufficient or summary.meaningful_initial_headroom == null) return report;
    report.full_workflow_adequate = summary.adequacy == .adequate and evidence.useful_completion_rate.? >= protocol.thresholds.minimum_useful_completion;
    if (evidence.qualification == .infeasible or evidence.qualification_budget == .exceeds) {
        report.decision = .revise;
        report.reason = .qualification_infeasible;
        report.follow_up = .budget_decision;
    } else if (report.full_workflow_adequate.? and !summary.meaningful_initial_headroom.?) {
        report.decision = .retain_baseline;
        report.reason = .adequate_without_meaningful_headroom;
        report.follow_up = .stop_redesign;
    } else if (other_loss) {
        report.decision = .revise;
        report.reason = .non_generation_failure;
        report.follow_up = .owning_boundary;
    } else if (reproduced_generation_loss and summary.meaningful_initial_headroom.?) {
        report.decision = .advance;
        report.reason = .generation_headroom;
        report.follow_up = .phase3_diagnostic;
    } else {
        report.reason = .unresolved_failure_boundary;
    }
    return report;
}

const Test = struct {
    fn summary() comparison.BaselineSummary {
        const estimate: comparison.QualificationEstimate = .{ .status = .sized, .reason = null, .baseline_feature_stddev = 0, .required_features = 8, .paired_workloads = 144, .sends_at_observed_worst = 144, .tokens_at_observed_worst = 144, .observed_cost_budget = .fits };
        return .{ .adequacy = .below_target, .meaningful_initial_headroom = true, .fidelity_features = 8, .robustness_features = 8, .fidelity_sample_stddev = 0, .robustness_sample_stddev = 0, .qualification = estimate, .qualification_robustness = estimate, .qualification_metric = .first_pass_fidelity };
    }
    const complete: Evidence = .{ .native_capture_complete = true, .admission_audit_complete = true, .admission_escapes = 0, .semantic_evidence_complete = true, .upstream_evidence_complete = true, .finding_accuracy_complete = true, .failure_attribution_complete = true, .useful_completion_complete = true, .useful_completion_rate = 0.7, .qualification = .frozen, .qualification_budget = .fits };
    const loss: FailureClass = .{ .stage = .generation, .category = .duty_loss, .workloads = 2, .feature_ids = &.{"rooms"}, .domains = &.{"booking"}, .trial_ordinals = &.{ 1, 2 }, .repeated_identical_case = true, .reproduced = true };
    fn protocol(a: std.mem.Allocator) !comparison.Protocol {
        return comparison.parseProtocol(a, @embedFile("../../calibration/semantic-simplicity/protocol.json"));
    }
};

test "Phase 2 decisions retain adequate baseline and route measured failures to their owning boundary" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const protocol = try Test.protocol(arena.allocator());
    try std.testing.expectEqual(.advance, decide(protocol, Test.summary(), Test.complete, &.{Test.loss}).decision);
    var review = Test.loss;
    review.stage = .review;
    const revised = decide(protocol, Test.summary(), Test.complete, &.{review});
    try std.testing.expectEqual(.revise, revised.decision);
    try std.testing.expectEqual(.owning_boundary, revised.follow_up);
    var representation = Test.loss;
    representation.stage = .representation_admission;
    try std.testing.expectEqual(.owning_boundary, decide(protocol, Test.summary(), Test.complete, &.{representation}).follow_up);
    var admission_evidence = Test.complete;
    admission_evidence.admission_escapes = 1;
    const escaped = decide(protocol, null, admission_evidence, &.{});
    try std.testing.expectEqual(.native_admission_escape, escaped.reason);
    try std.testing.expectEqual(.owning_boundary, escaped.follow_up);
    admission_evidence = Test.complete;
    admission_evidence.admission_audit_complete = false;
    const unaudited = decide(protocol, Test.summary(), admission_evidence, &.{Test.loss});
    try std.testing.expectEqual(.inconclusive, unaudited.decision);
    try std.testing.expect(unaudited.missing.admission_audit);
    var summary = Test.summary();
    summary.adequacy = .adequate;
    summary.meaningful_initial_headroom = false;
    var evidence = Test.complete;
    evidence.useful_completion_rate = 0.9;
    const retained = decide(protocol, summary, evidence, &.{});
    try std.testing.expectEqual(.retain_baseline, retained.decision);
    try std.testing.expect(!retained.workflow_authority and !retained.semantic_benefit_demonstrated);
}

test "unknown cause missing rubric evidence and infeasible counts never advance Phase 2" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const protocol = try Test.protocol(arena.allocator());
    var evidence = Test.complete;
    evidence.failure_attribution_complete = false;
    try std.testing.expectEqual(.inconclusive, decide(protocol, Test.summary(), evidence, &.{Test.loss}).decision);
    evidence = Test.complete;
    evidence.useful_completion_complete = false;
    try std.testing.expectEqual(.inconclusive, decide(protocol, Test.summary(), evidence, &.{Test.loss}).decision);
    evidence = Test.complete;
    evidence.qualification_budget = .exceeds;
    const exceeded = decide(protocol, Test.summary(), evidence, &.{Test.loss});
    try std.testing.expectEqual(.revise, exceeded.decision);
    try std.testing.expectEqual(.budget_decision, exceeded.follow_up);
    var unknown = Test.loss;
    unknown.stage = .unknown;
    try std.testing.expectEqual(.inconclusive, decide(protocol, Test.summary(), Test.complete, &.{unknown}).decision);
    var single = Test.loss;
    single.reproduced = false;
    try std.testing.expectEqual(.inconclusive, decide(protocol, Test.summary(), Test.complete, &.{single}).decision);
    var malformed = Test.loss;
    malformed.category = .{ .terminal = .malformed };
    try std.testing.expectEqual(.inconclusive, decide(protocol, Test.summary(), Test.complete, &.{malformed}).decision);
}

test "failure classes retain exact examples and distinguish repeated requests from harmless variants" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try comparison.parseInventory(a, @embedFile("../../calibration/semantic-simplicity/cases.json"));
    const duties = [_]comparison.DutyAssessment{.{ .id = "retained-duty", .preserved = true }};
    const template: comparison.Observation = .{ .trial_ordinal = 1, .initial = .{ .status = .completed, .duties = &duties, .questions_correct = true, .structural_valid = true, .issues = .{} }, .status = .completed, .duties = &duties, .questions_correct = true, .structural_valid = true, .published = false, .corrective_sends = 0, .physical_sends = 1, .issues = .{ .harmful_diagnoses = 1 }, .usage = .{ .input_tokens = 1, .output_tokens = 1 }, .elapsed_ns = 1, .uncertain_delivery = false, .scoring_disputed = false, .failure_stage = .review };
    const trials = [_]comparison.Trial{
        .{ .ordinal = 1, .case_id = "room-booking.base", .feature_id = "room-booking", .arm = .A, .repetition = 1 },
        .{ .ordinal = 2, .case_id = "room-booking.equivalent", .feature_id = "room-booking", .arm = .A, .repetition = 2 },
        .{ .ordinal = 3, .case_id = "room-booking.base", .feature_id = "room-booking", .arm = .A, .repetition = 2 },
        .{ .ordinal = 4, .case_id = "instrument-release.base", .feature_id = "instrument-release", .arm = .A, .repetition = 1 },
    };
    var observations: [trials.len]comparison.Observation = @splat(template);
    for (&observations, trials) |*observation, trial| observation.trial_ordinal = trial.ordinal;
    const variants = try failureClasses(a, inventory, trials[0..2], observations[0..2], &.{});
    try std.testing.expectEqual(@as(usize, 1), variants.len);
    try std.testing.expect(!variants[0].repeated_identical_case and !variants[0].reproduced);
    const repeated = try failureClasses(a, inventory, &trials, &observations, &.{});
    try std.testing.expectEqual(@as(usize, 1), repeated.len);
    try std.testing.expect(repeated[0].repeated_identical_case and repeated[0].reproduced);
    try std.testing.expectEqual(@as(usize, 2), repeated[0].feature_ids.len);
    try std.testing.expectEqual(@as(usize, 2), repeated[0].domains.len);
    try std.testing.expectEqualSlices(u32, &.{ 1, 2, 3, 4 }, repeated[0].trial_ordinals);
    try std.testing.expectEqual(comparison.FailureStage.review, repeated[0].stage);
    observations[3].scoring_disputed = true;
    const disputed = try failureClasses(a, inventory, &trials, &observations, &.{});
    try std.testing.expectEqual(@as(u32, 3), disputed[0].workloads);
    for (&observations) |*observation| {
        observation.issues = .{};
        observation.scoring_disputed = false;
    }
    const original_loss: upstream.Result = .{ .call = 1, .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } }, .stage = .extraction, .original = true, .output_id = "original-source-response", .outcome = .material_failure, .mechanical_failure = false, .disputed = false };
    var another_loss = original_loss;
    another_loss.call = 2;
    another_loss.origin.request.value = 2;
    another_loss.output_id = "another-original-source-response";
    var correction = original_loss;
    correction.original = false;
    correction.call = 3;
    correction.origin.attempt.value = 2;
    correction.output_id = "corrected-source-response";
    correction.outcome = .faithful;
    const native_results = [_]upstream.Result{ original_loss, another_loss, correction };
    const upstream_workloads = [_]UpstreamWorkload{
        .{ .trial_ordinal = 1, .results = &native_results },
        .{ .trial_ordinal = 3, .results = &native_results },
    };
    const upstream_failures = try failureClasses(a, inventory, &trials, &observations, &upstream_workloads);
    try std.testing.expectEqual(@as(usize, 1), upstream_failures.len);
    try std.testing.expectEqual(@as(u32, 2), upstream_failures[0].workloads);
    try std.testing.expect(upstream_failures[0].reproduced);
    try std.testing.expectEqual(comparison.FailureStage.extraction_grouping, upstream_failures[0].stage);
    try std.testing.expectEqual(.revise, decide(try Test.protocol(a), Test.summary(), Test.complete, upstream_failures).decision);
}
