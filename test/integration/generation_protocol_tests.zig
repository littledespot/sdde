//! Fixed offline Phase 0 scenario. No provider, credentials, model calls,
//! production candidates or publication capability.
const std = @import("std");
const comparison = @import("../harness/generation_comparison.zig");
const Temperature = @import("../../src/domain/model_controls.zig").Temperature;
const root = "test/calibration/semantic-simplicity";
const output = ".zig-cache/semantic-simplicity/phase0";

const Specimen = struct {
    id: []const u8,
    case_id: []const u8,
    candidate_text: []const u8,
    initial_candidate_text: []const u8,
    observation: comparison.Observation,
    expected: struct { first_pass: bool, material_harm: bool, false_gap: bool, harmful_repair: bool },
};
const Specimens = struct { schema: u32, specimens: []const Specimen };
const SourceInput = struct {
    case_id: []const u8,
    scope: enum { complete_source_backed_record_collection },
    sources: []const comparison.Source,
};

fn caseFor(inventory: comparison.Inventory, id: []const u8) !comparison.Case {
    for (inventory.cases) |example| if (std.mem.eql(u8, example.id, id)) return example;
    return error.InvalidFixtureCase;
}
fn faithful(a: std.mem.Allocator, inventory: comparison.Inventory, trials: []const comparison.Trial) ![]comparison.Observation {
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
            .published = status == .completed,
            .corrective_sends = 0,
            // Deliberately unequal sends: per-call scoring must not alter
            // complete feature weighting when the assignment count changes.
            .physical_sends = if (trial.arm == .A) 2 else 1,
            .issues = .{},
            .usage = .{ .input_tokens = 1000, .output_tokens = 200 },
            .elapsed_ns = 1_000_000_000,
            .uncertain_delivery = false,
            .scoring_disputed = false,
        };
    }
    return observations;
}
fn write(a: std.mem.Allocator, path: []const u8, value: anytype) !void {
    const bytes = try std.json.Stringify.valueAlloc(a, value, .{ .whitespace = .indent_2 });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = bytes });
}
fn hash(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

test "test.integration.generation_protocol Phase 0 prepares sources and accounts complete labelled workloads" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try comparison.parseInventory(a, @embedFile("../calibration/semantic-simplicity/cases.json"));
    const protocol = try comparison.parseProtocol(a, @embedFile("../calibration/semantic-simplicity/protocol.json"));
    try std.testing.expectEqual(.small, protocol.cohort);
    try std.testing.expect(!protocol.live_authorized);
    try std.testing.expectEqualStrings("aws-bedrock", protocol.provider);
    try std.testing.expectEqualStrings("openai.gpt-oss-20b-1:0", protocol.model);
    try std.testing.expectEqualStrings("ap-southeast-2", protocol.region);
    try std.testing.expectEqual(.low, protocol.reasoning_effort);
    try std.testing.expectEqual(.native_schema, protocol.response_mode);
    try std.testing.expectEqual(Temperature.fixed.wireValue(), protocol.temperature);
    try std.testing.expectEqual(@as(u32, 16384), protocol.max_output_tokens);
    try std.testing.expectEqual(@as(usize, 72), inventory.cases.len);
    var development: u32 = 0;
    var qualification: u32 = 0;
    var labelled_duties: u32 = 0;
    var completed_base: u32 = 0;
    var gap_base: u32 = 0;
    var small_features: u32 = 0;
    var medium_features: u32 = 0;
    for (inventory.cases) |example| {
        labelled_duties += @intCast(example.duties.len);
        if (example.variant != .base) continue;
        if (example.size == .small) small_features += 1 else medium_features += 1;
        if (example.partition == .development) {
            development += 1;
            if (example.expected_terminal == .completed) completed_base += 1 else gap_base += 1;
        } else qualification += 1;
    }
    try std.testing.expectEqual(@as(u32, 8), development);
    try std.testing.expectEqual(@as(u32, 16), qualification);
    try std.testing.expectEqual(@as(u32, 6), completed_base);
    try std.testing.expectEqual(@as(u32, 2), gap_base);
    try std.testing.expect(small_features > 0 and medium_features > 0);

    const trials = try comparison.plan(a, inventory, protocol, .paired);
    try std.testing.expectEqual(@as(usize, 144), trials.len);
    try std.Io.Dir.cwd().createDirPath(std.testing.io, output ++ "/source-inputs");
    var prepared: u32 = 0;
    for (inventory.cases) |example| if (example.partition == .development) {
        const bytes = try comparison.sourceInput(a, example);
        const source_input = try comparison.decode(SourceInput, a, bytes);
        try std.testing.expectEqualStrings(example.id, source_input.case_id);
        try std.testing.expectEqualDeep(example.sources, source_input.sources);
        // Decode through a closed source-only shape; hidden labels cannot
        // appear as an extra field, regardless of words shared with sources.
        const leaked = try std.mem.replaceOwned(u8, a, bytes, "\"case_id\":", "\"expected_terminal\":\"completed\",\"case_id\":");
        try std.testing.expectError(error.InvalidComparisonContract, comparison.decode(SourceInput, a, leaked));
        const path = try std.fmt.allocPrint(a, output ++ "/source-inputs/{s}.json", .{example.id});
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = bytes });
        prepared += 1;
    };
    try std.testing.expectEqual(@as(u32, 24), prepared);
    try write(a, output ++ "/development-plan.json", trials);

    const observations = try faithful(a, inventory, trials);
    const score = try comparison.aggregate(a, inventory, protocol, .paired, trials, observations, .synthetic);
    defer score.deinit(a);
    try std.testing.expectEqual(@as(u32, 144), score.attempted);
    try std.testing.expectEqual(@as(u64, 0), score.physical_sends);
    try std.testing.expectEqual(@as(u64, 216), score.simulated_physical_sends);
    try std.testing.expectEqual(@as(u64, 0), score.actual_tokens);
    try std.testing.expectEqual(@as(u64, 172800), score.simulated_tokens);
    for (score.arms) |arm| {
        try std.testing.expectEqual(@as(f64, 1), arm.first_pass_fidelity);
        try std.testing.expectEqual(@as(f64, 1), arm.robust_success);
        try std.testing.expectEqual(@as(f64, 0), arm.useful_completion);
        try std.testing.expectEqual(@as(?f64, 0), arm.repeat_inconsistency);
        try std.testing.expect(arm.brittleness_evidence_sufficient);
    }
    try std.testing.expect(!score.semantic_benefit_demonstrated and !score.workflow_authority);
    for (score.resources) |resources| {
        try std.testing.expectEqual(@as(u32, 72), resources.attempted_workloads);
        try std.testing.expectEqual(@as(u64, 0), resources.physical_sends);
        try std.testing.expectEqual(@as(u64, 0), resources.actual_tokens);
        try std.testing.expectEqual(@as(u64, if (resources.arm == .A) 144 else 72), resources.simulated_physical_sends);
        try std.testing.expectEqual(@as(?f64, 1200), resources.median_workload_tokens);
        try std.testing.expectEqual(@as(?u64, 1200), resources.worst_workload_tokens);
        try std.testing.expectEqual(@as(?f64, 1_000_000_000), resources.median_workload_elapsed_ns);
        try std.testing.expect(resources.tokens_per_useful_completion == null);
    }

    const specimens = try comparison.decode(Specimens, a, @embedFile("../calibration/semantic-simplicity/specimens.json"));
    try std.testing.expectEqual(@as(u32, 1), specimens.schema);
    try std.testing.expectEqual(@as(usize, 6), specimens.specimens.len);
    for (specimens.specimens, 0..) |specimen, at| {
        try std.testing.expect(specimen.candidate_text.len != 0 and specimen.initial_candidate_text.len != 0);
        for (specimens.specimens[0..at]) |prior| try std.testing.expect(!std.mem.eql(u8, prior.id, specimen.id));
        const changed = try a.dupe(comparison.Observation, observations);
        const index = for (trials, 0..) |trial, index| {
            if (std.mem.eql(u8, trial.case_id, specimen.case_id) and trial.arm == .A and trial.repetition == 1) break index;
        } else return error.ForeignSpecimenCase;
        changed[index] = specimen.observation;
        changed[index].trial_ordinal = trials[index].ordinal;
        const evaluated = try comparison.aggregate(a, inventory, protocol, .paired, trials, changed, .synthetic);
        defer evaluated.deinit(a);
        const feature = for (evaluated.features) |feature| {
            if (feature.arm == .A and std.mem.eql(u8, feature.feature_id, trials[index].feature_id)) break feature;
        } else return error.MissingFixtureFeature;
        try std.testing.expectEqual(@as(u32, if (specimen.expected.first_pass) 9 else 8), feature.first_pass_successes);
        try std.testing.expectEqual(@as(u32, if (specimen.expected.material_harm) 1 else 0), feature.material_workloads);
        try std.testing.expectEqual(@as(u32, if (specimen.expected.false_gap) 1 else 0), feature.false_gap_workloads);
        try std.testing.expectEqual(@as(u32, if (specimen.expected.harmful_repair) 1 else 0), evaluated.issues.harmful_repairs);
        for (evaluated.arms) |arm| try std.testing.expectEqual(@as(f64, 0), arm.useful_completion);
        try std.testing.expect(!evaluated.workflow_authority and !evaluated.semantic_benefit_demonstrated);
    }

    const partial = try a.dupe(comparison.Observation, observations);
    partial[0] = .{
        .trial_ordinal = trials[0].ordinal,
        .initial = .{ .status = .unattempted, .duties = &.{}, .questions_correct = false, .structural_valid = false, .issues = .{} },
        .status = .unattempted,
        .duties = &.{},
        .questions_correct = false,
        .structural_valid = false,
        .published = false,
        .corrective_sends = 0,
        .physical_sends = 0,
        .issues = .{},
        .usage = null,
        .elapsed_ns = null,
        .uncertain_delivery = false,
        .scoring_disputed = false,
    };
    const incomplete = try comparison.aggregate(a, inventory, protocol, .paired, trials, partial, .synthetic);
    defer incomplete.deinit(a);
    try std.testing.expectEqual(@as(u32, 143), incomplete.attempted);
    try std.testing.expectEqual(@as(u32, 1), incomplete.unattempted);
    try std.testing.expect(incomplete.inconclusive);
    const unknown = try a.dupe(comparison.Observation, observations);
    unknown[0].usage = null;
    const halted = try comparison.aggregate(a, inventory, protocol, .paired, trials, unknown, .synthetic);
    defer halted.deinit(a);
    try std.testing.expect(halted.halt_required and halted.inconclusive);
    const missing = observations[0 .. observations.len - 1];
    try std.testing.expectError(error.InvalidComparisonContract, comparison.aggregate(a, inventory, protocol, .paired, trials, missing, .synthetic));

    const interval = try comparison.pairedInterval(a, protocol, &.{ 0.1, 0.2, 0.1, 0.2, 0.1, 0.2, 0.1, 0.2 });
    try std.testing.expect(interval.lower > 0 and interval.mean >= protocol.thresholds.minimum_effect);
    try std.testing.expectEqual(@as(u32, 8), try comparison.sizeQualification(protocol, 0));
    try std.testing.expectEqual(@as(u32, 16), try comparison.sizeQualification(protocol, 0.3));
    try std.testing.expectError(error.InvalidComparisonContract, comparison.sizeQualification(protocol, 0.5));
    const protocol_hash = hash(@embedFile("../calibration/semantic-simplicity/protocol.json"));
    const cases_hash = hash(@embedFile("../calibration/semantic-simplicity/cases.json"));
    const specimens_hash = hash(@embedFile("../calibration/semantic-simplicity/specimens.json"));
    try write(a, output ++ "/dry-run.json", .{
        .schema = "semantic-simplicity-phase0-report/v1",
        .result = "passed_offline",
        .scope = "synthetic",
        .model = protocol.model,
        .fixture_sha256 = .{
            .protocol = protocol_hash[0..],
            .cases = cases_hash[0..],
            .specimens = specimens_hash[0..],
        },
        .label_review = "model_assisted",
        .features = development + qualification,
        .development_features = development,
        .qualification_features = qualification,
        .case_variants = inventory.cases.len,
        .labelled_duties = labelled_duties,
        .prepared_source_inputs = prepared,
        .qualification_source_inputs_exported = @as(u32, 0),
        .scorecard_specimens = specimens.specimens.len,
        .scorecard = score,
        .uncertainty_fixture = interval,
        .native_workflow_origin_available = false,
        .semantic_quality = "not_measured",
        .phase1_provider_exchange = "not_run",
    });
}

test "test.integration.generation_protocol Phase 2 baseline accounts all 72 A workloads without qualification or C observations" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inventory = try comparison.parseInventory(a, @embedFile("../calibration/semantic-simplicity/cases.json"));
    const protocol = try comparison.parseProtocol(a, @embedFile("../calibration/semantic-simplicity/protocol.json"));
    try std.testing.expectEqual(.first_pass_fidelity, protocol.qualification.metric);
    const trials = try comparison.plan(a, inventory, protocol, .baseline);
    try std.testing.expectEqual(@as(usize, 72), trials.len);
    for (trials) |trial| {
        try std.testing.expectEqual(comparison.Arm.A, trial.arm);
        const example = try caseFor(inventory, trial.case_id);
        try std.testing.expectEqual(comparison.Partition.development, example.partition);
    }
    const observations = try faithful(a, inventory, trials);
    const score = try comparison.aggregate(a, inventory, protocol, .baseline, trials, observations, .synthetic);
    defer score.deinit(a);
    try std.testing.expectEqual(@as(usize, 8), score.features.len);
    try std.testing.expectEqual(@as(usize, 1), score.arms.len);
    try std.testing.expectEqual(@as(usize, 1), score.resources.len);
    try std.testing.expectEqual(@as(u32, 72), score.attempted);
    try std.testing.expectEqual(@as(u32, 0), score.unattempted);
    try std.testing.expectEqual(@as(u32, 60), score.statuses.completed);
    try std.testing.expectEqual(@as(u32, 12), score.statuses.clarification);
    try std.testing.expectEqual(@as(u64, 144), score.simulated_physical_sends);
    for (score.features) |feature| {
        try std.testing.expectEqual(@as(u64, 18), feature.resources.simulated_physical_sends);
        try std.testing.expectEqual(@as(u64, 10800), feature.resources.simulated_tokens);
        try std.testing.expectEqual(@as(u64, 0), feature.resources.actual_tokens);
    }
    try std.testing.expectEqual(@as(u64, 86400), score.simulated_tokens);
    try std.testing.expectEqual(@as(u64, 0), score.actual_tokens);
    try std.testing.expectEqual(@as(u64, 0), score.physical_sends);
    try std.testing.expectEqual(@as(f64, 0), score.arms[0].useful_completion);
    try std.testing.expectEqual(@as(?f64, 0), score.arms[0].representation_sensitivity);
    try std.testing.expect(score.arms[0].common_representation_sensitivity == null);
    try std.testing.expect(!score.arms[0].brittleness_evidence_sufficient);
    const baseline = score.baseline.?;
    try std.testing.expectEqual(@as(u32, 8), baseline.fidelity_features);
    try std.testing.expectEqual(@as(u32, 8), baseline.robustness_features);
    try std.testing.expectEqual(@as(?f64, 0), baseline.fidelity_sample_stddev);
    try std.testing.expectEqual(@as(?f64, 0), baseline.robustness_sample_stddev);
    try std.testing.expectEqual(.first_pass_fidelity, baseline.qualification_metric);
    try std.testing.expectEqual(.sized, baseline.qualification.status);
    try std.testing.expectEqual(@as(?u32, 8), baseline.qualification.required_features);
    try std.testing.expectEqual(@as(?u64, 144), baseline.qualification.paired_workloads);
    try std.testing.expectEqual(@as(?u64, 288), baseline.qualification.sends_at_observed_worst);
    try std.testing.expectEqual(@as(?u64, 172800), baseline.qualification.tokens_at_observed_worst);
    try std.testing.expectEqual(.fits, baseline.qualification.observed_cost_budget);
    try std.testing.expect(!score.workflow_authority and !score.semantic_benefit_demonstrated);

    const specimens = try comparison.decode(Specimens, a, @embedFile("../calibration/semantic-simplicity/specimens.json"));
    for (specimens.specimens) |specimen| {
        const changed = try a.dupe(comparison.Observation, observations);
        const index = for (trials, 0..) |trial, index| {
            if (std.mem.eql(u8, trial.case_id, specimen.case_id) and trial.repetition == 1) break index;
        } else return error.ForeignSpecimenCase;
        changed[index] = specimen.observation;
        changed[index].trial_ordinal = trials[index].ordinal;
        changed[index].failure_stage = if (specimen.expected.harmful_repair) .repair else if (specimen.expected.material_harm) .generation else null;
        const assessed = try comparison.aggregate(a, inventory, protocol, .baseline, trials, changed, .synthetic);
        defer assessed.deinit(a);
        const feature = for (assessed.features) |feature| {
            if (std.mem.eql(u8, feature.feature_id, trials[index].feature_id)) break feature;
        } else return error.MissingFixtureFeature;
        try std.testing.expectEqual(@as(u32, if (specimen.expected.first_pass) 9 else 8), feature.first_pass_successes);
        try std.testing.expectEqual(@as(u32, if (specimen.expected.material_harm) 1 else 0), feature.material_workloads);
        try std.testing.expectEqual(@as(u32, if (specimen.expected.false_gap) 1 else 0), feature.false_gap_workloads);
        try std.testing.expectEqual(@as(u32, if (specimen.expected.harmful_repair) 1 else 0), assessed.failure_stages.repair);
        try std.testing.expect(assessed.baseline != null);
    }

    // The selected variance is a closed, required freeze rather than a report
    // heuristic, including when both metrics happen to have the same variance.
    const protocol_bytes = @embedFile("../calibration/semantic-simplicity/protocol.json");
    const wrong_metric = try std.mem.replaceOwned(u8, a, protocol_bytes, "first_pass_fidelity", "robust_success");
    try std.testing.expectError(error.InvalidComparisonContract, comparison.parseProtocol(a, wrong_metric));
    const missing_metric = try std.mem.replaceOwned(u8, a, protocol_bytes, "    \"metric\": \"first_pass_fidelity\",\n", "");
    try std.testing.expectError(error.InvalidComparisonContract, comparison.parseProtocol(a, missing_metric));
}
