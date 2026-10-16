//! Offline comparison protocol and labelled-result accounting. No inference,
//! semantic classifier, provider binding, or workflow/publication authority.
const std = @import("std");
const contracts = @import("contracts.zig");
const Temperature = @import("../../src/domain/model_controls.zig").Temperature;
const identity = @import("../../src/domain/llm_provider_identity.zig");
const cost_policy = @import("model_cost_policy.zig");

pub const Error = std.mem.Allocator.Error || error{InvalidComparisonContract};
pub const Arm = enum { A, C };
/// Baseline observes the unchanged A contract only; paired is the frozen A/C comparison.
pub const Mode = enum { baseline, paired };
pub fn activeArms(mode: Mode) []const Arm {
    return switch (mode) {
        .baseline => &.{.A},
        .paired => &.{ .A, .C },
    };
}
pub const Partition = enum { development, qualification };
pub const Variant = enum { base, equivalent, changed };
pub const Terminal = enum { completed, clarification };
pub const Source = struct { id: []const u8, path: []const u8, text: []const u8 };
pub const SourceRef = struct { source_id: []const u8, quote: []const u8 };
pub const Duty = struct { id: []const u8, description: []const u8, source_refs: []const SourceRef, exact_values: []const []const u8 };
pub const Case = struct {
    id: []const u8,
    feature_id: []const u8,
    partition: Partition,
    variant: Variant,
    domain: []const u8,
    size: enum { small, medium },
    risk_tags: []const []const u8,
    sources: []const Source,
    duties: []const Duty,
    expected_terminal: Terminal,
    expected_questions: []const []const u8,
    permissible_alternatives: []const []const u8,
    forbidden_additions: []const []const u8,
};
pub const Inventory = struct { schema: u32, cases: []const Case };
pub const Thresholds = struct {
    minimum_fidelity: f64,
    minimum_robust_success: f64,
    minimum_useful_completion: f64,
    maximum_material_harm: f64,
    maximum_false_gap: f64,
    minimum_effect: f64,
    minimum_brittleness_reduction: f64,
    minimum_common_original_success: u32,
    maximum_token_ratio: f64,
    maximum_latency_ratio: f64,
};
pub const QualificationMetric = enum { first_pass_fidelity };
pub const Qualification = struct { metric: QualificationMetric, minimum_features: u32, maximum_features: u32, confidence: f64, precision: f64 };
pub const Protocol = struct {
    schema: u32,
    cohort: enum { small },
    provider: []const u8,
    api: enum { converse },
    model: []const u8,
    generation_slot: []const u8,
    region: []const u8,
    reasoning_effort: enum { low },
    response_mode: enum { native_schema },
    temperature: f64,
    max_output_tokens: u32,
    repetitions: u32,
    arms: []const Arm,
    development_features: u32,
    qualification: Qualification,
    analysis: struct {
        method: enum { paired_feature_bootstrap },
        resamples: u32,
        seed: u64,
        minimum_effect_lower_bound: f64,
        primary_brittleness: enum { representation_sensitivity },
    },
    thresholds: Thresholds,
    limits: struct { maximum_sends: u32, maximum_actual_tokens: u64 },
    live_authorized: bool,
};
pub const Trial = struct { ordinal: u32, case_id: []const u8, feature_id: []const u8, arm: Arm, repetition: u32 };
pub const DutyAssessment = struct { id: []const u8, preserved: bool };
pub const Issues = struct {
    unsupported_behavior: u32 = 0,
    lost_restrictions: u32 = 0,
    wrong_support: u32 = 0,
    harmful_diagnoses: u32 = 0,
    harmful_repairs: u32 = 0,
    false_gaps: u32 = 0,
};
pub const IssueRates = struct {
    unsupported_behavior: f64 = 0,
    lost_restrictions: f64 = 0,
    wrong_support: f64 = 0,
    harmful_diagnoses: f64 = 0,
    harmful_repairs: f64 = 0,
    false_gaps: f64 = 0,
};
pub const Usage = struct { input_tokens: u64, output_tokens: u64 };
pub const Status = enum { unattempted, completed, clarification, provider_failed, malformed, truncated, blocked };
pub const StatusCounts = struct {
    unattempted: u32 = 0,
    completed: u32 = 0,
    clarification: u32 = 0,
    provider_failed: u32 = 0,
    malformed: u32 = 0,
    truncated: u32 = 0,
    blocked: u32 = 0,
};
/// Supplied assessed origin. A later terminal step alone cannot establish where
/// a semantic loss first arose; absent attribution is reported explicitly.
pub const FailureStage = enum { extraction_grouping, generation, representation_admission, review, repair, provider, unknown };
pub const FailureStages = struct {
    extraction_grouping: u32 = 0,
    generation: u32 = 0,
    representation_admission: u32 = 0,
    review: u32 = 0,
    repair: u32 = 0,
    provider: u32 = 0,
    unknown: u32 = 0,
};
/// Explicit labels for the original response. Final/corrected content never
/// substitutes for these labels, including when a later review harms good work.
pub const InitialAssessment = struct {
    status: Status,
    duties: []const DutyAssessment,
    questions_correct: bool,
    structural_valid: bool,
    issues: Issues,
};
pub const Observation = struct {
    trial_ordinal: u32,
    initial: InitialAssessment,
    status: Status,
    duties: []const DutyAssessment,
    questions_correct: bool,
    structural_valid: bool,
    published: bool,
    corrective_sends: u32,
    physical_sends: u32,
    /// Cumulative issue events for the complete chain, including initial
    /// content. A correction cannot remove an already observed event.
    issues: Issues,
    usage: ?Usage,
    elapsed_ns: ?u64,
    uncertain_delivery: bool,
    scoring_disputed: bool,
    /// Original assessment completeness is independent of later missing labels.
    initial_scoring_disputed: bool = false,
    failure_stage: ?FailureStage = null,
};
pub const EvidenceScope = enum { synthetic, diagnostic };
pub const ResourceTotals = struct {
    physical_sends: u64 = 0,
    simulated_physical_sends: u64 = 0,
    actual_tokens: u64 = 0,
    simulated_tokens: u64 = 0,
    corrective_sends: u64 = 0,
    usage_complete: bool = true,
    total_elapsed_ns: ?u64 = 0,
};
pub const FeatureScore = struct {
    feature_id: []const u8,
    arm: Arm,
    attempted: u32,
    well_posed_attempted: u32,
    first_pass_successes: u32,
    structural_successes: u32,
    useful_completions: u32,
    expected_gap_attempted: u32,
    correct_clarifications: u32,
    robust_bundles: u32,
    /// Attempted bundles include every repeat with at least one dispatched arm
    /// workload. A partial bundle cannot be successful or promote the panel.
    total_bundles: u32,
    planned_bundles: u32 = 0,
    unattempted_bundles: u32 = 0,
    partial_bundles: u32 = 0,
    unknown_bundles: u32 = 0,
    repeat_inconsistent: bool,
    repeat_coverage_complete: bool = false,
    variants: [3]VariantScore = variantScores(),
    material_workloads: u32,
    issues: Issues = .{},
    /// Each category counts an affected attempted workload once; event counts
    /// remain in issues and may be larger than the workload denominator.
    material_incidence: Issues = .{},
    omitted_duty_labels: u32 = 0,
    false_gap_workloads: u32,
    common_original_success_pairs: u32,
    common_representation_eligible_pairs: u32 = 0,
    common_representation_failures: u32,
    original_success_pairs: u32 = 0,
    representation_eligible_pairs: u32 = 0,
    representation_failures: u32 = 0,
    statuses: StatusCounts = .{},
    failure_stages: FailureStages = .{},
    resources: ResourceTotals = .{},
};
pub const InitialOutcome = enum { semantic_success, material_failure, mechanical_failure, unknown, unattempted };
pub const VariantScore = struct {
    variant: Variant,
    planned_repetitions: u32 = 0,
    attempted_repetitions: u32 = 0,
    semantic_successes: u32 = 0,
    material_failures: u32 = 0,
    mechanical_failures: u32 = 0,
    unknown: u32 = 0,
    unattempted: u32 = 0,
    repeat_inconsistent: bool = false,
    semantic_coverage_complete: bool = false,
};
fn variantScores() [3]VariantScore {
    return .{ .{ .variant = .base }, .{ .variant = .equivalent }, .{ .variant = .changed } };
}
pub const RiskScore = struct {
    risk_tag: []const u8,
    arm: Arm,
    independent_features: u32 = 0,
    well_posed_features: u32 = 0,
    planned_workloads: u32 = 0,
    attempted_workloads: u32 = 0,
    unattempted_workloads: u32 = 0,
    well_posed_attempted: u32 = 0,
    material_workloads: u32 = 0,
    false_gap_workloads: u32 = 0,
    scoring_disputed_workloads: u32 = 0,
    issues: Issues = .{},
    material_incidence: Issues = .{},
    material_harm: ?f64 = null,
    false_gap: ?f64 = null,
    material_category_rates: IssueRates = .{},
};
pub const ArmScore = struct {
    arm: Arm,
    features: u32,
    attempted_features: u32 = 0,
    well_posed_features: u32,
    first_pass_fidelity: f64,
    structural_success: f64,
    useful_completion: f64,
    clarification_correctness: ?f64,
    robust_success: f64,
    repeat_inconsistency: ?f64,
    repeat_inconsistent_features: u32 = 0,
    repeat_covered_features: u32 = 0,
    material_harm: f64,
    issues: Issues = .{},
    material_incidence: Issues = .{},
    material_category_rates: IssueRates = .{},
    false_gap: f64,
    common_representation_sensitivity: ?f64,
    common_original_success_features: u32,
    common_representation_eligible_features: u32 = 0,
    common_original_success_pairs: u32,
    common_representation_eligible_pairs: u32 = 0,
    common_representation_failures: u32 = 0,
    brittleness_evidence_sufficient: bool,
    representation_sensitivity: ?f64 = null,
    original_success_features: u32 = 0,
    original_success_pairs: u32 = 0,
    representation_eligible_features: u32 = 0,
    representation_eligible_pairs: u32 = 0,
    representation_failures: u32 = 0,
};
pub const ArmResources = struct {
    arm: Arm,
    attempted_workloads: u32,
    physical_sends: u64,
    simulated_physical_sends: u64,
    actual_tokens: u64,
    simulated_tokens: u64,
    usage_complete: bool,
    elapsed_complete: bool,
    median_workload_tokens: ?f64,
    worst_workload_tokens: ?u64,
    median_workload_elapsed_ns: ?f64,
    worst_workload_elapsed_ns: ?u64,
    // Both available scopes exclude production publication. A zero useful
    // completion denominator cannot yield a fabricated cost per completion.
    tokens_per_useful_completion: ?f64 = null,
};
pub const QualificationEstimate = struct {
    status: enum { insufficient, infeasible, sized },
    reason: ?enum { incomplete_evidence, too_few_features, feature_bound, minimum_send_budget },
    baseline_feature_stddev: ?f64,
    required_features: ?u32,
    paired_workloads: ?u64,
    /// Forecasts reuse the observed A workload envelope. They do not assert
    /// that an unobserved candidate will consume the same resources.
    sends_at_observed_worst: ?u64,
    tokens_at_observed_worst: ?u64,
    observed_cost_budget: enum { unavailable, fits, exceeds },
};
pub const BaselineSummary = struct {
    adequacy: enum { insufficient, below_target, adequate },
    meaningful_initial_headroom: ?bool,
    fidelity_features: u32,
    robustness_features: u32,
    fidelity_sample_stddev: ?f64,
    robustness_sample_stddev: ?f64,
    qualification: QualificationEstimate,
    qualification_robustness: QualificationEstimate,
    /// Explicit frozen selector; robustness sizing is informative only.
    qualification_metric: QualificationMetric,
};
pub const Scorecard = struct {
    schema: u32 = 1,
    mode: Mode,

    scope: EvidenceScope,
    planned: u32,
    attempted: u32,
    unattempted: u32,
    physical_sends: u64,
    simulated_physical_sends: u64,
    actual_tokens: u64,
    simulated_tokens: u64,
    usage_complete: bool,
    elapsed_complete: bool,
    halt_required: bool,
    inconclusive: bool,
    issues: Issues,
    material_incidence: Issues = .{},
    omitted_duty_labels: u32,
    semantic_benefit_demonstrated: bool = false,
    workflow_authority: bool = false,
    features: []const FeatureScore,
    arms: []const ArmScore,
    resources: []const ArmResources,
    risk_strata: []const RiskScore = &.{},
    statuses: StatusCounts = .{},
    failure_stages: FailureStages = .{},
    baseline: ?BaselineSummary = null,

    /// Feature identifiers borrow the inventory; its owner must outlive this
    /// report. The report owns its feature, arm, resource and risk arrays.
    pub fn deinit(self: Scorecard, a: std.mem.Allocator) void {
        a.free(self.features);
        a.free(self.arms);
        a.free(self.resources);
        a.free(self.risk_strata);
    }
};

pub fn decode(comptime T: type, a: std.mem.Allocator, bytes: []const u8) Error!T {
    return contracts.decode(T, a, bytes) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidComparisonContract,
    };
}
pub fn parseInventory(a: std.mem.Allocator, bytes: []const u8) Error!Inventory {
    const inventory = try decode(Inventory, a, bytes);
    try validateInventory(inventory);
    return inventory;
}
pub fn parseProtocol(a: std.mem.Allocator, bytes: []const u8) Error!Protocol {
    const protocol = try decode(Protocol, a, bytes);
    try validateProtocol(protocol);
    return protocol;
}
fn validText(value: []const u8) bool {
    return contracts.text(value);
}
fn texts(values: []const []const u8) Error!void {
    for (values, 0..) |value, index| {
        if (!validText(value)) return error.InvalidComparisonContract;
        for (values[0..index]) |prior| if (std.mem.eql(u8, value, prior)) return error.InvalidComparisonContract;
    }
}
pub fn validateCase(example: Case) Error!void {
    if (!contracts.id(example.id) or !contracts.id(example.feature_id) or !contracts.id(example.domain) or
        example.sources.len == 0 or example.duties.len == 0 or example.risk_tags.len == 0) return error.InvalidComparisonContract;
    try texts(example.risk_tags);
    try texts(example.expected_questions);
    try texts(example.permissible_alternatives);
    try texts(example.forbidden_additions);
    if ((example.expected_terminal == .clarification) != (example.expected_questions.len != 0)) return error.InvalidComparisonContract;
    for (example.sources, 0..) |source, index| {
        if (!contracts.id(source.id) or !validText(source.text)) return error.InvalidComparisonContract;
        contracts.path(source.path) catch return error.InvalidComparisonContract;
        for (example.sources[0..index]) |prior| {
            if (std.mem.eql(u8, source.id, prior.id) or std.mem.eql(u8, source.path, prior.path)) return error.InvalidComparisonContract;
        }
    }
    for (example.duties, 0..) |duty, index| {
        if (!contracts.id(duty.id) or !validText(duty.description) or duty.source_refs.len == 0) return error.InvalidComparisonContract;
        for (example.duties[0..index]) |prior| if (std.mem.eql(u8, duty.id, prior.id)) return error.InvalidComparisonContract;
        for (duty.source_refs, 0..) |reference, at| {
            if (!validText(reference.quote)) return error.InvalidComparisonContract;
            const source = for (example.sources) |source| {
                if (std.mem.eql(u8, source.id, reference.source_id)) break source;
            } else return error.InvalidComparisonContract;
            if (std.mem.indexOf(u8, source.text, reference.quote) == null) return error.InvalidComparisonContract;
            for (duty.source_refs[0..at]) |prior| if (std.mem.eql(u8, prior.source_id, reference.source_id) and std.mem.eql(u8, prior.quote, reference.quote)) return error.InvalidComparisonContract;
        }
        try texts(duty.exact_values);
        for (duty.exact_values) |literal| {
            for (duty.source_refs) |reference| {
                if (std.mem.indexOf(u8, reference.quote, literal) != null) break;
            } else return error.InvalidComparisonContract;
        }
    }
}
pub fn validateInventory(inventory: Inventory) Error!void {
    if (inventory.schema != 1 or inventory.cases.len == 0) return error.InvalidComparisonContract;
    var development: u32 = 0;
    var qualification: u32 = 0;
    for (inventory.cases, 0..) |example, index| {
        try validateCase(example);
        for (inventory.cases[0..index]) |prior| {
            if (std.mem.eql(u8, prior.id, example.id)) return error.InvalidComparisonContract;
            if (std.mem.eql(u8, prior.feature_id, example.feature_id) and
                (prior.partition != example.partition or prior.variant == example.variant or
                    !std.mem.eql(u8, prior.domain, example.domain) or prior.size != example.size)) return error.InvalidComparisonContract;
        }
        var variants: [3]bool = .{ false, false, false };
        for (inventory.cases) |sibling| if (std.mem.eql(u8, sibling.feature_id, example.feature_id)) {
            variants[@intFromEnum(sibling.variant)] = true;
        };
        for (variants) |present| if (!present) return error.InvalidComparisonContract;
        if (example.variant == .base) {
            if (example.partition == .development) development += 1 else qualification += 1;
        }
    }
    if (development == 0 or qualification == 0) return error.InvalidComparisonContract;
}
fn fraction(value: f64) bool {
    return std.math.isFinite(value) and value >= 0 and value <= 1;
}
pub fn validateProtocol(protocol: Protocol) Error!void {
    const provider = identity.ProviderId.parse(protocol.provider) orelse return error.InvalidComparisonContract;
    const model = identity.ModelId.parse(protocol.model) orelse return error.InvalidComparisonContract;
    _ = identity.ModelSlotId.parse(protocol.generation_slot) orelse return error.InvalidComparisonContract;
    cost_policy.require(provider, model) catch return error.InvalidComparisonContract;
    if (protocol.schema != 1 or !std.mem.eql(u8, protocol.region, "ap-southeast-2") or
        protocol.live_authorized or protocol.temperature != Temperature.fixed.wireValue() or protocol.max_output_tokens != 16384 or
        protocol.repetitions < 3 or protocol.development_features == 0 or protocol.arms.len != 2 or
        protocol.arms[0] != .A or protocol.arms[1] != .C or protocol.limits.maximum_sends == 0 or
        protocol.limits.maximum_actual_tokens == 0) return error.InvalidComparisonContract;
    const qualification = protocol.qualification;
    if (qualification.minimum_features == 0 or qualification.maximum_features < qualification.minimum_features or
        qualification.confidence != 0.95 or !fraction(qualification.precision) or qualification.precision == 0 or
        protocol.analysis.resamples == 0 or !fraction(protocol.analysis.minimum_effect_lower_bound)) return error.InvalidComparisonContract;
    const t = protocol.thresholds;
    inline for (.{ t.minimum_fidelity, t.minimum_robust_success, t.minimum_useful_completion, t.maximum_material_harm, t.maximum_false_gap, t.minimum_effect, t.minimum_brittleness_reduction }) |value| {
        if (!fraction(value)) return error.InvalidComparisonContract;
    }
    if (t.minimum_fidelity == 0 or t.minimum_robust_success == 0 or t.minimum_useful_completion == 0 or
        t.minimum_effect == 0 or t.minimum_brittleness_reduction == 0 or t.minimum_common_original_success == 0 or
        t.minimum_common_original_success > protocol.development_features or
        !std.math.isFinite(t.maximum_token_ratio) or t.maximum_token_ratio <= 0 or
        !std.math.isFinite(t.maximum_latency_ratio) or t.maximum_latency_ratio <= 0) return error.InvalidComparisonContract;
    const cases = std.math.mul(u64, protocol.development_features, 3) catch return error.InvalidComparisonContract;
    const repeats = std.math.mul(u64, cases, protocol.repetitions) catch return error.InvalidComparisonContract;
    const workloads = std.math.mul(u64, repeats, protocol.arms.len) catch return error.InvalidComparisonContract;
    if (workloads > protocol.limits.maximum_sends or workloads > std.math.maxInt(u32)) return error.InvalidComparisonContract;
}
/// The sizing rule is frozen before baseline observations. Above-panel demand is
/// an infeasible qualification, never a silent reduction to the available cases.
pub fn sizeQualification(protocol: Protocol, baseline_stddev: f64) Error!u32 {
    try validateProtocol(protocol);
    if (!std.math.isFinite(baseline_stddev) or baseline_stddev < 0 or baseline_stddev > 1) return error.InvalidComparisonContract;
    const n = @ceil(std.math.pow(f64, 1.96 * baseline_stddev / protocol.qualification.precision, 2));
    if (n > @as(f64, @floatFromInt(protocol.qualification.maximum_features))) return error.InvalidComparisonContract;
    return @max(protocol.qualification.minimum_features, @as(u32, @intFromFloat(n)));
}
pub const Interval = struct { mean: f64, lower: f64, upper: f64, independent_features: u32, resamples: u32, seed: u64 };
/// Paired deltas have already been reduced to one equally weighted value per
/// independent feature. The interval quantifies this frozen panel; it does not
/// prove population reliability or discover the semantic labels.
pub fn pairedInterval(a: std.mem.Allocator, protocol: Protocol, deltas: []const f64) Error!Interval {
    try validateProtocol(protocol);
    if (deltas.len < 2 or deltas.len > std.math.maxInt(u32)) return error.InvalidComparisonContract;
    var mean: f64 = 0;
    for (deltas) |delta| {
        if (!std.math.isFinite(delta) or delta < -1 or delta > 1) return error.InvalidComparisonContract;
        mean += delta;
    }
    mean /= @as(f64, @floatFromInt(deltas.len));
    const resamples = try a.alloc(f64, protocol.analysis.resamples);
    defer a.free(resamples);
    var rng: std.Random.DefaultPrng = .init(protocol.analysis.seed);
    for (resamples) |*sample| {
        sample.* = 0;
        for (0..deltas.len) |_| sample.* += deltas[rng.random().uintLessThan(usize, deltas.len)];
        sample.* /= @as(f64, @floatFromInt(deltas.len));
    }
    std.mem.sort(f64, resamples, {}, struct {
        fn less(_: void, left: f64, right: f64) bool {
            return left < right;
        }
    }.less);
    const lower: usize = @intFromFloat(@floor(@as(f64, @floatFromInt(resamples.len - 1)) * 0.025));
    const upper: usize = @intFromFloat(@ceil(@as(f64, @floatFromInt(resamples.len - 1)) * 0.975));
    return .{ .mean = mean, .lower = resamples[lower], .upper = resamples[upper], .independent_features = @intCast(deltas.len), .resamples = protocol.analysis.resamples, .seed = protocol.analysis.seed };
}
/// This projection intentionally has no duties, scoring rubric, topology seeds,
/// terminal labels, or expected answers. It is data, not a production packet.
pub fn sourceInput(a: std.mem.Allocator, example: Case) Error![]const u8 {
    try validateCase(example);
    return std.json.Stringify.valueAlloc(a, .{ .case_id = example.id, .scope = "complete_source_backed_record_collection", .sources = example.sources }, .{}) catch error.OutOfMemory;
}
pub fn plan(a: std.mem.Allocator, inventory: Inventory, protocol: Protocol, mode: Mode) Error![]Trial {
    try validateInventory(inventory);
    try validateProtocol(protocol);
    var development: u32 = 0;
    var qualification: u32 = 0;
    for (inventory.cases) |example| if (example.variant == .base) {
        if (example.partition == .development) development += 1 else qualification += 1;
    };
    if (development != protocol.development_features or qualification < protocol.qualification.maximum_features) return error.InvalidComparisonContract;
    const count = protocol.development_features * 3 * protocol.repetitions * activeArms(mode).len;
    const trials = try a.alloc(Trial, count);
    var at: usize = 0;
    for (inventory.cases) |example| if (example.partition == .development) {
        for (0..protocol.repetitions) |repetition| {
            // A baseline never manufactures a C observation. Paired experiments
            // counterbalance the first arm across consecutive case/repeat pairs.
            const first: Arm = if (at / 2 % 2 == 0) .A else .C;
            const order = [_]Arm{ first, if (first == .A) .C else .A };
            for (if (mode == .baseline) activeArms(mode) else &order) |arm| {
                trials[at] = .{ .ordinal = @intCast(at + 1), .case_id = example.id, .feature_id = example.feature_id, .arm = arm, .repetition = @intCast(repetition + 1) };
                at += 1;
            }
        }
    };
    return trials;
}
fn material(issues: Issues) bool {
    return issues.unsupported_behavior != 0 or issues.lost_restrictions != 0 or issues.wrong_support != 0 or issues.harmful_diagnoses != 0 or issues.harmful_repairs != 0 or issues.false_gaps != 0;
}
fn labelledMaterial(example: Case, observation: Observation) bool {
    return material(observation.issues) or
        assessmentMaterial(example, observation.initial.status, observation.initial.duties, observation.initial.questions_correct, observation.initial_scoring_disputed) or
        assessmentMaterial(example, observation.status, observation.duties, observation.questions_correct, observation.scoring_disputed);
}
fn falseGap(example: Case, observation: Observation) bool {
    return example.expected_terminal == .completed and (observation.issues.false_gaps != 0 or observation.initial.status == .clarification or observation.status == .clarification);
}
fn assessmentMaterial(example: Case, status: Status, duties: []const DutyAssessment, questions_correct: bool, scoring_disputed: bool) bool {
    for (duties) |duty| if (!duty.preserved) return true;
    if (status == .completed or status == .clarification) {
        return (example.expected_terminal == .completed and status == .clarification) or
            (example.expected_terminal == .clarification and (status != .clarification or (!scoring_disputed and !questions_correct)));
    }
    return false;
}
fn dutyOmitted(duties: []const DutyAssessment, id: []const u8) bool {
    for (duties) |duty| if (std.mem.eql(u8, duty.id, id) and !duty.preserved) return true;
    return false;
}
fn caseFor(inventory: Inventory, trial: Trial) Error!Case {
    for (inventory.cases) |example| if (std.mem.eql(u8, example.id, trial.case_id) and std.mem.eql(u8, example.feature_id, trial.feature_id)) return example;
    return error.InvalidComparisonContract;
}
fn observationFor(observations: []const Observation, ordinal: u32) Error!Observation {
    for (observations) |observation| if (observation.trial_ordinal == ordinal) return observation;
    return error.InvalidComparisonContract;
}
fn validateObservation(example: Case, observation: Observation) Error!void {
    try validateInitial(example, observation.initial, observation.initial_scoring_disputed);
    inline for (std.meta.fields(Issues)) |field| {
        if (@field(observation.issues, field.name) < @field(observation.initial.issues, field.name)) return error.InvalidComparisonContract;
    }
    if (observation.status == .unattempted) {
        if (observation.initial.status != .unattempted) return error.InvalidComparisonContract;
        if (observation.physical_sends != 0 or observation.corrective_sends != 0 or observation.usage != null or observation.elapsed_ns != null or
            observation.duties.len != 0 or observation.published or observation.structural_valid or observation.questions_correct or
            observation.uncertain_delivery or observation.scoring_disputed or observation.initial_scoring_disputed or observation.failure_stage != null or material(observation.issues)) return error.InvalidComparisonContract;
        return;
    }
    if (observation.initial.status == .unattempted) return error.InvalidComparisonContract;
    if (observation.physical_sends == 0 or observation.corrective_sends >= observation.physical_sends) return error.InvalidComparisonContract;
    if (observation.published and (observation.status != .completed or !observation.structural_valid)) return error.InvalidComparisonContract;
    if (observation.status == .completed or observation.status == .clarification) {
        if (!observation.scoring_disputed and observation.duties.len != example.duties.len) return error.InvalidComparisonContract;
    } else if (observation.published or observation.structural_valid) return error.InvalidComparisonContract;
    for (observation.duties, 0..) |assessment, index| {
        for (example.duties) |duty| {
            if (std.mem.eql(u8, duty.id, assessment.id)) break;
        } else return error.InvalidComparisonContract;
        for (observation.duties[0..index]) |prior| if (std.mem.eql(u8, assessment.id, prior.id)) return error.InvalidComparisonContract;
    }
}
fn validateInitial(example: Case, initial: InitialAssessment, scoring_disputed: bool) Error!void {
    if (initial.status == .completed or initial.status == .clarification) {
        if (!scoring_disputed and initial.duties.len != example.duties.len) return error.InvalidComparisonContract;
    } else if (initial.duties.len != 0 or initial.structural_valid or initial.questions_correct or material(initial.issues)) return error.InvalidComparisonContract;
    for (initial.duties, 0..) |assessment, index| {
        for (example.duties) |duty| {
            if (std.mem.eql(u8, duty.id, assessment.id)) break;
        } else return error.InvalidComparisonContract;
        for (initial.duties[0..index]) |prior| if (std.mem.eql(u8, assessment.id, prior.id)) return error.InvalidComparisonContract;
    }
}
fn initialCorrect(example: Case, observation: Observation) bool {
    const initial = observation.initial;
    if (observation.initial_scoring_disputed or initial.duties.len != example.duties.len or material(initial.issues) or !initial.structural_valid) return false;
    if ((example.expected_terminal == .completed and initial.status != .completed) or
        (example.expected_terminal == .clarification and (initial.status != .clarification or !initial.questions_correct))) return false;
    for (initial.duties) |duty| if (!duty.preserved) return false;
    return true;
}
/// Semantic instability requires an assessed material change. Provider/schema
/// failures still fail fidelity and robustness, but cannot invent semantic loss.
pub fn initialOutcome(example: Case, observation: Observation) InitialOutcome {
    if (observation.status == .unattempted) return .unattempted;
    if (observation.initial_scoring_disputed) return .unknown;
    if (initialCorrect(example, observation)) return .semantic_success;
    const initial = observation.initial;
    if (material(initial.issues) or assessmentMaterial(example, initial.status, initial.duties, initial.questions_correct, false)) return .material_failure;
    return .mechanical_failure;
}
fn semanticOutcome(outcome: InitialOutcome) bool {
    return outcome == .semantic_success or outcome == .material_failure;
}
fn accumulateIssues(target: *Issues, source: Issues) Error!void {
    inline for (std.meta.fields(Issues)) |field| {
        @field(target, field.name) = std.math.add(u32, @field(target, field.name), @field(source, field.name)) catch return error.InvalidComparisonContract;
    }
}
fn accumulateIncidence(target: *Issues, issues: Issues) Error!void {
    inline for (std.meta.fields(Issues)) |field| {
        if (@field(issues, field.name) != 0) @field(target, field.name) = std.math.add(u32, @field(target, field.name), 1) catch return error.InvalidComparisonContract;
    }
}
fn accumulateIssueRates(target: *IssueRates, incidence: Issues, denominator: u32) void {
    inline for (std.meta.fields(Issues)) |field| @field(target, field.name) += rate(@field(incidence, field.name), denominator);
}
fn divideIssueRates(target: *IssueRates, denominator: u32) void {
    if (denominator == 0) return;
    inline for (std.meta.fields(IssueRates)) |field| @field(target, field.name) /= @as(f64, @floatFromInt(denominator));
}
fn assessedFailureStage(example: Case, observation: Observation) ?FailureStage {
    if (observation.status == .unattempted) return null;
    return observation.failure_stage orelse if (!initialCorrect(example, observation) or labelledMaterial(example, observation)) .unknown else null;
}

fn rate(numerator: u32, denominator: u32) f64 {
    return if (denominator == 0) 0 else @as(f64, @floatFromInt(numerator)) / @as(f64, @floatFromInt(denominator));
}
pub fn aggregate(a: std.mem.Allocator, inventory: Inventory, protocol: Protocol, mode: Mode, trials: []const Trial, observations: []const Observation, scope: EvidenceScope) Error!Scorecard {
    try validateInventory(inventory);
    try validateProtocol(protocol);
    const canonical = try plan(a, inventory, protocol, mode);
    defer a.free(canonical);
    if (trials.len != canonical.len or observations.len != trials.len) return error.InvalidComparisonContract;
    for (trials, canonical) |trial, expected| {
        if (trial.ordinal != expected.ordinal or trial.arm != expected.arm or trial.repetition != expected.repetition or
            !std.mem.eql(u8, trial.case_id, expected.case_id) or !std.mem.eql(u8, trial.feature_id, expected.feature_id)) return error.InvalidComparisonContract;
    }
    for (observations, 0..) |observation, index| {
        for (observations[0..index]) |prior| if (prior.trial_ordinal == observation.trial_ordinal) return error.InvalidComparisonContract;
        const trial = for (trials) |trial| {
            if (trial.ordinal == observation.trial_ordinal) break trial;
        } else return error.InvalidComparisonContract;
        try validateObservation(try caseFor(inventory, trial), observation);
    }
    const scores = try a.alloc(FeatureScore, protocol.development_features * activeArms(mode).len);
    errdefer a.free(scores);
    var result: Scorecard = .{ .mode = mode, .scope = scope, .planned = @intCast(trials.len), .attempted = 0, .unattempted = 0, .physical_sends = 0, .simulated_physical_sends = 0, .actual_tokens = 0, .simulated_tokens = 0, .usage_complete = true, .elapsed_complete = true, .halt_required = false, .inconclusive = false, .issues = .{}, .omitted_duty_labels = 0, .features = scores, .arms = &.{}, .resources = &.{} };
    for (observations) |observation| {
        incrementStatus(&result.statuses, observation.status);
        if (observation.status == .unattempted) {
            result.unattempted += 1;
            continue;
        }
        result.attempted += 1;
        try accumulateIssues(&result.issues, observation.issues);
        try accumulateIncidence(&result.material_incidence, observation.issues);
        const trial = for (trials) |trial| {
            if (trial.ordinal == observation.trial_ordinal) break trial;
        } else return error.InvalidComparisonContract;
        const example = try caseFor(inventory, trial);
        if (assessedFailureStage(example, observation)) |stage| incrementStage(&result.failure_stages, stage);
        for (example.duties) |duty| if (dutyOmitted(observation.initial.duties, duty.id) or dutyOmitted(observation.duties, duty.id)) {
            result.omitted_duty_labels = std.math.add(u32, result.omitted_duty_labels, 1) catch return error.InvalidComparisonContract;
        };
        result.physical_sends = std.math.add(u64, result.physical_sends, observation.physical_sends) catch return error.InvalidComparisonContract;
        if (try observationTokens(observation)) |tokens| {
            result.actual_tokens = std.math.add(u64, result.actual_tokens, tokens) catch return error.InvalidComparisonContract;
        } else result.usage_complete = false;
        if (observation.elapsed_ns == null) result.elapsed_complete = false;
        if (observation.uncertain_delivery or observation.scoring_disputed or observation.initial_scoring_disputed) result.halt_required = true;
    }
    const invalid_evidence = result.halt_required or !result.usage_complete or !result.elapsed_complete;
    const over_budget = result.physical_sends > protocol.limits.maximum_sends or result.actual_tokens > protocol.limits.maximum_actual_tokens;
    // Equality prohibits further sends. A completely observed panel that
    // finishes exactly at its limit is still complete evidence.
    result.halt_required = result.halt_required or !result.usage_complete or result.physical_sends >= protocol.limits.maximum_sends or result.actual_tokens >= protocol.limits.maximum_actual_tokens;
    result.inconclusive = invalid_evidence or over_budget or result.unattempted != 0;
    if (scope == .synthetic) {
        result.simulated_physical_sends = result.physical_sends;
        result.simulated_tokens = result.actual_tokens;
        result.physical_sends = 0;
        result.actual_tokens = 0;
    }
    var at: usize = 0;
    for (inventory.cases) |base| if (base.partition == .development and base.variant == .base) {
        for (activeArms(mode)) |arm| {
            var score: FeatureScore = .{ .feature_id = base.feature_id, .arm = arm, .attempted = 0, .well_posed_attempted = 0, .first_pass_successes = 0, .structural_successes = 0, .useful_completions = 0, .expected_gap_attempted = 0, .correct_clarifications = 0, .robust_bundles = 0, .total_bundles = 0, .planned_bundles = protocol.repetitions, .repeat_inconsistent = false, .material_workloads = 0, .false_gap_workloads = 0, .common_original_success_pairs = 0, .common_representation_failures = 0 };
            for (1..protocol.repetitions + 1) |repetition| {
                var robust = true;
                var common_base = true;
                var common_variant_assessed = true;
                var own_base = false;
                var equivalent_outcome: InitialOutcome = .unattempted;
                var attempted_variants: u32 = 0;
                var unknown = false;
                for (trials) |trial| if (std.mem.eql(u8, trial.feature_id, base.feature_id) and trial.repetition == repetition) {
                    const example = try caseFor(inventory, trial);
                    const observation = try observationFor(observations, trial.ordinal);
                    const outcome = initialOutcome(example, observation);
                    const success = outcome == .semantic_success;
                    if (example.variant == .base) common_base = common_base and success;
                    if (example.variant == .equivalent) common_variant_assessed = common_variant_assessed and semanticOutcome(outcome);
                    if (trial.arm != arm) continue;
                    const variant = &score.variants[@intFromEnum(example.variant)];
                    variant.planned_repetitions += 1;
                    switch (outcome) {
                        .semantic_success => variant.semantic_successes += 1,
                        .material_failure => variant.material_failures += 1,
                        .mechanical_failure => variant.mechanical_failures += 1,
                        .unknown => variant.unknown += 1,
                        .unattempted => variant.unattempted += 1,
                    }
                    incrementStatus(&score.statuses, observation.status);
                    if (assessedFailureStage(example, observation)) |stage| incrementStage(&score.failure_stages, stage);
                    if (example.variant == .base) own_base = success;
                    robust = robust and success;
                    if (example.variant == .equivalent) equivalent_outcome = outcome;
                    if (observation.status == .unattempted) continue;
                    attempted_variants += 1;
                    variant.attempted_repetitions += 1;
                    unknown = unknown or outcome == .unknown;
                    try accumulateResourceTotals(&score.resources, observation, scope);
                    try accumulateIssues(&score.issues, observation.issues);
                    try accumulateIncidence(&score.material_incidence, observation.issues);
                    for (example.duties) |duty| if (dutyOmitted(observation.initial.duties, duty.id) or dutyOmitted(observation.duties, duty.id)) {
                        score.omitted_duty_labels += 1;
                    };
                    score.attempted += 1;
                    if (observation.initial.structural_valid) score.structural_successes += 1;
                    if (labelledMaterial(example, observation)) score.material_workloads += 1;
                    if (falseGap(example, observation)) score.false_gap_workloads += 1;
                    if (example.expected_terminal == .completed) {
                        score.well_posed_attempted += 1;
                        if (success) score.first_pass_successes += 1;
                        // Synthetic and replay evidence never exercises native
                        // publication, regardless of a supplied boolean claim.
                    } else {
                        score.expected_gap_attempted += 1;
                        if (success) score.correct_clarifications += 1;
                    }
                };
                if (attempted_variants == 0) score.unattempted_bundles += 1 else score.total_bundles += 1;
                if (attempted_variants > 0 and attempted_variants < 3) score.partial_bundles += 1;
                if (unknown) score.unknown_bundles += 1;
                if (robust) score.robust_bundles += 1;
                if (own_base) {
                    score.original_success_pairs += 1;
                    if (semanticOutcome(equivalent_outcome)) score.representation_eligible_pairs += 1;
                    if (equivalent_outcome == .material_failure) score.representation_failures += 1;
                }
                if (mode == .paired and common_base) {
                    score.common_original_success_pairs += 1;
                    if (common_variant_assessed) {
                        score.common_representation_eligible_pairs += 1;
                        if (equivalent_outcome == .material_failure) score.common_representation_failures += 1;
                    }
                }
            }
            score.repeat_coverage_complete = true;
            for (&score.variants) |*variant| {
                variant.repeat_inconsistent = variant.semantic_successes != 0 and variant.material_failures != 0;
                variant.semantic_coverage_complete = variant.attempted_repetitions == variant.planned_repetitions and variant.unknown == 0 and variant.mechanical_failures == 0;
                score.repeat_inconsistent = score.repeat_inconsistent or variant.repeat_inconsistent;
                score.repeat_coverage_complete = score.repeat_coverage_complete and variant.semantic_coverage_complete;
            }
            scores[at] = score;
            at += 1;
        }
    };
    const arms = try a.alloc(ArmScore, activeArms(mode).len);
    errdefer a.free(arms);
    for (activeArms(mode), arms) |arm, *summary| {
        summary.* = .{ .arm = arm, .features = protocol.development_features, .well_posed_features = 0, .first_pass_fidelity = 0, .structural_success = 0, .useful_completion = 0, .clarification_correctness = null, .robust_success = 0, .repeat_inconsistency = null, .material_harm = 0, .false_gap = 0, .common_representation_sensitivity = null, .common_original_success_features = 0, .common_original_success_pairs = 0, .brittleness_evidence_sufficient = false };
        var gaps: f64 = 0;
        var gap_features: u32 = 0;
        var sensitivity: f64 = 0;
        var sensitivity_features: u32 = 0;
        var own_sensitivity: f64 = 0;
        var own_sensitivity_features: u32 = 0;
        for (scores) |score| if (score.arm == arm) {
            if (score.attempted != 0) summary.attempted_features += 1;
            summary.first_pass_fidelity += rate(score.first_pass_successes, score.well_posed_attempted);
            if (score.well_posed_attempted != 0) summary.well_posed_features += 1;
            summary.structural_success += rate(score.structural_successes, score.attempted);
            summary.useful_completion += rate(score.useful_completions, score.well_posed_attempted);
            summary.robust_success += rate(score.robust_bundles, score.total_bundles);
            if (score.repeat_inconsistent) summary.repeat_inconsistent_features += 1;
            if (score.repeat_coverage_complete) summary.repeat_covered_features += 1;
            summary.material_harm += rate(score.material_workloads, score.attempted);
            try accumulateIssues(&summary.issues, score.issues);
            try accumulateIssues(&summary.material_incidence, score.material_incidence);
            accumulateIssueRates(&summary.material_category_rates, score.material_incidence, score.attempted);
            summary.false_gap += rate(score.false_gap_workloads, score.well_posed_attempted);
            if (score.expected_gap_attempted != 0) {
                gaps += rate(score.correct_clarifications, score.expected_gap_attempted);
                gap_features += 1;
            }
            if (score.original_success_pairs != 0) {
                summary.original_success_features += 1;
                summary.original_success_pairs += score.original_success_pairs;
            }
            if (score.representation_eligible_pairs != 0) {
                own_sensitivity += rate(score.representation_failures, score.representation_eligible_pairs);
                own_sensitivity_features += 1;
            }
            summary.representation_eligible_pairs += score.representation_eligible_pairs;
            summary.representation_failures += score.representation_failures;
            if (score.common_original_success_pairs != 0) {
                summary.common_original_success_features += 1;
                summary.common_original_success_pairs += score.common_original_success_pairs;
            }
            if (score.common_representation_eligible_pairs != 0) {
                sensitivity += rate(score.common_representation_failures, score.common_representation_eligible_pairs);
                sensitivity_features += 1;
            }
            summary.common_representation_eligible_pairs += score.common_representation_eligible_pairs;
            summary.common_representation_failures += score.common_representation_failures;
        };
        const n: f64 = @floatFromInt(@max(@as(u32, 1), summary.attempted_features));
        const well_posed: f64 = @floatFromInt(@max(@as(u32, 1), summary.well_posed_features));
        summary.first_pass_fidelity /= well_posed;
        summary.structural_success /= n;
        summary.useful_completion /= well_posed;
        summary.robust_success /= n;
        if (summary.repeat_covered_features == protocol.development_features) summary.repeat_inconsistency = rate(summary.repeat_inconsistent_features, summary.repeat_covered_features);
        summary.material_harm /= n;
        divideIssueRates(&summary.material_category_rates, summary.attempted_features);
        summary.false_gap /= well_posed;
        if (gap_features != 0) summary.clarification_correctness = gaps / @as(f64, @floatFromInt(gap_features));
        if (sensitivity_features != 0) summary.common_representation_sensitivity = sensitivity / @as(f64, @floatFromInt(sensitivity_features));
        summary.common_representation_eligible_features = sensitivity_features;
        summary.brittleness_evidence_sufficient = mode == .paired and sensitivity_features >= protocol.thresholds.minimum_common_original_success and summary.common_representation_eligible_pairs == summary.common_original_success_pairs;
        summary.representation_eligible_features = own_sensitivity_features;
        if (own_sensitivity_features != 0) summary.representation_sensitivity = own_sensitivity / @as(f64, @floatFromInt(own_sensitivity_features));
    }
    result.arms = arms;
    result.resources = try aggregateResources(a, mode, trials, observations, scope);
    errdefer a.free(result.resources);
    result.risk_strata = try aggregateRisks(a, inventory, mode, trials, observations);
    errdefer a.free(result.risk_strata);
    if (mode == .baseline) result.baseline = try summarizeBaseline(protocol, result, observations);
    return result;
}

fn hasRisk(example: Case, tag: []const u8) bool {
    for (example.risk_tags) |risk| if (std.mem.eql(u8, risk, tag)) return true;
    return false;
}
/// A case can contribute to multiple predeclared strata. Within each stratum,
/// first reduce attempts belonging to one feature, then weight features equally.
fn aggregateRisks(a: std.mem.Allocator, inventory: Inventory, mode: Mode, trials: []const Trial, observations: []const Observation) Error![]const RiskScore {
    var strata: std.ArrayList(RiskScore) = .empty;
    errdefer strata.deinit(a);
    for (inventory.cases) |example| {
        if (example.partition != .development) continue;
        for (example.risk_tags) |tag| for (activeArms(mode)) |arm| {
            const found = for (strata.items) |existing| {
                if (existing.arm == arm and std.mem.eql(u8, existing.risk_tag, tag)) break true;
            } else false;
            if (!found) try strata.append(a, .{ .risk_tag = tag, .arm = arm });
        };
    }
    for (strata.items) |*stratum| {
        var harm_rates: f64 = 0;
        var gap_rates: f64 = 0;
        for (inventory.cases) |base| {
            if (base.partition != .development or base.variant != .base) continue;
            var attempted: u32 = 0;
            var well_posed: u32 = 0;
            var harms: u32 = 0;
            var gaps: u32 = 0;
            var incidence: Issues = .{};
            for (trials) |trial| {
                if (trial.arm != stratum.arm or !std.mem.eql(u8, trial.feature_id, base.feature_id)) continue;
                const example = try caseFor(inventory, trial);
                if (!hasRisk(example, stratum.risk_tag)) continue;
                stratum.planned_workloads += 1;
                const observation = try observationFor(observations, trial.ordinal);
                if (observation.status == .unattempted) {
                    stratum.unattempted_workloads += 1;
                    continue;
                }
                attempted += 1;
                if (example.expected_terminal == .completed) well_posed += 1;
                if (labelledMaterial(example, observation)) harms += 1;
                if (falseGap(example, observation)) gaps += 1;
                if (observation.scoring_disputed or observation.initial_scoring_disputed) stratum.scoring_disputed_workloads += 1;
                try accumulateIssues(&stratum.issues, observation.issues);
                try accumulateIncidence(&incidence, observation.issues);
            }
            stratum.attempted_workloads += attempted;
            stratum.well_posed_attempted += well_posed;
            stratum.material_workloads += harms;
            stratum.false_gap_workloads += gaps;
            try accumulateIssues(&stratum.material_incidence, incidence);
            if (attempted != 0) {
                stratum.independent_features += 1;
                harm_rates += rate(harms, attempted);
                accumulateIssueRates(&stratum.material_category_rates, incidence, attempted);
            }
            if (well_posed != 0) {
                stratum.well_posed_features += 1;
                gap_rates += rate(gaps, well_posed);
            }
        }
        if (stratum.independent_features != 0) stratum.material_harm = harm_rates / @as(f64, @floatFromInt(stratum.independent_features));
        if (stratum.well_posed_features != 0) stratum.false_gap = gap_rates / @as(f64, @floatFromInt(stratum.well_posed_features));
        divideIssueRates(&stratum.material_category_rates, stratum.independent_features);
    }
    return strata.toOwnedSlice(a);
}

fn observationTokens(observation: Observation) Error!?u64 {
    const usage = observation.usage orelse return null;
    return std.math.add(u64, usage.input_tokens, usage.output_tokens) catch return error.InvalidComparisonContract;
}
fn accumulateResourceTotals(totals: *ResourceTotals, observation: Observation, scope: EvidenceScope) Error!void {
    const sends = if (scope == .synthetic) &totals.simulated_physical_sends else &totals.physical_sends;
    sends.* = std.math.add(u64, sends.*, observation.physical_sends) catch return error.InvalidComparisonContract;
    totals.corrective_sends = std.math.add(u64, totals.corrective_sends, observation.corrective_sends) catch return error.InvalidComparisonContract;
    if (try observationTokens(observation)) |tokens| {
        const target = if (scope == .synthetic) &totals.simulated_tokens else &totals.actual_tokens;
        target.* = std.math.add(u64, target.*, tokens) catch return error.InvalidComparisonContract;
    } else totals.usage_complete = false;
    if (totals.total_elapsed_ns) |elapsed| {
        totals.total_elapsed_ns = if (observation.elapsed_ns) |duration| std.math.add(u64, elapsed, duration) catch return error.InvalidComparisonContract else null;
    }
}

fn incrementStatus(counts: *StatusCounts, status: Status) void {
    switch (status) {
        inline else => |tag| @field(counts, @tagName(tag)) += 1,
    }
}
fn incrementStage(counts: *FailureStages, stage: FailureStage) void {
    switch (stage) {
        inline else => |tag| @field(counts, @tagName(tag)) += 1,
    }
}
fn sampleStddev(count: u32, sum: f64, sum_squares: f64) ?f64 {
    if (count < 2) return null;
    const n: f64 = @floatFromInt(count);
    return @sqrt(@max(@as(f64, 0), (sum_squares - sum * sum / n) / (n - 1)));
}
fn estimateQualification(protocol: Protocol, result: Scorecard, stddev: ?f64, observations: []const Observation) Error!QualificationEstimate {
    var estimate: QualificationEstimate = .{ .status = .insufficient, .reason = .incomplete_evidence, .baseline_feature_stddev = stddev, .required_features = null, .paired_workloads = null, .sends_at_observed_worst = null, .tokens_at_observed_worst = null, .observed_cost_budget = .unavailable };
    if (result.inconclusive) return estimate;
    const deviation = stddev orelse {
        estimate.reason = .too_few_features;
        return estimate;
    };
    const demand = @max(@as(f64, @floatFromInt(protocol.qualification.minimum_features)), @ceil(std.math.pow(f64, 1.96 * deviation / protocol.qualification.precision, 2)));
    estimate.status = .infeasible;
    estimate.reason = .feature_bound;
    if (demand > @as(f64, @floatFromInt(std.math.maxInt(u32)))) return estimate;
    const required: u32 = @intFromFloat(demand);
    estimate.required_features = required;
    const workloads = std.math.mul(u64, std.math.mul(u64, required, 6) catch return error.InvalidComparisonContract, protocol.repetitions) catch return error.InvalidComparisonContract;
    estimate.paired_workloads = workloads;
    var worst_sends: u64 = 0;
    var worst_tokens: u64 = 0;
    for (observations) |observation| {
        worst_sends = @max(worst_sends, observation.physical_sends);
        if (try observationTokens(observation)) |tokens| worst_tokens = @max(worst_tokens, tokens);
    }
    estimate.sends_at_observed_worst = std.math.mul(u64, workloads, worst_sends) catch return error.InvalidComparisonContract;
    estimate.tokens_at_observed_worst = std.math.mul(u64, workloads, worst_tokens) catch return error.InvalidComparisonContract;
    const spent_sends = if (result.scope == .synthetic) result.simulated_physical_sends else result.physical_sends;
    const spent_tokens = if (result.scope == .synthetic) result.simulated_tokens else result.actual_tokens;
    const planning_sends = std.math.add(u64, spent_sends, estimate.sends_at_observed_worst.?) catch return error.InvalidComparisonContract;
    const planning_tokens = std.math.add(u64, spent_tokens, estimate.tokens_at_observed_worst.?) catch return error.InvalidComparisonContract;
    estimate.observed_cost_budget = if (planning_sends > protocol.limits.maximum_sends or planning_tokens > protocol.limits.maximum_actual_tokens) .exceeds else .fits;
    if (required > protocol.qualification.maximum_features) return estimate;
    if ((std.math.add(u64, spent_sends, workloads) catch return error.InvalidComparisonContract) > protocol.limits.maximum_sends) {
        estimate.reason = .minimum_send_budget;
        return estimate;
    }
    estimate.status = .sized;
    estimate.reason = null;
    return estimate;
}
fn summarizeBaseline(protocol: Protocol, result: Scorecard, observations: []const Observation) Error!BaselineSummary {
    var fidelity_count: u32 = 0;
    var fidelity_sum: f64 = 0;
    var fidelity_squares: f64 = 0;
    var robust_count: u32 = 0;
    var robust_sum: f64 = 0;
    var robust_squares: f64 = 0;
    for (result.features) |feature| {
        if (feature.well_posed_attempted != 0) {
            const value = rate(feature.first_pass_successes, feature.well_posed_attempted);
            fidelity_count += 1;
            fidelity_sum += value;
            fidelity_squares += value * value;
        }
        if (feature.total_bundles != 0) {
            const value = rate(feature.robust_bundles, feature.total_bundles);
            robust_count += 1;
            robust_sum += value;
            robust_squares += value * value;
        }
    }
    const fidelity_stddev = sampleStddev(fidelity_count, fidelity_sum, fidelity_squares);
    const robust_stddev = sampleStddev(robust_count, robust_sum, robust_squares);
    const arm = result.arms[0];
    const sufficient = !result.inconclusive and fidelity_stddev != null and robust_stddev != null;
    const adequate = arm.first_pass_fidelity >= protocol.thresholds.minimum_fidelity and
        arm.robust_success >= protocol.thresholds.minimum_robust_success and
        arm.material_harm <= protocol.thresholds.maximum_material_harm and
        arm.false_gap <= protocol.thresholds.maximum_false_gap and
        (arm.clarification_correctness == null or arm.clarification_correctness.? == 1);
    return .{
        .adequacy = if (!sufficient) .insufficient else if (adequate) .adequate else .below_target,
        .meaningful_initial_headroom = if (!sufficient) null else (1 - arm.first_pass_fidelity >= protocol.thresholds.minimum_effect or 1 - arm.robust_success >= protocol.thresholds.minimum_effect),
        .fidelity_features = fidelity_count,
        .robustness_features = robust_count,
        .fidelity_sample_stddev = fidelity_stddev,
        .robustness_sample_stddev = robust_stddev,
        .qualification = try estimateQualification(protocol, result, fidelity_stddev, observations),
        .qualification_metric = protocol.qualification.metric,
        .qualification_robustness = try estimateQualification(protocol, result, robust_stddev, observations),
    };
}

fn median(sorted: []const u64) ?f64 {
    if (sorted.len == 0) return null;
    const middle = sorted.len / 2;
    return if (sorted.len % 2 == 1) @floatFromInt(sorted[middle]) else (@as(f64, @floatFromInt(sorted[middle - 1])) + @as(f64, @floatFromInt(sorted[middle]))) / 2;
}
fn lessResource(_: void, left: u64, right: u64) bool {
    return left < right;
}
fn aggregateResources(a: std.mem.Allocator, mode: Mode, trials: []const Trial, observations: []const Observation, scope: EvidenceScope) Error![]ArmResources {
    const resources = try a.alloc(ArmResources, activeArms(mode).len);
    errdefer a.free(resources);
    const tokens = try a.alloc(u64, trials.len);
    defer a.free(tokens);
    const elapsed = try a.alloc(u64, trials.len);
    defer a.free(elapsed);
    for (activeArms(mode), resources) |arm, *resource| {
        resource.* = .{ .arm = arm, .attempted_workloads = 0, .physical_sends = 0, .simulated_physical_sends = 0, .actual_tokens = 0, .simulated_tokens = 0, .usage_complete = true, .elapsed_complete = true, .median_workload_tokens = null, .worst_workload_tokens = null, .median_workload_elapsed_ns = null, .worst_workload_elapsed_ns = null };
        var token_count: usize = 0;
        var elapsed_count: usize = 0;
        for (trials) |trial| if (trial.arm == arm) {
            const observation = try observationFor(observations, trial.ordinal);
            if (observation.status == .unattempted) continue;
            resource.attempted_workloads += 1;
            resource.physical_sends = std.math.add(u64, resource.physical_sends, observation.physical_sends) catch return error.InvalidComparisonContract;
            if (try observationTokens(observation)) |consumed| {
                tokens[token_count] = consumed;
                token_count += 1;
                resource.actual_tokens = std.math.add(u64, resource.actual_tokens, consumed) catch return error.InvalidComparisonContract;
            } else resource.usage_complete = false;
            if (observation.elapsed_ns) |duration| {
                elapsed[elapsed_count] = duration;
                elapsed_count += 1;
            } else resource.elapsed_complete = false;
        };
        std.mem.sort(u64, tokens[0..token_count], {}, lessResource);
        std.mem.sort(u64, elapsed[0..elapsed_count], {}, lessResource);
        if (resource.usage_complete and token_count != 0) {
            resource.median_workload_tokens = median(tokens[0..token_count]);
            resource.worst_workload_tokens = tokens[token_count - 1];
        }
        if (resource.elapsed_complete and elapsed_count != 0) {
            resource.median_workload_elapsed_ns = median(elapsed[0..elapsed_count]);
            resource.worst_workload_elapsed_ns = elapsed[elapsed_count - 1];
        }
        if (scope == .synthetic) {
            resource.simulated_physical_sends = resource.physical_sends;
            resource.simulated_tokens = resource.actual_tokens;
            resource.physical_sends = 0;
            resource.actual_tokens = 0;
        }
    }
    return resources;
}

fn exampleCase() Case {
    return .{ .id = "example-base", .feature_id = "example", .partition = .development, .variant = .base, .domain = "loans", .size = .small, .risk_tags = &.{"condition"}, .sources = &.{.{ .id = "source", .path = "reference/loan.md", .text = "Return loans within 30 days unless extended." }}, .duties = &.{.{ .id = "return", .description = "Retain loan deadline and extension exception.", .source_refs = &.{.{ .source_id = "source", .quote = "Return loans within 30 days unless extended." }}, .exact_values = &.{"30 days"} }}, .expected_terminal = .completed, .expected_questions = &.{}, .permissible_alternatives = &.{"The deadline can be expressed as thirty days."}, .forbidden_additions = &.{"Charge a late fee."} };
}
fn exampleProtocol() Protocol {
    return .{ .schema = 1, .cohort = .small, .provider = "aws-bedrock", .api = .converse, .model = "openai.gpt-oss-20b-1:0", .generation_slot = "spec_generation", .region = "ap-southeast-2", .reasoning_effort = .low, .response_mode = .native_schema, .temperature = Temperature.fixed.wireValue(), .max_output_tokens = 16384, .repetitions = 3, .arms = &.{ .A, .C }, .development_features = 8, .qualification = .{ .metric = .first_pass_fidelity, .minimum_features = 8, .maximum_features = 16, .confidence = 0.95, .precision = 0.15 }, .analysis = .{ .method = .paired_feature_bootstrap, .resamples = 10000, .seed = 20261015, .minimum_effect_lower_bound = 0, .primary_brittleness = .representation_sensitivity }, .thresholds = .{ .minimum_fidelity = 0.85, .minimum_robust_success = 0.75, .minimum_useful_completion = 0.80, .maximum_material_harm = 0.05, .maximum_false_gap = 0.05, .minimum_effect = 0.10, .minimum_brittleness_reduction = 0.10, .minimum_common_original_success = 6, .maximum_token_ratio = 1.25, .maximum_latency_ratio = 1.5 }, .limits = .{ .maximum_sends = 1000, .maximum_actual_tokens = 2000000 }, .live_authorized = false };
}
fn miniatureInventory(a: std.mem.Allocator) Error!Inventory {
    const cases = try a.alloc(Case, 6);
    for (0..2) |feature| {
        const feature_id = try std.fmt.allocPrint(a, "feature-{d}", .{feature});
        inline for (std.meta.tags(Variant), 0..) |variant, index| {
            var example = exampleCase();
            example.feature_id = feature_id;
            example.id = try std.fmt.allocPrint(a, "{s}-{s}", .{ feature_id, @tagName(variant) });
            example.variant = variant;
            example.partition = if (feature == 0) .development else .qualification;
            cases[feature * 3 + index] = example;
        }
    }
    return .{ .schema = 1, .cases = cases };
}
fn miniatureProtocol() Protocol {
    var protocol = exampleProtocol();
    protocol.development_features = 1;
    protocol.qualification.minimum_features = 1;
    protocol.qualification.maximum_features = 1;
    protocol.thresholds.minimum_common_original_success = 1;
    return protocol;
}
fn faithfulObservation(trial: Trial) Observation {
    return .{ .trial_ordinal = trial.ordinal, .initial = .{ .status = .completed, .duties = &.{.{ .id = "return", .preserved = true }}, .questions_correct = false, .structural_valid = true, .issues = .{} }, .status = .completed, .duties = &.{.{ .id = "return", .preserved = true }}, .questions_correct = false, .structural_valid = true, .published = true, .corrective_sends = 0, .physical_sends = 1, .issues = .{}, .usage = .{ .input_tokens = 10, .output_tokens = 5 }, .elapsed_ns = 100, .uncertain_delivery = false, .scoring_disputed = false };
}
test "persisted observations explicitly retain unknown failure origin in the closed shape" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const observation = faithfulObservation(.{ .ordinal = 1, .case_id = "example", .feature_id = "feature", .arm = .A, .repetition = 1 });
    const bytes = try std.json.Stringify.valueAlloc(a, observation, .{});
    try std.testing.expect((try decode(Observation, a, bytes)).failure_stage == null);
    const missing = try std.mem.replaceOwned(u8, a, bytes, ",\"failure_stage\":null", "");
    try std.testing.expect(!std.mem.eql(u8, bytes, missing));
    try std.testing.expectError(error.InvalidComparisonContract, decode(Observation, a, missing));
    const missing_initial = try std.mem.replaceOwned(u8, a, bytes, ",\"initial_scoring_disputed\":false", "");
    try std.testing.expect(!std.mem.eql(u8, bytes, missing_initial));
    try std.testing.expectError(error.InvalidComparisonContract, decode(Observation, a, missing_initial));
}
test "comparison contracts reject malformed closed data and unfrozen controls" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const protocol = exampleProtocol();
    const bytes = try std.json.Stringify.valueAlloc(a, protocol, .{});
    _ = try parseProtocol(a, bytes);
    const unknown = try std.mem.replaceOwned(u8, a, bytes, "\"schema\":1", "\"schema\":1,\"extra\":true");
    try std.testing.expectError(error.InvalidComparisonContract, parseProtocol(a, unknown));
    var bad = protocol;
    bad.live_authorized = true;
    try std.testing.expectError(error.InvalidComparisonContract, validateProtocol(bad));
    bad = protocol;
    bad.repetitions = 2;
    try std.testing.expectError(error.InvalidComparisonContract, validateProtocol(bad));
    bad = protocol;
    bad.thresholds.minimum_effect = 0;
    try std.testing.expectError(error.InvalidComparisonContract, validateProtocol(bad));
    bad = protocol;
    bad.temperature = 0;
    try std.testing.expectError(error.InvalidComparisonContract, validateProtocol(bad));
    bad = protocol;
    bad.max_output_tokens = 16385;
    try std.testing.expectError(error.InvalidComparisonContract, validateProtocol(bad));
    bad = protocol;
    bad.generation_slot = "";
    try std.testing.expectError(error.InvalidComparisonContract, validateProtocol(bad));
    bad.generation_slot = "\xff";
    try std.testing.expectError(error.InvalidComparisonContract, validateProtocol(bad));
    const missing_slot = try std.mem.replaceOwned(u8, a, bytes, "\"generation_slot\":\"spec_generation\",", "");
    try std.testing.expect(!std.mem.eql(u8, bytes, missing_slot));
    try std.testing.expectError(error.InvalidComparisonContract, parseProtocol(a, missing_slot));
    bad = protocol;
    bad.limits.maximum_sends = 143;
    try std.testing.expectError(error.InvalidComparisonContract, validateProtocol(bad));
    try std.testing.expectEqual(@as(u32, 8), try sizeQualification(protocol, 0.1));
    try std.testing.expectError(error.InvalidComparisonContract, sizeQualification(protocol, 0.5));
}
test "comparison protocol freezes the selected GPT-OSS binding and rejects superseded controls" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const protocol = exampleProtocol();
    const bytes = try std.json.Stringify.valueAlloc(a, protocol, .{});
    const accepted = try parseProtocol(a, bytes);
    try std.testing.expectEqual(.low, accepted.reasoning_effort);
    try std.testing.expectEqual(Temperature.fixed.wireValue(), accepted.temperature);
    const Mutation = struct { old: []const u8, replacement: []const u8 };
    for ([_]Mutation{
        .{ .old = "\"provider\":\"aws-bedrock\"", .replacement = "\"provider\":\"openai\"" },
        .{ .old = "openai.gpt-oss-20b-1:0", .replacement = "global.openai.gpt-6-luna" },
        .{ .old = "openai.gpt-oss-20b-1:0", .replacement = "gpt-oss-20b" },
        .{ .old = "openai.gpt-oss-20b-1:0", .replacement = "openai.gpt-oss-120b-1:0" },
        .{ .old = "ap-southeast-2", .replacement = "us-west-2" },
        .{ .old = "\"api\":\"converse\"", .replacement = "\"api\":\"openai_responses\"" },
        .{ .old = "\"reasoning_effort\":\"low\"", .replacement = "\"reasoning_effort\":null" },
        .{ .old = "\"reasoning_effort\":\"low\"", .replacement = "\"reasoning_effort\":\"medium\"" },
        .{ .old = "\"response_mode\":\"native_schema\"", .replacement = "\"response_mode\":\"prompt_only\"" },
        .{ .old = "\"temperature\":0.1", .replacement = "\"temperature\":null" },
        .{ .old = "\"temperature\":0.1", .replacement = "\"temperature\":0.2" },
        .{ .old = "\"max_output_tokens\":16384", .replacement = "\"max_output_tokens\":8192" },
        .{ .old = "\"schema\":1", .replacement = "\"schema\":1,\"native_json_strict\":true" },
        .{ .old = "\"schema\":1", .replacement = "\"schema\":1,\"reasoning_mode\":\"provider_default\"" },
        .{ .old = "\"schema\":1", .replacement = "\"schema\":1,\"documented_default_effort\":\"medium\"" },
    }) |mutation| {
        const rejected = try std.mem.replaceOwned(u8, a, bytes, mutation.old, mutation.replacement);
        try std.testing.expect(!std.mem.eql(u8, bytes, rejected));
        try std.testing.expectError(error.InvalidComparisonContract, parseProtocol(a, rejected));
    }
}
test "source projection excludes evaluation labels and rejects unsupported labels" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var example = exampleCase();
    const bytes = try sourceInput(a, example);
    try std.testing.expect(std.mem.indexOf(u8, bytes, example.duties[0].description) == null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, example.forbidden_additions[0]) == null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "expected_terminal") == null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, example.sources[0].text) != null);
    example.duties = &.{.{ .id = "foreign", .description = "Invented label.", .source_refs = &.{.{ .source_id = "source", .quote = "Charge a fee." }}, .exact_values = &.{} }};
    try std.testing.expectError(error.InvalidComparisonContract, validateCase(example));
}
test "inventory validates complete feature variants and excludes partition leaks" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try miniatureInventory(a);
    try validateInventory(inventory);
    const protocol = miniatureProtocol();
    const trials = try plan(a, inventory, protocol, .paired);
    try std.testing.expectEqual(@as(usize, 18), trials.len);
    try std.testing.expectEqual(Arm.A, trials[0].arm);
    try std.testing.expectEqual(Arm.C, trials[2].arm);
    const cases = try a.dupe(Case, inventory.cases);
    cases[1].partition = .qualification;
    try std.testing.expectError(error.InvalidComparisonContract, validateInventory(.{ .schema = 1, .cases = cases }));
    cases[1] = cases[0];
    try std.testing.expectError(error.InvalidComparisonContract, validateInventory(.{ .schema = 1, .cases = cases }));
    try std.testing.expectError(error.InvalidComparisonContract, validateInventory(.{ .schema = 2, .cases = inventory.cases }));
    try std.testing.expectError(error.InvalidComparisonContract, plan(a, inventory, exampleProtocol(), .paired));
}
test "labelled accounting retains failed attempts and denies synthetic publication authority" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try miniatureInventory(a);
    const protocol = miniatureProtocol();
    const trials = try plan(a, inventory, protocol, .paired);
    const observations = try a.alloc(Observation, trials.len);
    for (trials, observations) |trial, *observation| observation.* = faithfulObservation(trial);
    const faithful = try aggregate(a, inventory, protocol, .paired, trials, observations, .synthetic);
    try std.testing.expectEqual(@as(u64, 0), faithful.physical_sends);
    try std.testing.expectEqual(@as(u64, 18), faithful.simulated_physical_sends);
    try std.testing.expectEqual(@as(u64, 0), faithful.actual_tokens);
    try std.testing.expectEqual(@as(u64, 270), faithful.simulated_tokens);
    try std.testing.expectEqual(@as(f64, 1), faithful.arms[0].first_pass_fidelity);
    try std.testing.expectEqual(@as(f64, 0), faithful.arms[0].useful_completion);
    try std.testing.expect(!faithful.workflow_authority and !faithful.semantic_benefit_demonstrated);
    observations[0].status = .truncated;
    observations[0].initial = .{ .status = .truncated, .duties = &.{}, .questions_correct = false, .structural_valid = false, .issues = .{} };
    observations[0].duties = &.{};
    observations[0].structural_valid = false;
    observations[0].published = false;
    const failed = try aggregate(a, inventory, protocol, .paired, trials, observations, .synthetic);
    try std.testing.expectEqual(@as(u32, 18), failed.attempted);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0 / 9.0), failed.arms[0].first_pass_fidelity, 0.0001);
    try std.testing.expect(failed.arms[0].repeat_inconsistency == null);
    try std.testing.expect(!failed.features[0].repeat_inconsistent);
    try std.testing.expectEqual(@as(u32, 1), failed.features[0].variants[@intFromEnum(Variant.base)].mechanical_failures);
    observations[0].usage = null;
    const unknown = try aggregate(a, inventory, protocol, .paired, trials, observations, .synthetic);
    try std.testing.expect(unknown.halt_required and unknown.inconclusive and !unknown.usage_complete);
    try std.testing.expect(!unknown.resources[0].usage_complete);
    try std.testing.expect(unknown.resources[0].median_workload_tokens == null and unknown.resources[0].worst_workload_tokens == null);
    observations[0] = faithfulObservation(trials[0]);
    observations[0].scoring_disputed = true;
    const dispute = try aggregate(a, inventory, protocol, .paired, trials, observations, .synthetic);
    try std.testing.expect(dispute.halt_required and dispute.inconclusive);
    observations[0].trial_ordinal = observations[1].trial_ordinal;
    try std.testing.expectError(error.InvalidComparisonContract, aggregate(a, inventory, protocol, .paired, trials, observations, .synthetic));
}
test "paired uncertainty is seeded feature-level accounting" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const interval = try pairedInterval(a, exampleProtocol(), &.{ 0.1, 0.1, 0.1 });
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), interval.mean, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), interval.lower, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), interval.upper, 0.000001);
    const mixed = try pairedInterval(a, exampleProtocol(), &.{ -0.5, 0, 0.5 });
    const repeated = try pairedInterval(a, exampleProtocol(), &.{ -0.5, 0, 0.5 });
    try std.testing.expectEqualDeep(mixed, repeated);
    try std.testing.expect(mixed.lower < 0 and mixed.upper > 0);
    try std.testing.expectError(error.InvalidComparisonContract, pairedInterval(a, exampleProtocol(), &.{0.1}));
}
test "explicit omission and false clarification labels count harm despite structural success" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try miniatureInventory(a);
    const protocol = miniatureProtocol();
    const trials = try plan(a, inventory, protocol, .paired);
    const observations = try a.alloc(Observation, trials.len);
    for (trials, observations) |trial, *observation| observation.* = faithfulObservation(trial);
    const equivalent = for (trials, 0..) |trial, index| {
        if (trial.arm == .A and trial.repetition == 1 and (try caseFor(inventory, trial)).variant == .equivalent) break index;
    } else unreachable;
    observations[equivalent].duties = &.{.{ .id = "return", .preserved = false }};
    observations[equivalent].initial.duties = observations[equivalent].duties;
    const omitted = try aggregate(a, inventory, protocol, .paired, trials, observations, .synthetic);
    try std.testing.expectEqual(@as(f64, 1), omitted.arms[0].structural_success);
    try std.testing.expectEqual(@as(u32, 1), omitted.omitted_duty_labels);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 9.0), omitted.arms[0].material_harm, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 3.0), omitted.arms[0].common_representation_sensitivity.?, 0.0001);
    try std.testing.expectEqual(@as(?f64, 1), omitted.arms[0].repeat_inconsistency);
    observations[equivalent] = faithfulObservation(trials[equivalent]);
    observations[equivalent].status = .clarification;
    observations[equivalent].initial.status = .clarification;
    observations[equivalent].published = false;
    const false_gap = try aggregate(a, inventory, protocol, .paired, trials, observations, .synthetic);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 9.0), false_gap.arms[0].false_gap, 0.0001);
    observations[equivalent] = faithfulObservation(trials[equivalent]);
    observations[equivalent].issues.harmful_repairs = 1;
    observations[equivalent].corrective_sends = 1;
    observations[equivalent].physical_sends = 2;
    const harmful = try aggregate(a, inventory, protocol, .paired, trials, observations, .synthetic);
    try std.testing.expectEqual(@as(u32, 1), harmful.issues.harmful_repairs);
    try std.testing.expectEqual(@as(f64, 1), harmful.arms[0].first_pass_fidelity);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 9.0), harmful.arms[0].material_harm, 0.0001);
}

test "correction preserves original omission invention and false-gap harm" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try miniatureInventory(a);
    const protocol = miniatureProtocol();
    const trials = try plan(a, inventory, protocol, .paired);
    const observations = try a.alloc(Observation, trials.len);
    for (trials, observations) |trial, *observation| observation.* = faithfulObservation(trial);
    observations[0].corrective_sends = 1;
    observations[0].physical_sends = 2;
    observations[0].initial.duties = &.{.{ .id = "return", .preserved = false }};
    const omitted_initial = try aggregate(a, inventory, protocol, .paired, trials, observations, .synthetic);
    try std.testing.expectEqual(@as(u32, 1), omitted_initial.omitted_duty_labels);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0 / 9.0), omitted_initial.arms[0].first_pass_fidelity, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 9.0), omitted_initial.arms[0].material_harm, 0.0001);

    observations[0].initial.duties = observations[0].duties;
    observations[0].initial.issues.unsupported_behavior = 1;
    try std.testing.expectError(error.InvalidComparisonContract, aggregate(a, inventory, protocol, .paired, trials, observations, .synthetic));
    observations[0].issues.unsupported_behavior = 1;
    const invented_initial = try aggregate(a, inventory, protocol, .paired, trials, observations, .synthetic);
    try std.testing.expectEqual(@as(u32, 1), invented_initial.issues.unsupported_behavior);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 9.0), invented_initial.arms[0].material_harm, 0.0001);

    observations[0].initial.issues = .{};
    observations[0].issues = .{};
    observations[0].initial.status = .clarification;
    const gap_initial = try aggregate(a, inventory, protocol, .paired, trials, observations, .synthetic);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 9.0), gap_initial.arms[0].false_gap, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 9.0), gap_initial.arms[0].material_harm, 0.0001);
    try std.testing.expectEqual(@as(f64, 0), gap_initial.arms[0].useful_completion);
}

test "experiment equality stops further sends while overshoot is inconclusive" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try miniatureInventory(a);
    var protocol = miniatureProtocol();
    const trials = try plan(a, inventory, protocol, .paired);
    protocol.limits = .{ .maximum_sends = 18, .maximum_actual_tokens = 270 };
    const observations = try a.alloc(Observation, trials.len);
    for (trials, observations) |trial, *observation| observation.* = faithfulObservation(trial);
    const equality = try aggregate(a, inventory, protocol, .paired, trials, observations, .diagnostic);
    try std.testing.expect(equality.halt_required and !equality.inconclusive);
    observations[0].physical_sends = 2;
    observations[0].corrective_sends = 1;
    const overshoot = try aggregate(a, inventory, protocol, .paired, trials, observations, .diagnostic);
    try std.testing.expect(overshoot.halt_required and overshoot.inconclusive);
}

test "resource summaries sort unequal workload costs and isolate missing latency by arm" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try miniatureInventory(a);
    const protocol = miniatureProtocol();
    const trials = try plan(a, inventory, protocol, .paired);
    const observations = try a.alloc(Observation, trials.len);
    const costs = [_]u64{ 9, 1, 7, 2, 8, 3, 6, 4, 5 };
    var counts = [_]usize{ 0, 0 };
    for (trials, observations) |trial, *observation| {
        observation.* = faithfulObservation(trial);
        const index = @intFromEnum(trial.arm);
        const cost = costs[counts[index]] * @as(u64, if (trial.arm == .A) 10 else 1);
        counts[index] += 1;
        observation.usage = .{ .input_tokens = cost, .output_tokens = 0 };
        observation.elapsed_ns = cost * 10;
    }
    const complete = try aggregate(a, inventory, protocol, .paired, trials, observations, .diagnostic);
    try std.testing.expectEqual(@as(u64, 450), complete.resources[0].actual_tokens);
    try std.testing.expectEqual(@as(?f64, 50), complete.resources[0].median_workload_tokens);
    try std.testing.expectEqual(@as(?u64, 90), complete.resources[0].worst_workload_tokens);
    try std.testing.expectEqual(@as(?f64, 500), complete.resources[0].median_workload_elapsed_ns);
    try std.testing.expectEqual(@as(?u64, 900), complete.resources[0].worst_workload_elapsed_ns);
    try std.testing.expectEqual(@as(u64, 45), complete.resources[1].actual_tokens);
    try std.testing.expectEqual(@as(?f64, 5), complete.resources[1].median_workload_tokens);
    try std.testing.expectEqual(@as(?u64, 9), complete.resources[1].worst_workload_tokens);
    observations[0].elapsed_ns = null;
    const partial = try aggregate(a, inventory, protocol, .paired, trials, observations, .diagnostic);
    try std.testing.expect(partial.inconclusive and !partial.resources[0].elapsed_complete);
    try std.testing.expect(partial.resources[0].median_workload_elapsed_ns == null and partial.resources[0].worst_workload_elapsed_ns == null);
    try std.testing.expectEqual(@as(?f64, 50), partial.resources[1].median_workload_elapsed_ns);
    try std.testing.expectEqual(@as(?u64, 90), partial.resources[1].worst_workload_elapsed_ns);
    try std.testing.expectEqual(@as(?f64, 50), partial.resources[0].median_workload_tokens);
}

fn twoFeatureInventory(a: std.mem.Allocator) Error!Inventory {
    const cases = try a.alloc(Case, 9);
    for (0..3) |feature| {
        const feature_id = try std.fmt.allocPrint(a, "feature-{d}", .{feature});
        inline for (std.meta.tags(Variant), 0..) |variant, index| {
            var example = exampleCase();
            example.feature_id = feature_id;
            example.id = try std.fmt.allocPrint(a, "{s}-{s}", .{ feature_id, @tagName(variant) });
            example.variant = variant;
            example.partition = if (feature < 2) .development else .qualification;
            cases[feature * 3 + index] = example;
        }
    }
    return .{ .schema = 1, .cases = cases };
}
fn unattemptedObservation(trial: Trial) Observation {
    return .{ .trial_ordinal = trial.ordinal, .initial = .{ .status = .unattempted, .duties = &.{}, .questions_correct = false, .structural_valid = false, .issues = .{} }, .status = .unattempted, .duties = &.{}, .questions_correct = false, .structural_valid = false, .published = false, .corrective_sends = 0, .physical_sends = 0, .issues = .{}, .usage = null, .elapsed_ns = null, .uncertain_delivery = false, .scoring_disputed = false };
}
fn variabilityInventory(a: std.mem.Allocator) Error!Inventory {
    const inventory = try twoFeatureInventory(a);
    const cases = try a.dupe(Case, inventory.cases);
    for (cases) |*example| {
        if (std.mem.eql(u8, example.feature_id, "feature-1")) {
            example.domain = "delivery";
            example.risk_tags = &.{ "shared-risk", "recipient" };
            example.sources = &.{.{ .id = "source", .path = "delivery.md", .text = "Notify the named recipient after parcel delivery; retain the receipt for 7 days." }};
            example.duties = &.{.{ .id = "return", .description = "Preserve the recipient, delivery condition and receipt retention.", .source_refs = &.{.{ .source_id = "source", .quote = "Notify the named recipient after parcel delivery; retain the receipt for 7 days." }}, .exact_values = &.{"7 days"} }};
        } else example.risk_tags = &.{ "shared-risk", "deadline" };
    }
    return .{ .schema = 1, .cases = cases };
}
test "all variant repeats detect material instability with feature weighted category and risk reports" {
    for (std.meta.tags(Mode)) |mode| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const inventory = try variabilityInventory(a);
        var protocol = miniatureProtocol();
        protocol.development_features = 2;
        const trials = try plan(a, inventory, protocol, mode);
        const observations = try a.alloc(Observation, trials.len);
        for (trials, observations) |trial, *observation| {
            observation.* = faithfulObservation(trial);
            if (trial.arm != .A) continue;
            const example = try caseFor(inventory, trial);
            const feature_zero = std.mem.eql(u8, trial.feature_id, "feature-0");
            if ((feature_zero and example.variant == .equivalent and trial.repetition == 1) or
                (!feature_zero and example.variant == .changed and trial.repetition == 2))
            {
                observation.initial.duties = &.{.{ .id = "return", .preserved = false }};
                observation.duties = observation.initial.duties;
                if (feature_zero) observation.issues.lost_restrictions = 3 else observation.issues.wrong_support = 2;
                observation.initial.issues = observation.issues;
            }
        }
        const report = try aggregate(a, inventory, protocol, mode, trials, observations, .synthetic);
        defer report.deinit(a);
        const arm = report.arms[0];
        try std.testing.expectEqual(@as(?f64, 1), arm.repeat_inconsistency);
        try std.testing.expectEqual(@as(u32, 2), arm.repeat_inconsistent_features);
        try std.testing.expectEqual(@as(u32, 2), arm.repeat_covered_features);
        try std.testing.expectEqual(@as(u32, 3), arm.issues.lost_restrictions);
        try std.testing.expectEqual(@as(u32, 2), arm.issues.wrong_support);
        try std.testing.expectEqual(@as(u32, 1), arm.material_incidence.lost_restrictions);
        try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 18.0), arm.material_category_rates.lost_restrictions, 0.000001);
        for (report.features) |feature| {
            if (feature.arm != .A) continue;
            try std.testing.expect(feature.repeat_inconsistent and feature.repeat_coverage_complete);
            try std.testing.expectEqual(@as(u32, 3), feature.total_bundles);
            try std.testing.expectEqual(@as(u32, 2), feature.robust_bundles);
            const variant: Variant = if (std.mem.eql(u8, feature.feature_id, "feature-0")) .equivalent else .changed;
            try std.testing.expectEqual(@as(u32, 1), feature.variants[@intFromEnum(variant)].material_failures);
            try std.testing.expect(feature.variants[@intFromEnum(variant)].repeat_inconsistent);
            try std.testing.expectEqual(@as(u32, 1), feature.omitted_duty_labels);
        }
        try std.testing.expectEqual(@as(u32, 1), arm.representation_failures);
        try std.testing.expectEqual(@as(u32, 6), arm.representation_eligible_pairs);
        try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 6.0), arm.representation_sensitivity.?, 0.000001);
        const shared = for (report.risk_strata) |stratum| {
            if (stratum.arm == .A and std.mem.eql(u8, stratum.risk_tag, "shared-risk")) break stratum;
        } else return error.InvalidComparisonContract;
        try std.testing.expectEqual(@as(u32, 2), shared.independent_features);
        try std.testing.expectEqual(@as(u32, 18), shared.attempted_workloads);
        try std.testing.expectEqual(@as(u32, 3), shared.issues.lost_restrictions);
        try std.testing.expectEqual(@as(u32, 1), shared.material_incidence.lost_restrictions);
        try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 18.0), shared.material_category_rates.lost_restrictions, 0.000001);
        if (mode == .paired) {
            try std.testing.expectEqual(@as(?f64, 0), report.arms[1].repeat_inconsistency);
            try std.testing.expectEqual(@as(u32, 0), report.arms[1].representation_failures);
            try std.testing.expectEqual(@as(u32, 6), arm.common_representation_eligible_pairs);
        }
    }
}
test "unattempted mechanical and unknown variants cannot invent material instability or bundle attempts" {
    for (std.meta.tags(Mode)) |mode| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const inventory = try variabilityInventory(a);
        var protocol = miniatureProtocol();
        protocol.development_features = 2;
        const trials = try plan(a, inventory, protocol, mode);
        const observations = try a.alloc(Observation, trials.len);
        for (trials, observations) |trial, *observation| {
            observation.* = faithfulObservation(trial);
            if (trial.arm != .A) continue;
            const example = try caseFor(inventory, trial);
            if (std.mem.eql(u8, trial.feature_id, "feature-0")) {
                if (trial.repetition == 2 or (trial.repetition == 1 and example.variant == .equivalent)) observation.* = unattemptedObservation(trial);
            } else if (trial.repetition == 1 and example.variant == .equivalent) {
                observation.initial = .{ .status = .provider_failed, .duties = &.{}, .questions_correct = false, .structural_valid = false, .issues = .{} };
                observation.status = .provider_failed;
                observation.duties = &.{};
                observation.structural_valid = false;
                observation.published = false;
            } else if (trial.repetition == 1 and example.variant == .changed) {
                observation.initial.duties = &.{};
                observation.duties = &.{};
                observation.initial_scoring_disputed = true;
                observation.scoring_disputed = true;
            }
        }
        const report = try aggregate(a, inventory, protocol, mode, trials, observations, .synthetic);
        defer report.deinit(a);
        try std.testing.expect(report.inconclusive and report.arms[0].repeat_inconsistency == null);
        for (report.features) |feature| if (feature.arm == .A) {
            try std.testing.expect(!feature.repeat_inconsistent and !feature.repeat_coverage_complete);
            try std.testing.expectEqual(@as(u32, 0), feature.representation_failures);
            try std.testing.expectEqual(@as(u32, 0), feature.material_workloads);
            if (std.mem.eql(u8, feature.feature_id, "feature-0")) {
                try std.testing.expectEqual(@as(u32, 3), feature.planned_bundles);
                try std.testing.expectEqual(@as(u32, 2), feature.total_bundles);
                try std.testing.expectEqual(@as(u32, 1), feature.unattempted_bundles);
                try std.testing.expectEqual(@as(u32, 1), feature.partial_bundles);
                try std.testing.expectEqual(@as(u32, 2), feature.original_success_pairs);
                try std.testing.expectEqual(@as(u32, 1), feature.representation_eligible_pairs);
            } else {
                try std.testing.expectEqual(@as(u32, 1), feature.variants[@intFromEnum(Variant.equivalent)].mechanical_failures);
                try std.testing.expectEqual(@as(u32, 1), feature.variants[@intFromEnum(Variant.changed)].unknown);
                try std.testing.expectEqual(@as(u32, 1), feature.unknown_bundles);
            }
        };
        try std.testing.expectEqual(@as(u32, 0), report.omitted_duty_labels);
        try std.testing.expect(!report.arms[0].brittleness_evidence_sufficient);
    }
}
test "missing final judgments do not erase independently known original semantics" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try miniatureInventory(a);
    const protocol = miniatureProtocol();
    const trials = try plan(a, inventory, protocol, .baseline);
    const observations = try a.alloc(Observation, trials.len);
    for (trials, observations) |trial, *observation| observation.* = faithfulObservation(trial);
    observations[0].duties = &.{};
    observations[0].scoring_disputed = true;
    const report = try aggregate(a, inventory, protocol, .baseline, trials, observations, .synthetic);
    defer report.deinit(a);
    try std.testing.expect(report.inconclusive);
    try std.testing.expectEqual(@as(u32, 9), report.features[0].first_pass_successes);
    try std.testing.expectEqual(@as(u32, 3), report.features[0].robust_bundles);
    try std.testing.expectEqual(InitialOutcome.semantic_success, initialOutcome(inventory.cases[0], observations[0]));
}
test "baseline planning observes only A and denies paired or holdout substitutions" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try miniatureInventory(a);
    const protocol = miniatureProtocol();
    const trials = try plan(a, inventory, protocol, .baseline);
    try std.testing.expectEqual(@as(usize, 9), trials.len);
    for (trials, 0..) |trial, at| {
        try std.testing.expectEqual(Arm.A, trial.arm);
        try std.testing.expectEqual(@as(u32, @intCast(at + 1)), trial.ordinal);
        try std.testing.expectEqual(Partition.development, (try caseFor(inventory, trial)).partition);
    }
    const observations = try a.alloc(Observation, trials.len);
    for (trials, observations) |trial, *observation| observation.* = faithfulObservation(trial);
    const report = try aggregate(a, inventory, protocol, .baseline, trials, observations, .diagnostic);
    defer report.deinit(a);
    try std.testing.expectEqual(Mode.baseline, report.mode);
    try std.testing.expectEqual(@as(usize, 1), report.arms.len);
    try std.testing.expectEqual(@as(usize, 1), report.features.len);
    try std.testing.expectEqual(@as(usize, 1), report.resources.len);
    try std.testing.expectEqual(@as(u32, 0), report.arms[0].common_original_success_pairs);
    try std.testing.expect(report.arms[0].common_representation_sensitivity == null);
    try std.testing.expect(!report.arms[0].brittleness_evidence_sufficient);
    try std.testing.expectEqual(@as(?f64, 0), report.arms[0].representation_sensitivity);
    try std.testing.expectEqual(@as(u32, 3), report.arms[0].original_success_pairs);
    try std.testing.expectEqual(.insufficient, report.baseline.?.qualification.status);
    try std.testing.expect(!report.semantic_benefit_demonstrated and !report.workflow_authority);
    const paired = try plan(a, inventory, protocol, .paired);
    try std.testing.expectError(error.InvalidComparisonContract, aggregate(a, inventory, protocol, .baseline, paired, observations, .diagnostic));
    const foreign = try a.dupe(Trial, trials);
    foreign[0].arm = .C;
    try std.testing.expectError(error.InvalidComparisonContract, aggregate(a, inventory, protocol, .baseline, foreign, observations, .diagnostic));
    foreign[0] = trials[0];
    foreign[0].case_id = inventory.cases[3].id;
    foreign[0].feature_id = inventory.cases[3].feature_id;
    try std.testing.expectError(error.InvalidComparisonContract, aggregate(a, inventory, protocol, .baseline, foreign, observations, .diagnostic));
    try std.testing.expectError(error.InvalidComparisonContract, decode(Mode, a, "\"both_with_faked_C\""));
}
test "baseline reports independent feature variability adequacy and separate frozen size estimates" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try twoFeatureInventory(a);
    var protocol = miniatureProtocol();
    protocol.development_features = 2;
    const trials = try plan(a, inventory, protocol, .baseline);
    const observations = try a.alloc(Observation, trials.len);
    for (trials, observations) |trial, *observation| observation.* = faithfulObservation(trial);
    const faithful = try aggregate(a, inventory, protocol, .baseline, trials, observations, .diagnostic);
    defer faithful.deinit(a);
    const summary = faithful.baseline.?;
    try std.testing.expectEqual(.adequate, summary.adequacy);
    try std.testing.expectEqual(@as(?bool, false), summary.meaningful_initial_headroom);
    try std.testing.expectEqual(@as(?f64, 0), summary.fidelity_sample_stddev);
    try std.testing.expectEqual(@as(?f64, 0), summary.robustness_sample_stddev);
    try std.testing.expectEqual(.sized, summary.qualification.status);
    try std.testing.expectEqual(@as(?u32, 1), summary.qualification.required_features);
    try std.testing.expectEqual(@as(?u64, 18), summary.qualification_robustness.paired_workloads);
    try std.testing.expectEqual(.first_pass_fidelity, summary.qualification_metric);
    try std.testing.expectEqual(@as(u32, 18), faithful.statuses.completed);
    try std.testing.expectEqual(@as(u64, 9), faithful.features[0].resources.physical_sends);
    try std.testing.expectEqual(@as(u64, 135), faithful.features[0].resources.actual_tokens);
    try std.testing.expectEqual(@as(?u64, 900), faithful.features[0].resources.total_elapsed_ns);
    try std.testing.expectEqual(@as(f64, 0), faithful.arms[0].useful_completion);
    for (trials, observations) |trial, *observation| if (std.mem.eql(u8, trial.feature_id, "feature-1")) {
        observation.initial.duties = &.{.{ .id = "return", .preserved = false }};
        observation.duties = observation.initial.duties;
        observation.failure_stage = .extraction_grouping;
    };
    const variable = try aggregate(a, inventory, protocol, .baseline, trials, observations, .diagnostic);
    defer variable.deinit(a);
    try std.testing.expectEqual(.below_target, variable.baseline.?.adequacy);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 0.5)), variable.baseline.?.fidelity_sample_stddev.?, 0.000001);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 0.5)), variable.baseline.?.robustness_sample_stddev.?, 0.000001);
    try std.testing.expectEqual(.infeasible, variable.baseline.?.qualification_robustness.status);
    try std.testing.expectEqual(.feature_bound, variable.baseline.?.qualification_robustness.reason.?);
    try std.testing.expectEqual(@as(?u32, 86), variable.baseline.?.qualification_robustness.required_features);
    try std.testing.expectEqual(@as(u32, 9), variable.failure_stages.extraction_grouping);
    try std.testing.expectEqual(@as(u32, 9), variable.features[1].failure_stages.extraction_grouping);
    try std.testing.expectEqual(@as(u32, 9), variable.omitted_duty_labels);
    try std.testing.expect(!variable.semantic_benefit_demonstrated);
}
test "baseline incomplete unknown and disputed observations never size qualification" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try twoFeatureInventory(a);
    var protocol = miniatureProtocol();
    protocol.development_features = 2;
    const trials = try plan(a, inventory, protocol, .baseline);
    const observations = try a.alloc(Observation, trials.len);
    for (trials, observations) |trial, *observation| observation.* = faithfulObservation(trial);
    observations[0] = unattemptedObservation(trials[0]);
    const partial = try aggregate(a, inventory, protocol, .baseline, trials, observations, .diagnostic);
    defer partial.deinit(a);
    try std.testing.expectEqual(@as(u32, 1), partial.statuses.unattempted);
    try std.testing.expectEqual(@as(u32, 1), partial.features[0].statuses.unattempted);
    try std.testing.expectEqual(.insufficient, partial.baseline.?.adequacy);
    try std.testing.expectEqual(.insufficient, partial.baseline.?.qualification.status);
    try std.testing.expect(partial.baseline.?.qualification.required_features == null);
    observations[0].failure_stage = .generation;
    try std.testing.expectError(error.InvalidComparisonContract, aggregate(a, inventory, protocol, .baseline, trials, observations, .diagnostic));
    observations[0] = faithfulObservation(trials[0]);
    observations[0].usage = null;
    const unknown = try aggregate(a, inventory, protocol, .baseline, trials, observations, .diagnostic);
    defer unknown.deinit(a);
    try std.testing.expect(unknown.halt_required and unknown.inconclusive);
    try std.testing.expect(!unknown.features[0].resources.usage_complete);
    try std.testing.expectEqual(.insufficient, unknown.baseline.?.qualification_robustness.status);
    observations[0] = faithfulObservation(trials[0]);
    observations[0].scoring_disputed = true;
    const disputed = try aggregate(a, inventory, protocol, .baseline, trials, observations, .diagnostic);
    defer disputed.deinit(a);
    try std.testing.expectEqual(.insufficient, disputed.baseline.?.qualification_robustness.status);
}
test "qualification uses the selected first pass fidelity variance independently of later harm" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try twoFeatureInventory(a);
    var protocol = miniatureProtocol();
    protocol.development_features = 2;
    const trials = try plan(a, inventory, protocol, .baseline);
    const observations = try a.alloc(Observation, trials.len);
    for (trials, observations) |trial, *observation| {
        observation.* = faithfulObservation(trial);
        if (std.mem.eql(u8, trial.feature_id, "feature-1")) {
            // All original candidates are faithful. Later harmful review is
            // retained in adequacy without changing either original metric.
            observation.issues.harmful_diagnoses = 1;
            observation.failure_stage = .review;
        }
    }
    const report = try aggregate(a, inventory, protocol, .baseline, trials, observations, .diagnostic);
    defer report.deinit(a);
    const summary = report.baseline.?;
    try std.testing.expectEqual(.first_pass_fidelity, summary.qualification_metric);
    try std.testing.expectEqual(@as(?f64, 0), summary.fidelity_sample_stddev);
    try std.testing.expectEqual(@as(?f64, 0), summary.robustness_sample_stddev);
    try std.testing.expectEqual(.sized, summary.qualification.status);
    try std.testing.expectEqual(@as(?u32, 1), summary.qualification.required_features);
    try std.testing.expectEqual(.sized, summary.qualification_robustness.status);
    try std.testing.expectEqual(@as(?u32, 1), summary.qualification_robustness.required_features);
    try std.testing.expectEqual(.below_target, summary.adequacy);
}
test "qualification selects fidelity variance when equal fidelity has different robust bundles" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try twoFeatureInventory(a);
    var protocol = miniatureProtocol();
    protocol.development_features = 2;
    const trials = try plan(a, inventory, protocol, .baseline);
    const observations = try a.alloc(Observation, trials.len);
    for (trials, observations) |trial, *observation| {
        observation.* = faithfulObservation(trial);
        const example = try caseFor(inventory, trial);
        // Each feature loses three of nine originals: one representation in
        // every repeat versus every representation in one repeat. Fidelity is
        // equal, while complete representation-bundle success differs.
        const loses = if (std.mem.eql(u8, trial.feature_id, "feature-1")) trial.repetition == 1 else example.variant == .equivalent;
        if (loses) {
            observation.initial.duties = &.{.{ .id = "return", .preserved = false }};
            observation.duties = observation.initial.duties;
            observation.failure_stage = .generation;
        }
    }
    const report = try aggregate(a, inventory, protocol, .baseline, trials, observations, .diagnostic);
    defer report.deinit(a);
    const summary = report.baseline.?;
    try std.testing.expectEqual(@as(u32, 6), report.features[0].first_pass_successes);
    try std.testing.expectEqual(@as(u32, 6), report.features[1].first_pass_successes);
    try std.testing.expectEqual(@as(u32, 0), report.features[0].robust_bundles);
    try std.testing.expectEqual(@as(u32, 2), report.features[1].robust_bundles);
    try std.testing.expectEqual(@as(?f64, 0), summary.fidelity_sample_stddev);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 2.0 / 9.0)), summary.robustness_sample_stddev.?, 0.000001);
    try std.testing.expectEqual(.first_pass_fidelity, summary.qualification_metric);
    try std.testing.expectEqual(.sized, summary.qualification.status);
    try std.testing.expectEqual(@as(?u32, 1), summary.qualification.required_features);
    try std.testing.expectEqual(.infeasible, summary.qualification_robustness.status);
    try std.testing.expectEqual(@as(?u32, 38), summary.qualification_robustness.required_features);
}
test "baseline budget forecasts retain complete workload correction cost with the frozen fidelity size" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try twoFeatureInventory(a);
    var protocol = miniatureProtocol();
    protocol.development_features = 2;
    protocol.limits.maximum_actual_tokens = 1000;
    const trials = try plan(a, inventory, protocol, .baseline);
    const observations = try a.alloc(Observation, trials.len);
    for (trials, observations) |trial, *observation| observation.* = faithfulObservation(trial);
    observations[0].physical_sends = 3;
    observations[0].corrective_sends = 2;
    observations[0].usage = .{ .input_tokens = 200, .output_tokens = 100 };
    const report = try aggregate(a, inventory, protocol, .baseline, trials, observations, .diagnostic);
    defer report.deinit(a);
    const estimate = report.baseline.?.qualification;
    try std.testing.expectEqual(.sized, estimate.status);
    try std.testing.expectEqual(@as(?u64, 54), estimate.sends_at_observed_worst);
    try std.testing.expectEqual(@as(?u64, 5400), estimate.tokens_at_observed_worst);
    try std.testing.expectEqual(.exceeds, estimate.observed_cost_budget);
    try std.testing.expectEqual(@as(u64, 11), report.features[0].resources.physical_sends);
    try std.testing.expectEqual(@as(u64, 2), report.features[0].resources.corrective_sends);
    try std.testing.expectEqual(.first_pass_fidelity, report.baseline.?.qualification_metric);
}

test "missing semantic labels remain disputed evidence rather than fabricated omission or success" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try twoFeatureInventory(a);
    var protocol = miniatureProtocol();
    protocol.development_features = 2;
    const trials = try plan(a, inventory, protocol, .baseline);
    const observations = try a.alloc(Observation, trials.len);
    for (trials, observations) |trial, *observation| observation.* = faithfulObservation(trial);
    observations[0].initial.duties = &.{};
    observations[0].duties = &.{};
    try std.testing.expectError(error.InvalidComparisonContract, aggregate(a, inventory, protocol, .baseline, trials, observations, .diagnostic));
    observations[0].scoring_disputed = true;
    observations[0].initial_scoring_disputed = true;
    const unknown = try aggregate(a, inventory, protocol, .baseline, trials, observations, .diagnostic);
    defer unknown.deinit(a);
    try std.testing.expect(unknown.inconclusive and unknown.halt_required);
    try std.testing.expectEqual(@as(u32, 0), unknown.omitted_duty_labels);
    try std.testing.expectEqual(@as(u32, 0), unknown.features[0].material_workloads);
    try std.testing.expectEqual(@as(u32, 8), unknown.features[0].first_pass_successes);
    try std.testing.expect(!unknown.features[0].repeat_inconsistent);
    try std.testing.expectEqual(.insufficient, unknown.baseline.?.qualification.status);
    observations[0].initial.duties = &.{.{ .id = "foreign", .preserved = true }};
    try std.testing.expectError(error.InvalidComparisonContract, aggregate(a, inventory, protocol, .baseline, trials, observations, .diagnostic));
    observations[0].initial.duties = &.{};
    observations[0].duties = &.{ .{ .id = "return", .preserved = true }, .{ .id = "return", .preserved = true } };
    try std.testing.expectError(error.InvalidComparisonContract, aggregate(a, inventory, protocol, .baseline, trials, observations, .diagnostic));
}
