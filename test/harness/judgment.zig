//! Mechanical accounting of model judgments, never proof of semantic quality.
const std = @import("std");
const c = @import("contracts.zig");
const strict = @import("../../src/domain/strict_json.zig");
const coordinates = @import("../../src/domain/source_coordinates.zig");
/// Report-owned diagnostic data; indices are zero-based, IDs are from the rubric.
pub const Diagnostic = struct {
    reason: enum { json, invalid_shape, criterion_count, duplicate_criterion, missing_criterion, empty_explanation, missing_source_evidence, missing_specification_evidence, unknown_document, invalid_line_range, blank_evidence, invalid_score, invalid_disposition },
    criterion_id: ?[]const u8 = null,
    evidence_index: ?usize = null,
    document_id: ?[]const u8 = null,
    json: ?strict.Diagnostic = null,
};
pub const schema_revision = "rubric-judgment/v2";
/// Evidence names inclusive, 1-based lines of one supplied document. The
/// harness resolves their exact bytes; the judge never copies text.
pub const Evidence = struct { document_id: []const u8, first_line: u32, last_line: u32 };
pub const NumberedLine = struct { line: u32, text: []const u8 };
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
            const location: Diagnostic = .{ .reason = .unknown_document, .criterion_id = criterion.id, .evidence_index = index, .document_id = evidence.document_id };
            const text = documentText(capture, evidence.document_id) orelse return reject(diagnostic, location);
            if (std.mem.eql(u8, evidence.document_id, "specification")) candidate_evidence = true else source_evidence = true;
            const cited = (try lineSpan(text, evidence.first_line, evidence.last_line)) orelse {
                var invalid = location;
                invalid.reason = .invalid_line_range;
                return reject(diagnostic, invalid);
            };
            if (!c.text(cited)) {
                var blank = location;
                blank.reason = .blank_evidence;
                return reject(diagnostic, blank);
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

/// The supplied document a locator names, or null when the judge invented one.
pub fn documentText(capture: c.Capture, id: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, id, "specification")) return capture.specification;
    for (capture.sources) |source| if (std.mem.eql(u8, source.id, id)) return source.text;
    return null;
}

/// Line boundaries for judge packets, evidence checks and reports come from the
/// shared source-coordinate owner: CR, LF and CRLF each end one line, and a final
/// terminator ends the last line instead of starting another. Lines are 1-based.
const LineIterator = struct {
    text: []const u8,
    position: coordinates.Position = .{ .byte = 0, .line = 1, .column = 1 },
    start: usize = 0,
    const Line = struct { start: usize, end: usize };
    fn next(self: *LineIterator) c.Error!?Line {
        while (self.position.byte < self.text.len) {
            const current = self.position;
            self.position = coordinates.advance(self.text, current) catch return error.InvalidEvaluationContract;
            if (self.position.line != current.line) {
                defer self.start = self.position.byte;
                return .{ .start = self.start, .end = current.byte };
            }
        }
        if (self.start >= self.text.len) return null;
        defer self.start = self.text.len;
        return .{ .start = self.start, .end = self.text.len };
    }
};

pub fn lineCount(text: []const u8) c.Error!usize {
    var lines: LineIterator = .{ .text = text };
    var count: usize = 0;
    while (try lines.next()) |_| count += 1;
    return count;
}

/// Exact bytes from the start of line `first` to the end of line `last`, without
/// its terminator; null for an empty, reversed or out-of-range locator.
pub fn lineSpan(text: []const u8, first: u32, last: u32) c.Error!?[]const u8 {
    if (first == 0 or first > last) return null;
    var lines: LineIterator = .{ .text = text };
    var number: u32 = 0;
    var span_start: usize = 0;
    while (try lines.next()) |line| {
        number += 1;
        if (number == first) span_start = line.start;
        if (number == last) return text[span_start..line.end];
    }
    return null;
}

pub fn numberedLines(allocator: std.mem.Allocator, text: []const u8) c.Error![]const NumberedLine {
    var output: std.ArrayList(NumberedLine) = .empty;
    errdefer output.deinit(allocator);
    var lines: LineIterator = .{ .text = text };
    while (try lines.next()) |line| {
        const number = std.math.cast(u32, output.items.len + 1) orelse return error.InvalidEvaluationContract;
        try output.append(allocator, .{ .line = number, .text = text[line.start..line.end] });
    }
    return output.toOwnedSlice(allocator);
}

fn reject(out: ?*?Diagnostic, value: Diagnostic) error{InvalidEvaluationContract} {
    if (out) |slot| slot.* = value;
    return error.InvalidEvaluationContract;
}
