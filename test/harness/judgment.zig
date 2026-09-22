//! Mechanical accounting of model judgments, never proof of semantic quality.
const std = @import("std");
const c = @import("contracts.zig");
const strict = @import("../../src/domain/strict_json.zig");
/// Report-owned diagnostic data; indices are zero-based, IDs are from the rubric.
pub const Diagnostic = struct {
    reason: enum { json, invalid_shape, criterion_count, duplicate_criterion, missing_criterion, empty_explanation, missing_source_evidence, missing_specification_evidence, empty_quote, unknown_document, quote_not_found, invalid_score, invalid_disposition },
    criterion_id: ?[]const u8 = null,
    evidence_index: ?usize = null,
    document_id: ?[]const u8 = null,
    json: ?strict.Diagnostic = null,
};
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

pub fn validate(allocator: std.mem.Allocator, diagnostic: ?*?Diagnostic, capture: c.Capture, bytes: []const u8) c.Error!Result {
    if (diagnostic) |out| out.* = null;
    try c.validateCapture(capture);
    const proposal = c.decode(Proposal, allocator, bytes) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        // Diagnose only a failed decode, using the same parser and depth contract.
        if (diagnostic != null) {
            var detail: ?strict.Diagnostic = null;
            var parsed = strict.parse(allocator, bytes, c.json_limits, false, &detail) catch |parse_error| {
                if (parse_error == error.OutOfMemory) return error.OutOfMemory;
                return reject(diagnostic, .{ .reason = .json, .json = detail });
            };
            parsed.deinit();
        }
        return reject(diagnostic, .{ .reason = .invalid_shape });
    };
    if (proposal.results.len != capture.rubric.criteria.len) return reject(diagnostic, .{ .reason = .criterion_count });
    const ordered = try allocator.alloc(CriterionResult, proposal.results.len);
    var earned: u128 = 0;
    var possible: u128 = 0;
    var uncertain = false;
    for (capture.rubric.criteria, ordered) |criterion, *output| {
        var matched: ?CriterionResult = null;
        for (proposal.results) |result| {
            if (!std.mem.eql(u8, criterion.id, result.criterion_id)) continue;
            if (matched != null) return reject(diagnostic, .{ .reason = .duplicate_criterion, .criterion_id = criterion.id });
            matched = result;
        }
        const result = matched orelse return reject(diagnostic, .{ .reason = .missing_criterion, .criterion_id = criterion.id });
        if (!c.text(result.explanation)) return reject(diagnostic, .{ .reason = .empty_explanation, .criterion_id = criterion.id });
        var source_evidence = false;
        var candidate_evidence = false;
        for (result.evidence, 0..) |evidence, index| {
            const location: Diagnostic = .{ .reason = .empty_quote, .criterion_id = criterion.id, .evidence_index = index, .document_id = evidence.document_id };
            if (!c.text(evidence.quote)) return reject(diagnostic, location);
            const document = if (std.mem.eql(u8, evidence.document_id, "specification")) blk: {
                candidate_evidence = true;
                break :blk capture.specification;
            } else blk: {
                for (capture.sources) |source| if (std.mem.eql(u8, source.id, evidence.document_id)) {
                    source_evidence = true;
                    break :blk source.text;
                };
                var unknown = location;
                unknown.reason = .unknown_document;
                return reject(diagnostic, unknown);
            };
            if (std.mem.indexOf(u8, document, evidence.quote) == null) {
                var invalid = location;
                invalid.reason = .quote_not_found;
                return reject(diagnostic, invalid);
            }
        }
        if (!source_evidence) return reject(diagnostic, .{ .reason = .missing_source_evidence, .criterion_id = criterion.id });
        if (!candidate_evidence and !result.missing_from_specification) return reject(diagnostic, .{ .reason = .missing_specification_evidence, .criterion_id = criterion.id });
        switch (result.disposition) {
            .scored => {
                const score = result.score orelse return reject(diagnostic, .{ .reason = .invalid_score, .criterion_id = criterion.id });
                if (score < capture.rubric.minimum_score or score > capture.rubric.maximum_score) return reject(diagnostic, .{ .reason = .invalid_score, .criterion_id = criterion.id });
                earned += @as(u128, score - capture.rubric.minimum_score) * criterion.weight;
                possible += @as(u128, capture.rubric.maximum_score - capture.rubric.minimum_score) * criterion.weight;
            },
            .uncertain => {
                if (result.score != null) return reject(diagnostic, .{ .reason = .invalid_score, .criterion_id = criterion.id });
                uncertain = true;
            },
            .not_applicable => {
                if (!criterion.allow_not_applicable or result.score != null) return reject(diagnostic, .{ .reason = .invalid_disposition, .criterion_id = criterion.id });
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

fn reject(out: ?*?Diagnostic, value: Diagnostic) error{InvalidEvaluationContract} {
    if (out) |slot| slot.* = value;
    return error.InvalidEvaluationContract;
}
