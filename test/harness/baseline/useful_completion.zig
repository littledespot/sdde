//! Offline assessment of exact native publications. The canonical rubric
//! validator checks supplied judgments; no assessment authorizes engine work.
const std = @import("std");
const c = @import("../contracts.zig");
const judgment = @import("../judgment.zig");
const acceptance = @import("../acceptance.zig");
const final_metrics = @import("final_fidelity.zig");

pub const Provenance = struct { kind: enum { human, model_assisted }, assessor: []const u8 };
pub const Supplied = struct {
    output_id: []const u8,
    output_sha256: []const u8,
    rubric_sha256: []const u8,
    provenance: Provenance,
    proposal: judgment.Proposal,
    scoring_disputed: bool = false,
};
pub const Target = struct {
    output_id: []const u8,
    output_sha256: []const u8,
    rubric_sha256: []const u8,
    capture: c.Capture,
};
pub const Evaluation = struct {
    state: enum { not_required, missing, disputed, unresolved, threshold_unconfigured, human_adjudication_required, scored },
    useful: ?bool,
    rubric: ?judgment.Result = null,
    provenance: ?Provenance = null,
    evidence_complete: bool,
};

/// Native publication and source fidelity are independent conjuncts. An
/// attempted execution without publication is a known useful-completion
/// failure; an unscored existing publication is unknown, never an assumed pass.
pub fn evaluate(a: std.mem.Allocator, attempted: bool, published: bool, source_fidelity: ?bool, target: ?Target, supplied: ?Supplied) !Evaluation {
    if (!attempted or !published) {
        if (target != null or supplied != null or (!attempted and source_fidelity != null)) return error.InvalidPublishedAssessment;
        return .{ .state = .not_required, .useful = if (attempted) false else null, .evidence_complete = true };
    }
    const native = target orelse return error.InvalidPublishedAssessment;
    try c.validateCapture(native.capture);
    if (native.capture.generation.origin != .live_generation or native.capture.generation.workflow_status != .completed or
        !c.id(native.output_id) or !sameHash(native.capture.specification, native.output_sha256) or
        !sameHash(native.capture.rubric_bytes, native.rubric_sha256)) return error.InvalidPublishedAssessment;
    const proposal = supplied orelse return .{ .state = .missing, .useful = if (source_fidelity == false) false else null, .evidence_complete = false };
    if (!std.mem.eql(u8, proposal.output_id, native.output_id) or !std.mem.eql(u8, proposal.output_sha256, native.output_sha256) or
        !std.mem.eql(u8, proposal.rubric_sha256, native.rubric_sha256) or !c.id(proposal.provenance.assessor)) return error.InvalidPublishedAssessment;
    // Retain and mechanically validate disputed judgments too; dispute does
    // not permit fabricated references, out-of-range scores or missing fields.
    const result = try judgment.validate(a, null, native.capture, try std.json.Stringify.valueAlloc(a, proposal.proposal, .{}));
    if (proposal.scoring_disputed) return .{ .state = .disputed, .useful = if (source_fidelity == false) false else null, .rubric = result, .provenance = proposal.provenance, .evidence_complete = false };
    // Model judgments have no acceptance authority under the human-review policy.
    // Retain model assessments as diagnostics, without useful-completion credit.
    if (proposal.provenance.kind == .model_assisted) return .{ .state = .human_adjudication_required, .useful = if (source_fidelity == false) false else null, .rubric = result, .provenance = proposal.provenance, .evidence_complete = false };
    const quality = acceptance.quality(native.capture.rubric, result);
    const state: @FieldType(Evaluation, "state") = switch (quality) {
        .passed, .failed => .scored,
        .unresolved => |reason| if (reason == .missing_threshold) .threshold_unconfigured else .unresolved,
    };
    return .{
        .state = state,
        .useful = if (source_fidelity == false or quality == .failed) false else if (source_fidelity == true and quality == .passed) true else null,
        .rubric = result,
        .provenance = proposal.provenance,
        .evidence_complete = state == .scored and source_fidelity != null,
    };
}
fn sameHash(bytes: []const u8, supplied: []const u8) bool {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.mem.eql(u8, &std.fmt.bytesToHex(digest, .lower), supplied);
}

pub const Workload = struct {
    feature_id: []const u8,
    well_posed: bool,
    attempted: bool,
    evaluation: Evaluation,
    physical_sends: u64,
    known_input_tokens: u64,
    known_output_tokens: u64,
    usage_complete: bool,
    elapsed_ns: ?u64,
};
pub const Distribution = struct { samples: u32 = 0, complete: bool = true, median: ?f64 = null, worst: ?u64 = null };
pub const Costs = struct {
    workloads: u32 = 0,
    sends: Distribution = .{},
    input_tokens: Distribution = .{},
    output_tokens: Distribution = .{},
    total_tokens: Distribution = .{},
    elapsed_ns: Distribution = .{},
};
pub const PerCompletion = struct {
    /// All dispatched workload cost, including failed and genuine-gap work,
    /// divided by known useful completions only when the denominator is complete.
    numerator: enum { all_dispatched_workloads } = .all_dispatched_workloads,
    physical_sends: ?f64 = null,
    input_tokens: ?f64 = null,
    output_tokens: ?f64 = null,
    total_tokens: ?f64 = null,
    elapsed_ns: ?f64 = null,
};
pub const Report = struct {
    scope: enum { native_published_output_against_frozen_rubric } = .native_published_output_against_frozen_rubric,
    completion: final_metrics.Report,
    rubric_evidence_complete: bool,
    known_input_tokens: u64,
    known_output_tokens: u64,
    actual_input_tokens: ?u64,
    actual_output_tokens: ?u64,
    total_elapsed_ns: ?u64,
    attempted_workload_cost: Costs,
    useful_workload_cost: Costs,
    amortized_per_useful_completion: PerCompletion,
    phase5_qualification_claim: bool = false,
    workflow_authority: bool = false,

    pub fn deinit(self: Report, a: std.mem.Allocator) void {
        self.completion.deinit(a);
    }
};

pub fn summarize(a: std.mem.Allocator, workloads: []const Workload) !Report {
    const labels = try a.alloc(final_metrics.Workload, workloads.len);
    defer a.free(labels);
    var sends: u64 = 0;
    var input: u64 = 0;
    var output: u64 = 0;
    var elapsed: u64 = 0;
    var usage_complete = true;
    var elapsed_complete = true;
    var rubric_complete = true;
    for (workloads, labels) |row, *label| {
        if (!row.attempted and (row.physical_sends != 0 or row.known_input_tokens != 0 or row.known_output_tokens != 0 or row.elapsed_ns != null or row.evaluation.useful != null)) return error.InvalidPublishedAssessment;
        label.* = .{ .feature_id = row.feature_id, .well_posed = row.well_posed, .attempted = row.attempted, .final_fidelity = if (row.well_posed) row.evaluation.useful else null };
        if (!row.attempted) continue;
        if (row.physical_sends == 0) return error.InvalidPublishedAssessment;
        sends = try std.math.add(u64, sends, row.physical_sends);
        input = try std.math.add(u64, input, row.known_input_tokens);
        output = try std.math.add(u64, output, row.known_output_tokens);
        usage_complete = usage_complete and row.usage_complete;
        if (row.elapsed_ns) |duration| elapsed = try std.math.add(u64, elapsed, duration) else elapsed_complete = false;
        if (row.well_posed and !row.evaluation.evidence_complete) rubric_complete = false;
    }
    const completion = try final_metrics.summarizeUseful(a, labels);
    errdefer completion.deinit(a);
    var per: PerCompletion = .{};
    if (completion.evidence_complete and rubric_complete and completion.successes != 0) {
        const n: f64 = @floatFromInt(completion.successes);
        per.physical_sends = @as(f64, @floatFromInt(sends)) / n;
        if (usage_complete) {
            per.input_tokens = @as(f64, @floatFromInt(input)) / n;
            per.output_tokens = @as(f64, @floatFromInt(output)) / n;
            per.total_tokens = @as(f64, @floatFromInt(try std.math.add(u64, input, output))) / n;
        }
        if (elapsed_complete) per.elapsed_ns = @as(f64, @floatFromInt(elapsed)) / n;
    }
    return .{
        .completion = completion,
        .rubric_evidence_complete = rubric_complete,
        .known_input_tokens = input,
        .known_output_tokens = output,
        .actual_input_tokens = if (usage_complete) input else null,
        .actual_output_tokens = if (usage_complete) output else null,
        .total_elapsed_ns = if (elapsed_complete) elapsed else null,
        .attempted_workload_cost = try costs(a, workloads, false),
        .useful_workload_cost = try costs(a, workloads, true),
        .amortized_per_useful_completion = per,
    };
}
fn costs(a: std.mem.Allocator, rows: []const Workload, useful_only: bool) !Costs {
    var result: Costs = .{};
    for (rows) |row| if (row.attempted and (!useful_only or (row.well_posed and row.evaluation.useful == true))) {
        result.workloads += 1;
    };
    inline for (.{ "sends", "input_tokens", "output_tokens", "total_tokens", "elapsed_ns" }) |field| {
        const values = try a.alloc(u64, result.workloads);
        defer a.free(values);
        var count: usize = 0;
        var complete = true;
        for (rows) |row| {
            if (!row.attempted or (useful_only and (!row.well_posed or row.evaluation.useful != true))) continue;
            const value: ?u64 = if (comptime std.mem.eql(u8, field, "sends")) row.physical_sends else if (comptime std.mem.eql(u8, field, "elapsed_ns")) row.elapsed_ns else if (!row.usage_complete) null else if (comptime std.mem.eql(u8, field, "input_tokens")) row.known_input_tokens else if (comptime std.mem.eql(u8, field, "output_tokens")) row.known_output_tokens else try std.math.add(u64, row.known_input_tokens, row.known_output_tokens);
            if (value) |known| {
                values[count] = known;
                count += 1;
            } else complete = false;
        }
        std.mem.sort(u64, values[0..count], {}, less);
        @field(result, field) = .{
            .samples = @intCast(count),
            .complete = complete,
            .median = if (!complete or count == 0) null else if (count % 2 == 1) @floatFromInt(values[count / 2]) else (@as(f64, @floatFromInt(values[count / 2 - 1])) + @as(f64, @floatFromInt(values[count / 2]))) / 2,
            .worst = if (complete and count != 0) values[count - 1] else null,
        };
    }
    return result;
}
fn less(_: void, left: u64, right: u64) bool {
    return left < right;
}

const Test = struct {
    const rubric: c.Rubric = .{
        .schema = "evaluation-rubric/v2",
        .id = "source-duty",
        .revision = 1,
        .minimum_score = 0,
        .maximum_score = 1,
        .pass_threshold_percent = 100,
        .criteria = &.{.{ .id = "deadline", .description = "Retain the deadline.", .evidence = "Compare source deadline.", .weight = 1, .allow_not_applicable = false, .minimum_acceptable_score = 1, .anchors = &.{ .{ .score = 0, .description = "Missing." }, .{ .score = 1, .description = "Preserved." } } }},
    };
    const criterion: judgment.CriterionResult = .{ .criterion_id = "deadline", .disposition = .scored, .score = 1, .explanation = "The specified deadline matches the source.", .evidence = &.{ .{ .document_id = "policy", .first_line = 1, .last_line = 1 }, .{ .document_id = "specification", .first_line = 1, .last_line = 1 } }, .missing_from_specification = false };
    const proposal: judgment.Proposal = .{ .results = &.{criterion} };
    fn target(a: std.mem.Allocator) !Target {
        const capture: c.Capture = .{
            .evaluation_id = "published-trial-1",
            .case = .{ .schema = "evaluation-case/v2", .id = "return-policy", .sources = &.{.{ .id = "policy", .path = "reference/policy.md" }}, .rubric = "rubric.json", .grading_qualification = .{ .panel = "panel.json", .review = "review.json", .qualification = "qualification.json" } },
            .case_bytes = "frozen-case",
            .rubric = rubric,
            .rubric_bytes = try std.json.Stringify.valueAlloc(a, rubric, .{}),
            .sources = &.{.{ .id = "policy", .text = "Return within 30 days." }},
            .specification = "Return within 30 days.",
            .generation = .{ .origin = .live_generation, .workflow_status = .completed, .execution_id = "run-1", .models = &.{.{ .slot = "spec_generation", .provider = "aws-bedrock", .model = "openai.gpt-oss-20b-1:0" }} },
        };
        return .{ .output_id = "published-specification", .output_sha256 = try hash(a, capture.specification), .rubric_sha256 = try hash(a, capture.rubric_bytes), .capture = capture };
    }
    fn supplied(native: Target) Supplied {
        return .{ .output_id = native.output_id, .output_sha256 = native.output_sha256, .rubric_sha256 = native.rubric_sha256, .provenance = .{ .kind = .human, .assessor = "reviewer" }, .proposal = proposal };
    }
    fn hash(a: std.mem.Allocator, bytes: []const u8) ![]const u8 {
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
        return a.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
    }
};

test "useful completion requires exact native publication source fidelity and frozen rubric" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const target = try Test.target(a);
    const supplied = Test.supplied(target);
    const success = try evaluate(a, true, true, true, target, supplied);
    try std.testing.expectEqual(@as(?bool, true), success.useful);
    try std.testing.expectEqual(.met, success.rubric.?.threshold);
    try std.testing.expect(success.evidence_complete);
    const unfaithful = try evaluate(a, true, true, false, target, supplied);
    try std.testing.expectEqual(@as(?bool, false), unfaithful.useful);
    const unknown_fidelity = try evaluate(a, true, true, null, target, supplied);
    try std.testing.expect(unknown_fidelity.useful == null and !unknown_fidelity.evidence_complete);
    const unpublished = try evaluate(a, true, false, false, null, null);
    try std.testing.expectEqual(@as(?bool, false), unpublished.useful);
    const unattempted = try evaluate(a, false, false, null, null, null);
    try std.testing.expect(unattempted.useful == null);
    const missing = try evaluate(a, true, true, true, target, null);
    try std.testing.expectEqual(.missing, missing.state);
    try std.testing.expect(missing.useful == null and !missing.evidence_complete);
    var model_assisted = supplied;
    model_assisted.provenance.kind = .model_assisted;
    const unqualified = try evaluate(a, true, true, true, target, model_assisted);
    try std.testing.expectEqual(.human_adjudication_required, unqualified.state);
    try std.testing.expect(unqualified.useful == null and !unqualified.evidence_complete);
    var disputed = supplied;
    disputed.scoring_disputed = true;
    try std.testing.expectEqual(.disputed, (try evaluate(a, true, true, true, target, disputed)).state);
}

test "published rubric rejects substituted output rubric references and unsupported criterion evidence" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const target = try Test.target(a);
    var supplied = Test.supplied(target);
    supplied.output_sha256 = target.rubric_sha256;
    try std.testing.expectError(error.InvalidPublishedAssessment, evaluate(a, true, true, true, target, supplied));
    supplied = Test.supplied(target);
    supplied.rubric_sha256 = target.output_sha256;
    try std.testing.expectError(error.InvalidPublishedAssessment, evaluate(a, true, true, true, target, supplied));
    supplied = Test.supplied(target);
    supplied.output_id = "earlier-candidate";
    try std.testing.expectError(error.InvalidPublishedAssessment, evaluate(a, true, true, true, target, supplied));
    supplied = Test.supplied(target);
    var criterion = Test.criterion;
    criterion.evidence = &.{.{ .document_id = "policy", .first_line = 9, .last_line = 9 }};
    supplied.proposal = .{ .results = &.{criterion} };
    try std.testing.expectError(error.InvalidEvaluationContract, evaluate(a, true, true, true, target, supplied));
    try std.testing.expectError(error.InvalidPublishedAssessment, evaluate(a, true, false, false, null, Test.supplied(target)));
    supplied = Test.supplied(target);
    supplied.proposal = .{ .results = &.{} };
    try std.testing.expectError(error.InvalidEvaluationContract, evaluate(a, true, true, true, target, supplied));
}

test "unresolved unconfigured and below-threshold rubric outcomes cannot become useful success" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var target = try Test.target(a);
    var supplied = Test.supplied(target);
    var criterion = Test.criterion;
    criterion.score = 0;
    supplied.proposal = .{ .results = &.{criterion} };
    const failed = try evaluate(a, true, true, true, target, supplied);
    try std.testing.expectEqual(@as(?bool, false), failed.useful);
    try std.testing.expect(failed.evidence_complete);
    criterion.score = null;
    criterion.disposition = .uncertain;
    supplied.proposal = .{ .results = &.{criterion} };
    const unresolved = try evaluate(a, true, true, true, target, supplied);
    try std.testing.expectEqual(.unresolved, unresolved.state);
    try std.testing.expect(unresolved.useful == null and !unresolved.evidence_complete);
    target.capture.rubric.pass_threshold_percent = null;
    target.capture.rubric_bytes = try std.json.Stringify.valueAlloc(a, target.capture.rubric, .{});
    target.rubric_sha256 = try Test.hash(a, target.capture.rubric_bytes);
    const unconfigured = try evaluate(a, true, true, true, target, Test.supplied(target));
    try std.testing.expectEqual(.threshold_unconfigured, unconfigured.state);
    try std.testing.expect(unconfigured.useful == null and !unconfigured.evidence_complete);
}

test "resource costs retain failed work and known partial usage without invented useful denominator" {
    const rows = [_]Workload{
        .{ .feature_id = "return-policy", .well_posed = true, .attempted = true, .evaluation = .{ .state = .scored, .useful = true, .evidence_complete = true }, .physical_sends = 2, .known_input_tokens = 10, .known_output_tokens = 5, .usage_complete = true, .elapsed_ns = 100 },
        .{ .feature_id = "return-policy", .well_posed = true, .attempted = true, .evaluation = .{ .state = .not_required, .useful = false, .evidence_complete = true }, .physical_sends = 4, .known_input_tokens = 30, .known_output_tokens = 15, .usage_complete = true, .elapsed_ns = 300 },
    };
    const report = try summarize(std.testing.allocator, &rows);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(?f64, 0.5), report.completion.rate);
    try std.testing.expectEqual(@as(?f64, 6), report.amortized_per_useful_completion.physical_sends);
    try std.testing.expectEqual(@as(?f64, 60), report.amortized_per_useful_completion.total_tokens);
    try std.testing.expectEqual(@as(?f64, 30), report.attempted_workload_cost.total_tokens.median);
    try std.testing.expectEqual(@as(?u64, 45), report.attempted_workload_cost.total_tokens.worst);
    try std.testing.expectEqual(@as(?f64, 15), report.useful_workload_cost.total_tokens.median);
    try std.testing.expect(!report.phase5_qualification_claim and !report.workflow_authority);
    var partial_rows = rows;
    partial_rows[1].usage_complete = false;
    partial_rows[1].evaluation = .{ .state = .missing, .useful = null, .evidence_complete = false };
    const partial = try summarize(std.testing.allocator, &partial_rows);
    defer partial.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u64, 40), partial.known_input_tokens);
    try std.testing.expect(partial.actual_input_tokens == null and partial.attempted_workload_cost.total_tokens.median == null);
    try std.testing.expect(partial.completion.rate == null and partial.amortized_per_useful_completion.physical_sends == null);
}
