//! Mechanical accounting of model judgments, never proof of semantic quality.
const std = @import("std");
const c = @import("contracts.zig");
pub const schema_revision = "rubric-judgment/v1";
pub const Evidence = struct { document_id: []const u8, quote: []const u8 };
pub const CriterionResult = struct {
    criterion_id: []const u8,
    disposition: enum { scored, uncertain, not_applicable },
    score: ?u16,
    explanation: []const u8,
    evidence: []const Evidence,
    missing_from_specification: bool,
};
pub const Proposal = struct { results: []const CriterionResult };
pub const Assessment = enum { scored, unresolved, no_applicable_criteria };
pub const Threshold = enum { not_configured, met, not_met, undetermined };
pub const Result = struct {
    results: []const CriterionResult,
    assessment: Assessment,
    score_percent: ?f64,
    threshold: Threshold,
};

pub fn validate(allocator: std.mem.Allocator, capture: c.Capture, bytes: []const u8) c.Error!Result {
    try c.validateCapture(capture);
    const proposal = try c.decode(Proposal, allocator, bytes);
    if (proposal.results.len != capture.rubric.criteria.len) return error.InvalidEvaluationContract;
    const ordered = try allocator.alloc(CriterionResult, proposal.results.len);
    var earned: u128 = 0;
    var possible: u128 = 0;
    var uncertain = false;
    for (capture.rubric.criteria, ordered) |criterion, *output| {
        var matched: ?CriterionResult = null;
        for (proposal.results) |result| {
            if (!std.mem.eql(u8, criterion.id, result.criterion_id)) continue;
            if (matched != null) return error.InvalidEvaluationContract;
            matched = result;
        }
        const result = matched orelse return error.InvalidEvaluationContract;
        if (!c.text(result.explanation) or result.evidence.len == 0) return error.InvalidEvaluationContract;
        var source_evidence = false;
        var candidate_evidence = false;
        for (result.evidence) |evidence| {
            if (!c.text(evidence.quote)) return error.InvalidEvaluationContract;
            const document = if (std.mem.eql(u8, evidence.document_id, "specification")) blk: {
                candidate_evidence = true;
                break :blk capture.specification;
            } else blk: {
                for (capture.sources) |source| if (std.mem.eql(u8, source.id, evidence.document_id)) {
                    source_evidence = true;
                    break :blk source.text;
                };
                return error.InvalidEvaluationContract;
            };
            if (std.mem.indexOf(u8, document, evidence.quote) == null) return error.InvalidEvaluationContract;
        }
        if (!source_evidence or (!candidate_evidence and !result.missing_from_specification)) return error.InvalidEvaluationContract;
        switch (result.disposition) {
            .scored => {
                const score = result.score orelse return error.InvalidEvaluationContract;
                if (score < capture.rubric.minimum_score or score > capture.rubric.maximum_score) return error.InvalidEvaluationContract;
                earned += @as(u128, score - capture.rubric.minimum_score) * criterion.weight;
                possible += @as(u128, capture.rubric.maximum_score - capture.rubric.minimum_score) * criterion.weight;
            },
            .uncertain => {
                if (result.score != null) return error.InvalidEvaluationContract;
                uncertain = true;
            },
            .not_applicable => {
                if (!criterion.allow_not_applicable or result.score != null) return error.InvalidEvaluationContract;
            },
        }
        output.* = result;
    }
    const percent: ?f64 = if (uncertain or possible == 0) null else @as(f64, @floatFromInt(earned)) * 100 / @as(f64, @floatFromInt(possible));
    return .{
        .results = ordered,
        .assessment = if (uncertain) .unresolved else if (possible == 0) .no_applicable_criteria else .scored,
        .score_percent = percent,
        .threshold = if (capture.rubric.pass_threshold_percent) |threshold|
            if (percent) |score| if (score >= threshold) .met else .not_met else .undetermined
        else
            .not_configured,
    };
}
