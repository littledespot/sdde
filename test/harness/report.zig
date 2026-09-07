//! Report projections. No filesystem, provider, or workflow capabilities.
const std = @import("std");
const c = @import("contracts.zig");
const j = @import("judgment.zig");
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
pub const Attempt = struct {
    ordinal: u32,
    request_id: ?[]const u8,
    response_id: ?[]const u8,
    actual_model: ?[]const u8,
    usage: ?Usage,
    failure: ?Failure,
};
pub const Outcome = union(enum) { evaluated: j.Result, evaluator_error: Failure };
pub const Report = struct {
    schema: []const u8 = "evaluation-report/v1",
    prompt_revision: []const u8 = @import("packet.zig").revision,
    judgment_schema: []const u8 = j.schema_revision,
    capture: c.Capture,
    configuration: @import("configuration.zig").Config,
    attempts: []const Attempt,
    outcome: Outcome,
};

pub fn json(allocator: std.mem.Allocator, report: Report) std.mem.Allocator.Error![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, report, .{ .whitespace = .indent_2 });
}
pub fn markdown(allocator: std.mem.Allocator, report: Report) std.mem.Allocator.Error![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    render(&out.writer, report) catch return error.OutOfMemory;
    return out.toOwnedSlice() catch return error.OutOfMemory;
}
fn render(out: *std.Io.Writer, report: Report) std.Io.Writer.Error!void {
    try out.writeAll("# Specification evaluation\n\nCase: ");
    try escape(out, report.capture.case.id);
    try out.writeAll("\n\nEvaluation: ");
    try escape(out, report.capture.evaluation_id);
    try out.print("\n\nArtifact origin: {s}; workflow: {s}\n\nRequested judge: ", .{ @tagName(report.capture.generation.origin), @tagName(report.capture.generation.workflow_status) });
    try escape(out, report.configuration.model);
    try out.writeAll("\n\nRubric: ");
    try escape(out, report.capture.rubric.id);
    try out.print(" (revision {d}; scale {d}–{d})\n\n", .{ report.capture.rubric.revision, report.capture.rubric.minimum_score, report.capture.rubric.maximum_score });
    for (report.attempts) |attempt| {
        try out.print("Attempt {d}: model ", .{attempt.ordinal});
        try escape(out, attempt.actual_model orelse "unavailable");
        try out.writeAll("; request ");
        try escape(out, attempt.request_id orelse "unavailable");
        try out.writeAll("; response ");
        try escape(out, attempt.response_id orelse "unavailable");
        if (attempt.usage) |usage| {
            try out.print("; tokens {d} input + {d} output = {d}", .{ usage.input_tokens, usage.output_tokens, usage.total_tokens });
        } else try out.writeAll("; usage unavailable");
        if (attempt.failure) |failure| try out.print("; {s}", .{@tagName(failure)});
        try out.writeAll("\n\n");
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
                try out.writeAll("\n\n");
                try escape(out, criterion.explanation);
                try out.writeAll("\n\n");
                for (criterion.evidence) |evidence| {
                    try out.writeAll("- ");
                    try escape(out, evidence.document_id);
                    try out.writeAll(": ");
                    try escape(out, evidence.quote);
                    try out.writeByte('\n');
                }
                if (criterion.missing_from_specification) try out.writeAll("\nThe judge reports missing specification content.\n");
                try out.writeByte('\n');
            }
        },
    }
    try out.writeAll("\nThis is a model-assisted assessment, not workflow approval or semantic proof.\n");
}
fn escape(out: *std.Io.Writer, bytes: []const u8) std.Io.Writer.Error!void {
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
