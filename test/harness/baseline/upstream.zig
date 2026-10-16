//! Source-backed observations of original extraction/reconciliation responses.
//! These judgments never replace specification-generation fidelity, alter its
//! sizing metric, admit a native response, or authorize workflow continuation.
const std = @import("std");
const comparison = @import("../generation_comparison.zig");
const contracts = @import("../contracts.zig");
const stages = @import("stages.zig");
const Origin = @import("../../../src/domain/model_candidate_origin.zig").Origin;

pub const Error = std.mem.Allocator.Error || error{InvalidUpstreamAssessment};
pub const Stage = enum { extraction, reconciliation };
pub const Outcome = enum { faithful, material_failure, mechanical_failure };
/// Constructed from verified native receipts and exact archived model text;
/// never decoded from an assessor's document. Missing text remains missing.
pub const Target = struct {
    call: usize,
    origin: Origin,
    purpose: stages.Purpose,
    owner_kind: stages.OwnerKind,
    output_id: ?[]const u8,
    text: ?[]const u8,
    sha256: ?[]const u8,
    /// Only an exact native provider/protocol rejection proves this flag.
    mechanical_failure: bool = false,
    usage: ?comparison.Usage = null,
    uncertain_delivery: bool = false,
};
/// Assessor provenance is inherited from the containing assessment entry.
pub const Judgment = struct {
    origin: Origin,
    output_id: ?[]const u8,
    output_sha256: ?[]const u8,
    outcome: Outcome,
    explanation: []const u8,
    source_refs: []const comparison.SourceRef,
    output_quote: ?[]const u8,
    scoring_disputed: bool = false,
};
pub const Result = struct {
    call: usize,
    origin: Origin,
    stage: Stage,
    original: bool,
    output_id: ?[]const u8,
    outcome: ?Outcome,
    mechanical_failure: bool,
    disputed: bool,
};
pub const Counts = struct {
    targets: u32 = 0,
    faithful: u32 = 0,
    material_failures: u32 = 0,
    mechanical_failures: u32 = 0,
    native_mechanical_failures: u32 = 0,
    unknown: u32 = 0,
    disputed: u32 = 0,
};
pub const Assessment = struct {
    scope: enum { supplied_original_upstream_assessment } = .supplied_original_upstream_assessment,
    results: []const Result,
    original: Counts,
    corrective: Counts,
    /// Only original assignments are mandatory for this separate measure.
    evidence_complete: bool,
    original_evidence_complete: bool,
    corrective_evidence_complete: bool,
    generation_sizing_metric_changed: bool = false,
    workflow_authority: bool = false,

    /// Result IDs borrow the capture; only the result array is owned here.
    pub fn deinit(self: Assessment, a: std.mem.Allocator) void {
        a.free(self.results);
    }
};

pub fn stage(target: Target) Error!Stage {
    if (target.purpose != .initial_generation and target.purpose != .atomic_repair and target.purpose != .context_followup) return error.InvalidUpstreamAssessment;
    return switch (target.owner_kind) {
        .reference_chunk => .extraction,
        .reference_global => .reconciliation,
        .workflow_step, .specification_unit, .plan_unit, .task_cluster, .implementation_operation, .semantic_review => error.InvalidUpstreamAssessment,
    };
}
pub fn requiredOriginal(target: Target) bool {
    return target.purpose == .initial_generation and target.origin.attempt.value == 1 and switch (target.owner_kind) {
        .reference_chunk, .reference_global => true,
        .workflow_step, .specification_unit, .plan_unit, .task_cluster, .implementation_operation, .semantic_review => false,
    };
}
fn sameOptional(left: ?[]const u8, right: ?[]const u8) bool {
    if (left) |value| return if (right) |other| std.mem.eql(u8, value, other) else false;
    return right == null;
}
fn validateTarget(target: Target) Error!void {
    _ = try stage(target);
    if (target.call == 0 or target.origin.request.value == 0 or target.origin.attempt.value == 0 or target.origin.kind != .inference) return error.InvalidUpstreamAssessment;
    if (target.text) |text| {
        const id = target.output_id orelse return error.InvalidUpstreamAssessment;
        const sha256 = target.sha256 orelse return error.InvalidUpstreamAssessment;
        if (!contracts.id(id) or !std.unicode.utf8ValidateSlice(text)) return error.InvalidUpstreamAssessment;
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(text, &digest, .{});
        if (!std.mem.eql(u8, sha256, &std.fmt.bytesToHex(digest, .lower))) return error.InvalidUpstreamAssessment;
    } else if (target.output_id != null or target.sha256 != null) return error.InvalidUpstreamAssessment;
    if (target.usage) |usage| _ = std.math.add(u64, usage.input_tokens, usage.output_tokens) catch return error.InvalidUpstreamAssessment;
}
fn validateJudgment(example: comparison.Case, target: Target, judgment: Judgment) Error!void {
    if (!std.meta.eql(target.origin, judgment.origin) or !sameOptional(target.output_id, judgment.output_id) or
        !sameOptional(target.sha256, judgment.output_sha256) or !contracts.text(judgment.explanation) or judgment.source_refs.len == 0) return error.InvalidUpstreamAssessment;
    for (judgment.source_refs, 0..) |reference, index| {
        if (!contracts.text(reference.quote)) return error.InvalidUpstreamAssessment;
        const source = for (example.sources) |source| {
            if (std.mem.eql(u8, source.id, reference.source_id)) break source;
        } else return error.InvalidUpstreamAssessment;
        if (std.mem.indexOf(u8, source.text, reference.quote) == null) return error.InvalidUpstreamAssessment;
        for (judgment.source_refs[0..index]) |prior| if (std.mem.eql(u8, prior.source_id, reference.source_id) and std.mem.eql(u8, prior.quote, reference.quote)) return error.InvalidUpstreamAssessment;
    }
    if (judgment.output_quote) |quote| {
        const text = target.text orelse return error.InvalidUpstreamAssessment;
        if (!contracts.text(quote) or std.mem.indexOf(u8, text, quote) == null) return error.InvalidUpstreamAssessment;
    }
    switch (judgment.outcome) {
        .faithful => if (target.mechanical_failure or target.text == null or judgment.output_quote == null) return error.InvalidUpstreamAssessment,
        .material_failure => if (target.text == null or judgment.output_quote == null) return error.InvalidUpstreamAssessment,
        .mechanical_failure => if (!target.mechanical_failure) return error.InvalidUpstreamAssessment,
    }
}
fn accumulate(counts: *Counts, result: Result) void {
    counts.targets += 1;
    if (result.mechanical_failure) counts.native_mechanical_failures += 1;
    if (result.disputed) counts.disputed += 1;
    if (result.outcome) |outcome| switch (outcome) {
        .faithful => counts.faithful += 1,
        .material_failure => counts.material_failures += 1,
        .mechanical_failure => counts.mechanical_failures += 1,
    } else counts.unknown += 1;
}

/// Every original native upstream assignment needs its own source-backed label.
/// A later successful correction cannot satisfy an omitted original judgment.
pub fn evaluate(a: std.mem.Allocator, example: comparison.Case, targets: []const Target, judgments: []const Judgment) Error!Assessment {
    comparison.validateCase(example) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidUpstreamAssessment;
    if (targets.len > std.math.maxInt(u32)) return error.InvalidUpstreamAssessment;
    for (targets, 0..) |target, index| {
        try validateTarget(target);
        for (targets[0..index]) |prior| if (std.meta.eql(prior.origin, target.origin) or prior.call == target.call or
            (prior.output_id != null and sameOptional(prior.output_id, target.output_id))) return error.InvalidUpstreamAssessment;
    }
    for (judgments, 0..) |judgment, index| {
        for (judgments[0..index]) |prior| if (std.meta.eql(prior.origin, judgment.origin)) return error.InvalidUpstreamAssessment;
        const target = for (targets) |target| {
            if (std.meta.eql(target.origin, judgment.origin)) break target;
        } else return error.InvalidUpstreamAssessment;
        try validateJudgment(example, target, judgment);
    }
    const results = try a.alloc(Result, targets.len);
    errdefer a.free(results);
    var original: Counts = .{};
    var corrective: Counts = .{};
    for (targets, results) |target, *result| {
        const supplied: ?Judgment = for (judgments) |judgment| {
            if (std.meta.eql(target.origin, judgment.origin)) break judgment;
        } else null;
        const disputed = if (supplied) |judgment| judgment.scoring_disputed else false;
        result.* = .{
            .call = target.call,
            .origin = target.origin,
            .stage = try stage(target),
            .original = requiredOriginal(target),
            .output_id = target.output_id,
            .outcome = if (supplied != null and !disputed) supplied.?.outcome else null,
            .mechanical_failure = target.mechanical_failure,
            .disputed = disputed,
        };
        accumulate(if (result.original) &original else &corrective, result.*);
    }
    return .{
        .results = results,
        .original = original,
        .corrective = corrective,
        .evidence_complete = original.unknown == 0,
        .original_evidence_complete = original.unknown == 0,
        .corrective_evidence_complete = corrective.unknown == 0,
    };
}

fn fixtureCase(comptime index: usize) comparison.Case {
    const text = if (index == 0) "Retain the loan return date until the final receipt." else "Notify the parcel recipient only after consent.";
    return .{
        .id = if (index == 0) "loan.base" else "parcel.base",
        .feature_id = if (index == 0) "loan" else "parcel",
        .partition = .development,
        .variant = .base,
        .domain = if (index == 0) "loans" else "delivery",
        .size = .small,
        .risk_tags = &.{"condition"},
        .sources = &.{.{ .id = "source", .path = "requirements.md", .text = text }},
        .duties = &.{.{ .id = "preserve", .description = "Preserve the stated condition.", .source_refs = &.{.{ .source_id = "source", .quote = text }}, .exact_values = &.{} }},
        .expected_terminal = .completed,
        .expected_questions = &.{},
        .permissible_alternatives = &.{},
        .forbidden_additions = &.{},
    };
}
fn fixtureTarget(a: std.mem.Allocator, request: usize, attempt: u32, owner: stages.OwnerKind, text: ?[]const u8, failure: bool) !Target {
    var target: Target = .{ .call = request * 100 + attempt, .origin = .{ .request = .{ .value = request }, .attempt = .{ .value = attempt } }, .purpose = .initial_generation, .owner_kind = owner, .output_id = null, .text = text, .sha256 = null, .mechanical_failure = failure };
    if (text) |bytes| {
        target.output_id = try std.fmt.allocPrint(a, "upstream-{d}-{d}", .{ request, attempt });
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
        target.sha256 = try a.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
    }
    return target;
}
fn fixtureJudgment(a: std.mem.Allocator, example: comparison.Case, target: Target, outcome: Outcome) !Judgment {
    return .{
        .origin = target.origin,
        .output_id = target.output_id,
        .output_sha256 = target.sha256,
        .outcome = outcome,
        .explanation = "Supplied source-backed judgment of this exact native upstream response.",
        .source_refs = try a.dupe(comparison.SourceRef, &.{.{ .source_id = "source", .quote = example.sources[0].text }}),
        .output_quote = target.text,
    };
}

test "upstream originals retain losses independently of later corrected extraction and grouping" {
    inline for (0..2) |index| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const example = fixtureCase(index);
        const targets = [_]Target{
            try fixtureTarget(a, 1, 1, .reference_chunk, "Ignore the stated condition.", false),
            try fixtureTarget(a, 1, 2, .reference_chunk, example.sources[0].text, false),
            try fixtureTarget(a, 2, 1, .reference_global, example.sources[0].text, false),
        };
        const judgments = [_]Judgment{
            try fixtureJudgment(a, example, targets[0], .material_failure),
            try fixtureJudgment(a, example, targets[1], .faithful),
            try fixtureJudgment(a, example, targets[2], .faithful),
        };
        const assessed = try evaluate(a, example, &targets, &judgments);
        defer assessed.deinit(a);
        try std.testing.expect(assessed.evidence_complete and assessed.original_evidence_complete and assessed.corrective_evidence_complete);
        try std.testing.expectEqual(@as(u32, 2), assessed.original.targets);
        try std.testing.expectEqual(@as(u32, 1), assessed.original.material_failures);
        try std.testing.expectEqual(@as(u32, 1), assessed.original.faithful);
        try std.testing.expectEqual(@as(u32, 1), assessed.corrective.faithful);
        try std.testing.expectEqual(Stage.extraction, assessed.results[0].stage);
        try std.testing.expectEqual(Stage.reconciliation, assessed.results[2].stage);
        try std.testing.expect(!assessed.generation_sizing_metric_changed and !assessed.workflow_authority);
        const omitted = try evaluate(a, example, &targets, judgments[1..]);
        defer omitted.deinit(a);
        try std.testing.expect(!omitted.evidence_complete and omitted.corrective_evidence_complete);
        try std.testing.expectEqual(@as(u32, 1), omitted.original.unknown);
        const original_only = try evaluate(a, example, &targets, &.{ judgments[0], judgments[2] });
        defer original_only.deinit(a);
        try std.testing.expect(original_only.evidence_complete and !original_only.corrective_evidence_complete);
        try std.testing.expectEqual(@as(u32, 1), original_only.corrective.unknown);
        var disputed = judgments;
        disputed[0].scoring_disputed = true;
        const uncertain = try evaluate(a, example, &targets, &disputed);
        defer uncertain.deinit(a);
        try std.testing.expect(!uncertain.evidence_complete);
        try std.testing.expectEqual(@as(u32, 1), uncertain.original.disputed);
        try std.testing.expectEqual(@as(u32, 0), uncertain.original.material_failures);
    }
}

test "upstream judgment bindings reject corrected substitution foreign provenance and fabricated mechanical proof" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const example = fixtureCase(1);
    const original = try fixtureTarget(a, 1, 1, .reference_chunk, example.sources[0].text, false);
    const corrected = try fixtureTarget(a, 1, 2, .reference_chunk, "A later corrected response.", false);
    const judgment = try fixtureJudgment(a, example, original, .faithful);
    var wrong = judgment;
    wrong.output_id = corrected.output_id;
    wrong.output_sha256 = corrected.sha256;
    try std.testing.expectError(error.InvalidUpstreamAssessment, evaluate(a, example, &.{ original, corrected }, &.{wrong}));
    wrong = judgment;
    wrong.output_quote = "Invented output quote.";
    try std.testing.expectError(error.InvalidUpstreamAssessment, evaluate(a, example, &.{original}, &.{wrong}));
    wrong = judgment;
    wrong.source_refs = &.{.{ .source_id = "source", .quote = "Invented source authority." }};
    try std.testing.expectError(error.InvalidUpstreamAssessment, evaluate(a, example, &.{original}, &.{wrong}));
    wrong = judgment;
    wrong.origin.request.value = 99;
    try std.testing.expectError(error.InvalidUpstreamAssessment, evaluate(a, example, &.{original}, &.{wrong}));
    try std.testing.expectError(error.InvalidUpstreamAssessment, evaluate(a, example, &.{original}, &.{ judgment, judgment }));
    var tampered = original;
    tampered.text = "Different retained output bytes.";
    try std.testing.expectError(error.InvalidUpstreamAssessment, evaluate(a, example, &.{tampered}, &.{judgment}));
    const rejected = try fixtureTarget(a, 2, 1, .reference_global, null, true);
    const mechanical = try fixtureJudgment(a, example, rejected, .mechanical_failure);
    const known = try evaluate(a, example, &.{rejected}, &.{mechanical});
    defer known.deinit(a);
    try std.testing.expectEqual(@as(u32, 1), known.original.mechanical_failures);
    try std.testing.expectEqual(@as(u32, 1), known.original.native_mechanical_failures);
    var unproved = rejected;
    unproved.mechanical_failure = false;
    try std.testing.expectError(error.InvalidUpstreamAssessment, evaluate(a, example, &.{unproved}, &.{mechanical}));
    const missing = try evaluate(a, example, &.{unproved}, &.{});
    defer missing.deinit(a);
    try std.testing.expect(!missing.evidence_complete);
    try std.testing.expectEqual(@as(u32, 1), missing.original.unknown);
    var native_rejected = original;
    native_rejected.mechanical_failure = true;
    try std.testing.expectError(error.InvalidUpstreamAssessment, evaluate(a, example, &.{native_rejected}, &.{judgment}));
}

test "upstream context followups and repairs remain separate from typed original assignment coverage" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const example = fixtureCase(0);
    var followup = try fixtureTarget(a, 1, 1, .reference_global, example.sources[0].text, false);
    followup.purpose = .context_followup;
    var repair = try fixtureTarget(a, 2, 1, .reference_chunk, example.sources[0].text, false);
    repair.purpose = .atomic_repair;
    const report = try evaluate(a, example, &.{ followup, repair }, &.{});
    defer report.deinit(a);
    try std.testing.expectEqual(@as(u32, 0), report.original.targets);
    try std.testing.expectEqual(@as(u32, 2), report.corrective.unknown);
    try std.testing.expect(report.original_evidence_complete and !report.corrective_evidence_complete);
    var wrong_owner = followup;
    wrong_owner.owner_kind = .specification_unit;
    try std.testing.expect(!requiredOriginal(wrong_owner));
    try std.testing.expectError(error.InvalidUpstreamAssessment, evaluate(a, example, &.{wrong_owner}, &.{}));
    var wrong_purpose = followup;
    wrong_purpose.purpose = .semantic_review;
    try std.testing.expectError(error.InvalidUpstreamAssessment, evaluate(a, example, &.{wrong_purpose}, &.{}));
}
