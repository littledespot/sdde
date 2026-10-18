//! One bounded correction of a mechanically invalid judgment (user decision,
//! 18 October 2026). It reports the canonical validator's exact diagnostic and
//! never asks the judge to reconsider a valid result or score.
const std = @import("std");
const c = @import("contracts.zig");
const judgment = @import("judgment.zig");
const strict = @import("../../src/domain/strict_json.zig");
pub const Reason = @FieldType(judgment.Diagnostic, "reason");

/// Corrections a report may contain; the evaluator and the report reader both
/// enforce this hashed value.
pub const attempts = 1;
pub const instruction = "The previous judgment failed validation. Correct only the reported error and return the complete judgment again. " ++
    "Keep every other criterion result, including its disposition, score, explanation and evidence, unchanged.";
/// Model-visible statement of the evidence-defect grade pin.
pub const keep_grade = "Correct only this result's evidence; keep its disposition and score unchanged.";

/// Mechanical defects only: missing evidence, invalid line references, missing
/// criteria and malformed output. Score, disposition, duplicate and explanation
/// defects are judgment content and end the evaluation.
pub fn correctable(reason: Reason) bool {
    return explanation(reason) != null;
}

/// An evidence defect is corrected in its evidence: the named result keeps its
/// disposition and score, so a correction cannot regrade it.
pub fn evidenceDefect(reason: Reason) bool {
    return switch (reason) {
        .missing_source_evidence, .missing_specification_evidence, .blank_evidence, .unknown_document, .invalid_line_range => true,
        else => false,
    };
}

pub fn explanation(reason: Reason) ?[]const u8 {
    return switch (reason) {
        .json => "The response is not valid JSON.",
        .invalid_shape => "The response does not match the judgment schema.",
        .criterion_count => "The response must contain exactly one result for every rubric criterion.",
        .missing_criterion => "This rubric criterion has no result.",
        .missing_source_evidence => "This result cites no source lines; every result requires source evidence.",
        .missing_specification_evidence => "This result cites no specification lines and does not mark the content missing from the specification.",
        .blank_evidence => "This evidence locator names only blank lines.",
        .unknown_document => "This evidence locator names a document that was not supplied.",
        .invalid_line_range => "This evidence locator names lines outside the supplied document.",
        .duplicate_criterion, .empty_explanation, .invalid_score, .invalid_disposition, .changed_criterion => null,
    };
}

pub const Correction = struct { rejected: []const u8, diagnostic: judgment.Diagnostic };

/// Model-visible guidance: the validator's typed location, a fixed explanation
/// and the fixed instruction. The affected criterion is named when one exists.
pub fn guidance(a: std.mem.Allocator, diagnostic: judgment.Diagnostic) c.Error![]const u8 {
    const text = explanation(diagnostic.reason) orelse return error.InvalidEvaluationContract;
    return std.json.Stringify.valueAlloc(a, .{
        .diagnostic = .{
            .reason = diagnostic.reason,
            .criterion_id = diagnostic.criterion_id,
            .evidence_index = diagnostic.evidence_index,
            .document_id = diagnostic.document_id,
            .json = if (diagnostic.json) |detail| .{ .reason = detail.reason, .location = detail.location } else null,
        },
        .explanation = text,
        .constraint = if (evidenceDefect(diagnostic.reason)) keep_grade else null,
        .instruction = instruction,
    }, .{ .emit_null_optional_fields = false }) catch return error.OutOfMemory;
}

pub fn evidence(a: std.mem.Allocator, rejected: []const u8) c.Error![]const u8 {
    return std.json.Stringify.valueAlloc(a, .{ .rejected_response = rejected }, .{}) catch return error.OutOfMemory;
}

/// The protocol facts a retained grade depends on, bound into its hash.
pub fn protocol(a: std.mem.Allocator) std.mem.Allocator.Error!std.json.Value {
    var reasons: std.json.Array = .init(a);
    var explanations: std.json.ObjectMap = .empty;
    var evidence_defects: std.json.Array = .init(a);
    for (std.meta.tags(Reason)) |reason| if (explanation(reason)) |text| {
        try reasons.append(.{ .string = @tagName(reason) });
        try explanations.put(a, @tagName(reason), .{ .string = text });
        if (evidenceDefect(reason)) try evidence_defects.append(.{ .string = @tagName(reason) });
    };
    var object: std.json.ObjectMap = .empty;
    try object.put(a, "attempts", .{ .integer = attempts });
    try object.put(a, "instruction", .{ .string = instruction });
    try object.put(a, "preservation", .{ .string = "every readable unnamed result equal after canonical decoding; a named result keeps disposition and score for an evidence defect; unparseable JSON, a response without a top-level results array, or one with no decodable result has no readable result, and unreadable results are logged; a readable duplicate is final" });
    try object.put(a, "grade_pinned_for", .{ .array = evidence_defects });
    try object.put(a, "placement", .{ .string = "bedrock: guidance in the system blocks after the instruction, evidence as a user message after the documents; openai: guidance and evidence as user messages after the documents" });
    // The exact correction envelope, bound through fixed probes.
    var probes: std.json.Array = .init(a);
    for ([_]judgment.Diagnostic{
        .{ .reason = .missing_source_evidence, .criterion_id = "probe", .evidence_index = 0, .document_id = "probe" },
        .{ .reason = .invalid_shape },
    }) |probe| try probes.append(.{ .string = guidance(a, probe) catch return error.OutOfMemory });
    try probes.append(.{ .string = evidence(a, "probe") catch return error.OutOfMemory });
    try object.put(a, "probes", .{ .array = probes });
    try object.put(a, "correctable", .{ .array = reasons });
    try object.put(a, "explanations", .{ .object = explanations });
    return .{ .object = object };
}

/// Why a correction is checked by validation alone: the rejected response left
/// no readable result to preserve (user decision, 18 October 2026). Every such
/// correction records its reason in the report.
pub const Unconstrained = enum {
    unparseable_json,
    no_results_array,
    no_readable_result,
    some_results_unreadable,

    pub fn explanation(self: Unconstrained) []const u8 {
        return switch (self) {
            .unparseable_json => "the rejected response was not valid JSON, so no result could be preserved",
            .no_results_array => "the rejected response had no top-level results array, so no result could be preserved",
            .no_readable_result => "no result in the rejected response decoded on its own, so none could be preserved",
            .some_results_unreadable => "some results in the rejected response did not decode on their own, so only the readable ones were preserved",
        };
    }
};

/// A correction may change only what its diagnostic named. Every other result
/// the rejected response made readable must be returned equal after canonical
/// decoding, so a correction cannot raise unaffected scores; an evidence defect
/// also keeps the named result's disposition and score. With no readable result
/// the complete corrected judgment is still validated (`Unconstrained`).
pub fn preserved(a: std.mem.Allocator, correction: Correction, corrected: []const u8) c.Error!?judgment.Diagnostic {
    // judgment.validate has already decoded the corrected response.
    const after = c.decode(judgment.Proposal, a, corrected) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidEvaluationContract;
    const before = (try readable(a, correction.rejected)).results;
    for (before, 0..) |prior, index| {
        if (named(judgment.RawResult, before[0..index], prior.criterion_id) != null) continue;
        const current = named(judgment.CriterionResult, after.results, prior.criterion_id) orelse continue;
        const changed: judgment.Diagnostic = .{ .reason = .changed_criterion, .criterion_id = prior.criterion_id };
        if (correction.diagnostic.criterion_id) |affected| if (std.mem.eql(u8, affected, prior.criterion_id)) {
            const current_score: ?i64 = if (current.score) |score| score else null;
            if (evidenceDefect(correction.diagnostic.reason) and (prior.disposition != current.disposition or prior.score != current_score)) return changed;
            continue;
        };
        const left = std.json.Stringify.valueAlloc(a, prior, .{}) catch return error.OutOfMemory;
        const right = std.json.Stringify.valueAlloc(a, current, .{}) catch return error.OutOfMemory;
        if (!std.mem.eql(u8, left, right)) return changed;
    }
    return null;
}

/// A readable duplicate behind a shape defect is judgment content: no correction
/// may choose between the judge's two results for one criterion.
pub fn blocked(a: std.mem.Allocator, rejected: []const u8) c.Error!?judgment.Diagnostic {
    return judgment.duplicate((try readable(a, rejected)).results);
}

/// Null when a correction of this rejected response preserves readable results.
pub fn unconstrained(a: std.mem.Allocator, rejected: []const u8) c.Error!?Unconstrained {
    return (try readable(a, rejected)).unconstrained;
}

const Readable = struct { results: []const judgment.RawResult, unconstrained: ?Unconstrained = null };

/// The results a rejected response made readable: all of them when it decodes,
/// otherwise each result that decodes on its own under a top-level `results`
/// array after a shape defect. Anything else has no readable result.
fn readable(a: std.mem.Allocator, bytes: []const u8) c.Error!Readable {
    if (c.decode(judgment.RawProposal, a, bytes)) |proposal| {
        return .{ .results = proposal.results, .unconstrained = if (proposal.results.len == 0) .no_readable_result else null };
    } else |err| if (err == error.OutOfMemory) return error.OutOfMemory;
    var tree = strict.parse(a, bytes, c.json_limits, false, null) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else .{ .results = &.{}, .unconstrained = .unparseable_json };
    defer tree.deinit();
    const results = if (tree.value == .object) tree.value.object.get("results") else null;
    if (results == null or results.? != .array) return .{ .results = &.{}, .unconstrained = .no_results_array };
    var decoded: std.ArrayList(judgment.RawResult) = .empty;
    errdefer decoded.deinit(a);
    for (results.?.array.items) |item| {
        const encoded = std.json.Stringify.valueAlloc(a, item, .{}) catch return error.OutOfMemory;
        const result = c.decode(judgment.RawResult, a, encoded) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            continue;
        };
        try decoded.append(a, result);
    }
    const skipped = results.?.array.items.len - decoded.items.len;
    const owned = try decoded.toOwnedSlice(a);
    return .{ .results = owned, .unconstrained = if (owned.len == 0) .no_readable_result else if (skipped != 0) .some_results_unreadable else null };
}

fn named(comptime Result: type, results: []const Result, id: []const u8) ?Result {
    for (results) |result| if (std.mem.eql(u8, result.criterion_id, id)) return result;
    return null;
}
