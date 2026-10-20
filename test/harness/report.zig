//! Report projections. No filesystem, provider, or workflow capabilities.
const std = @import("std");
const c = @import("contracts.zig");
const j = @import("judgment.zig");
const gate = @import("acceptance_gate.zig");
pub const Failure = enum {
    authentication,
    configuration,
    rate_limited,
    timeout,
    cancelled,
    provider_failed,
    refused,
    incomplete,
    invalid_response,
    invalid_judgment,
    budget_exceeded,
    usage_unavailable,
    retries_exhausted,
};
pub const Usage = @import("../../src/domain/llm_provider_operation.zig").ProviderUsage;
/// `purpose` names the request sent: the original judgment request or its one
/// correction. A transient retry resends the same request. `diagnostic` is the
/// typed rejection of that attempt's judgment, when it had one. `unconstrained`
/// logs why a correction is checked by validation alone.
pub const Attempt = struct {
    ordinal: u32,
    purpose: enum { judgment, correction },
    request_id: ?[]const u8,
    identity: @import("provider.zig").Identity,
    usage: ?Usage,
    failure: ?Failure,
    diagnostic: ?j.Diagnostic = null,
    unconstrained: ?@import("correction.zig").Unconstrained = null,
};
pub const Outcome = union(enum) { evaluated: j.Result, evaluator_error: Failure };
pub const schema_version = "evaluation-report/v7";
pub const Report = struct {
    schema: []const u8 = schema_version,
    prompt_revision: []const u8 = @import("packet.zig").revision,
    judgment_schema: []const u8 = j.schema_revision,
    capture: c.Capture,
    configuration: @import("configuration.zig").Config,
    attempts: []const Attempt,
    outcome: Outcome,
    acceptance: gate.Evidence = .{},
    grader_qualification: ?@import("grading_evidence.zig").Evidence = null,
    protocol_sha256: ?[]const u8 = null,
};

/// Persisted reports carry their exact protocol and acceptance identities.
/// Construction defaults never stand in for omitted external evidence.
pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) c.Error!Report {
    var tree = @import("../../src/domain/strict_json.zig").parse(allocator, bytes, c.json_limits, false, null) catch |err| {
        return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidEvaluationContract;
    };
    defer tree.deinit();
    if (tree.value != .object) return error.InvalidEvaluationContract;
    for ([_][]const u8{ "schema", "prompt_revision", "judgment_schema", "protocol_sha256", "acceptance", "grader_qualification" }) |key| {
        if (!tree.value.object.contains(key)) return error.InvalidEvaluationContract;
    }
    const value = try c.decode(Report, allocator, bytes);
    if (!std.mem.eql(u8, value.schema, schema_version) or
        !std.mem.eql(u8, value.prompt_revision, @import("packet.zig").revision) or
        !std.mem.eql(u8, value.judgment_schema, j.schema_revision)) return error.InvalidEvaluationContract;
    if (value.protocol_sha256) |digest| {
        if (digest.len != 64) return error.InvalidEvaluationContract;
        for (digest) |byte| {
            if (!(byte >= '0' and byte <= '9') and !(byte >= 'a' and byte <= 'f')) return error.InvalidEvaluationContract;
        }
    }
    try validateAttempts(value.attempts, value.outcome, value.configuration);
    // A persisted judgment must still resolve against its own captured documents
    // and reproduce its recorded arithmetic; every reader inherits this check.
    if (value.outcome == .evaluated) {
        const evaluated = value.outcome.evaluated;
        const native = try j.validate(allocator, null, value.capture, std.json.Stringify.valueAlloc(allocator, j.Proposal{ .results = evaluated.results }, .{}) catch return error.OutOfMemory);
        const recorded = std.json.Stringify.valueAlloc(allocator, evaluated, .{}) catch return error.OutOfMemory;
        const expected = std.json.Stringify.valueAlloc(allocator, native, .{}) catch return error.OutOfMemory;
        if (!std.mem.eql(u8, recorded, expected)) return error.InvalidEvaluationContract;
    }
    return value;
}

/// The closed attempt policy. A transient provider failure with known usage
/// resends the same request, within `retry_limit`; a correctable invalid
/// judgment is followed only by its correction, up to the hashed correction
/// limit, whose `unconstrained` log matches the defect; every other attempt is
/// final. The outcome is the final attempt's, or a stop the attempts justify.
pub fn validateAttempts(attempts: []const Attempt, outcome: Outcome, config: @import("configuration.zig").Config) c.Error!void {
    const correction = @import("correction.zig");
    var retries: usize = 0;
    var corrections: usize = 0;
    var total: u128 = 0;
    for (attempts, 0..) |attempt, index| {
        if (attempt.ordinal != index + 1) return error.InvalidEvaluationContract;
        if (attempt.usage) |usage| total += usage.total_tokens;
        if (attempt.failure) |failure| switch (failure) {
            // Evaluator outcomes, never one attempt's observation.
            .budget_exceeded, .retries_exhausted => return error.InvalidEvaluationContract,
            else => {},
        };
        if ((attempt.diagnostic != null) != (attempt.failure == .invalid_judgment)) return error.InvalidEvaluationContract;
        if (attempt.diagnostic) |diagnostic| if (diagnostic.reason == .changed_criterion and attempt.purpose != .correction) return error.InvalidEvaluationContract;
        if (attempt.unconstrained != null and attempt.purpose != .correction) return error.InvalidEvaluationContract;
        if (index == 0) {
            if (attempt.purpose != .judgment) return error.InvalidEvaluationContract;
            continue;
        }
        const prior = attempts[index - 1];
        switch (prior.failure orelse return error.InvalidEvaluationContract) {
            .provider_failed, .rate_limited => {
                if (attempt.purpose != prior.purpose or prior.usage == null or attempt.unconstrained != prior.unconstrained) return error.InvalidEvaluationContract;
                retries += 1;
            },
            .invalid_judgment => {
                const defect = prior.diagnostic.?.reason;
                if (attempt.purpose != .correction or corrections == correction.attempts or prior.usage == null or !correction.correctable(defect)) return error.InvalidEvaluationContract;
                // The log follows from the defect's class: unparseable JSON always,
                // a decoded response only when it held no result.
                const logged = switch (defect) {
                    .json => attempt.unconstrained == .unparseable_json,
                    .invalid_shape => attempt.unconstrained != .unparseable_json,
                    .criterion_count => attempt.unconstrained == null or attempt.unconstrained == .no_readable_result,
                    else => attempt.unconstrained == null,
                };
                if (!logged) return error.InvalidEvaluationContract;
                corrections += 1;
            },
            else => return error.InvalidEvaluationContract,
        }
    }
    if (retries > config.retry_limit) return error.InvalidEvaluationContract;
    const last: ?Attempt = if (attempts.len == 0) null else attempts[attempts.len - 1];
    // A judgment, valid or not, is validated only with actual usage.
    if (last) |final| if ((final.failure == null or final.failure == .invalid_judgment) and final.usage == null) return error.InvalidEvaluationContract;
    // A metered transient failure is retried, and a correctable defect with a
    // correction remaining is corrected, unless the budget or cancellation stops it.
    const retry_pending = if (last) |final| (final.failure == .provider_failed or final.failure == .rate_limited) and final.usage != null else false;
    const correction_pending = if (last) |final| final.failure == .invalid_judgment and corrections < correction.attempts and
        correction.correctable(final.diagnostic.?.reason) else false;
    const exhausted = total > config.total_token_budget or (total >= config.total_token_budget and (retry_pending or correction_pending));
    switch (outcome) {
        .evaluated => if (last == null or last.?.failure != null or total > config.total_token_budget) return error.InvalidEvaluationContract,
        .evaluator_error => |failure| switch (failure) {
            .authentication, .configuration, .rate_limited, .timeout, .provider_failed, .refused, .incomplete, .invalid_response, .invalid_judgment, .usage_unavailable => {
                if (last == null or last.?.failure != failure or retry_pending or correction_pending or exhausted) return error.InvalidEvaluationContract;
            },
            .retries_exhausted => if (!retry_pending or retries != config.retry_limit or exhausted) return error.InvalidEvaluationContract,
            .budget_exceeded => if (!exhausted) return error.InvalidEvaluationContract,
            .cancelled => if (exhausted or (last != null and last.?.failure != .cancelled and !retry_pending and !correction_pending)) return error.InvalidEvaluationContract,
        },
    }
}

pub fn json(allocator: std.mem.Allocator, report: Report) std.mem.Allocator.Error![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, report, .{ .whitespace = .indent_2 });
}
pub fn markdown(allocator: std.mem.Allocator, report: Report) c.Error![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    render(&out.writer, report) catch |err| return if (err == error.InvalidEvaluationContract) error.InvalidEvaluationContract else error.OutOfMemory;
    return out.toOwnedSlice() catch return error.OutOfMemory;
}
fn render(out: *std.Io.Writer, report: Report) (std.Io.Writer.Error || c.Error)!void {
    try out.writeAll("# Specification evaluation\n\nCase: ");
    try escape(out, report.capture.case.id);
    try out.writeAll("\n\nEvaluation: ");
    try escape(out, report.capture.evaluation_id);
    try out.print("\n\nArtifact origin: {s}; workflow: {s}\n\nRequested judge: ", .{ @tagName(report.capture.generation.origin), @tagName(report.capture.generation.workflow_status) });
    try escape(out, report.configuration.model);
    try out.writeAll("\n\nRubric: ");
    try escape(out, report.capture.rubric.id);
    try out.print(" (revision {d}; scale {d}–{d})\n\n", .{ report.capture.rubric.revision, report.capture.rubric.minimum_score, report.capture.rubric.maximum_score });
    try out.print("Development acceptance: unresolved ({s})\n\nJudge qualification: {s}\n\n", .{ @tagName(report.acceptance.decision), @tagName(report.acceptance.qualification) });
    if (report.grader_qualification) |evidence| switch (evidence) {
        .unresolved => |reason| try out.print("Grader qualification evidence: unresolved ({s})\n\n", .{@tagName(reason)}),
        .qualified => |proof| {
            try out.writeAll("Grader qualification evidence: qualified\n\n");
            inline for (@typeInfo(@TypeOf(proof)).@"struct".fields) |field| {
                try out.print("- {s}: ", .{field.name});
                try escape(out, @field(proof, field.name));
                try out.writeByte('\n');
            }
            try out.writeByte('\n');
        },
    };
    for (report.attempts) |attempt| {
        try out.print("Attempt {d} ({s}): ", .{ attempt.ordinal, @tagName(attempt.purpose) });
        switch (attempt.identity) {
            .unavailable => try out.writeAll("provider identity unavailable"),
            .openai_response => |value| {
                try out.writeAll("reported model ");
                try escape(out, value.actual_model);
            },
            .bedrock_target => |value| {
                try out.writeAll("requested Bedrock target ");
                try escape(out, value.model);
                try out.print(" in {s}; model identity not echoed by API", .{@tagName(value.region)});
            },
        }
        try out.writeAll("; request ");
        try escape(out, attempt.request_id orelse "unavailable");
        switch (attempt.identity) {
            .openai_response => |value| {
                try out.writeAll("; response ");
                try escape(out, value.response_id);
            },
            .bedrock_target, .unavailable => {},
        }
        if (attempt.usage) |usage| {
            try out.print("; tokens {d} input + {d} output = {d}", .{ usage.input_tokens, usage.output_tokens, usage.total_tokens });
        } else try out.writeAll("; usage unavailable");
        if (attempt.failure) |failure| try out.print("; {s}", .{@tagName(failure)});
        try out.writeAll("\n\n");
        if (attempt.unconstrained) |reason| try out.print("Correction checked by validation alone: {s}.\n\n", .{reason.explanation()});
        if (attempt.diagnostic) |diagnostic| {
            try out.print("Judgment diagnostic: {s}", .{@tagName(diagnostic.reason)});
            if (diagnostic.criterion_id) |id| {
                try out.writeAll("; criterion ");
                try escape(out, id);
            }
            if (diagnostic.evidence_index) |index| try out.print("; evidence index {d}", .{index});
            if (diagnostic.document_id) |id| {
                try out.writeAll("; document ");
                try escape(out, id);
            }
            if (diagnostic.json) |detail| {
                try out.print("; {s}", .{@tagName(detail.reason)});
                if (detail.location) |location| try out.print(" at byte {d}, line {d}, column {d}", .{ location.byte_offset, location.line, location.column });
                try out.writeAll(". ");
                try out.writeAll(detail.explanation());
            }
            try out.writeAll("\n\n");
        }
    }
    switch (report.outcome) {
        .evaluator_error => |failure| try out.print("Evaluator error: {s}. No quality score.\n", .{@tagName(failure)}),
        .evaluated => |result| {
            try out.print("Assessment: {s}; threshold: {s}\n\n", .{ @tagName(result.assessment), @tagName(result.threshold) });
            if (result.score_percent) |score| try out.print("Score: {d:.2}%\n\n", .{score});
            for (result.results) |criterion| {
                try out.writeAll("## ");
                try escape(out, criterion.criterion_id);
                try out.print("\n\n{s}", .{@tagName(criterion.disposition)});
                if (criterion.score) |score| try out.print(": {d}", .{score});
                for (report.capture.rubric.criteria) |definition| {
                    if (std.mem.eql(u8, definition.id, criterion.criterion_id)) {
                        if (definition.minimum_acceptable_score) |minimum| try out.print("; critical minimum: {d}", .{minimum});
                        break;
                    }
                }
                try out.writeAll("\n\n");
                try escape(out, criterion.explanation);
                try out.writeAll("\n\n");
                // Locators resolve to the exact captured lines; an unresolvable
                // locator is an invalid report, never a rendered placeholder.
                for (criterion.evidence) |evidence| {
                    const text = j.documentText(report.capture, evidence.document_id) orelse return error.InvalidEvaluationContract;
                    const cited = (try j.lineSpan(text, evidence.first_line, evidence.last_line)) orelse return error.InvalidEvaluationContract;
                    try out.writeAll("- ");
                    try escape(out, evidence.document_id);
                    try out.print(" lines {d}-{d}: ", .{ evidence.first_line, evidence.last_line });
                    try escape(out, cited);
                    try out.writeByte('\n');
                }
                if (criterion.missing_from_specification) try out.writeAll("\nThe judge reports missing specification content.\n");
                try out.writeByte('\n');
            }
        },
    }
    try out.writeAll("\nThis is a model-assisted assessment, not workflow approval or semantic proof.\n");
}
pub fn escape(out: *std.Io.Writer, bytes: []const u8) std.Io.Writer.Error!void {
    for (bytes) |b| switch (b) {
        '<' => try out.writeAll("&lt;"),
        '>' => try out.writeAll("&gt;"),
        '&' => try out.writeAll("&amp;"),
        '\\', '`', '*', '_', '[', ']', '#', '|', '!' => {
            try out.writeByte('\\');
            try out.writeByte(b);
        },
        0...31, 127 => try out.writeByte(' '),
        else => try out.writeByte(b),
    };
}
