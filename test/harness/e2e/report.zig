const std = @import("std");
const c = @import("contracts.zig");

pub const Output = struct {
    json: std.Io.File,
    markdown: std.Io.File,

    pub fn reserve(io: std.Io, dir: std.Io.Dir) !Output {
        const json = try dir.createFile(io, "report.json", .{ .exclusive = true, .permissions = .fromMode(0o600) });
        errdefer json.close(io);
        const markdown = try dir.createFile(io, "report.md", .{ .exclusive = true, .permissions = .fromMode(0o600) });
        return .{ .json = json, .markdown = markdown };
    }

    pub fn close(self: Output, io: std.Io) void {
        self.json.close(io);
        self.markdown.close(io);
    }

    pub fn save(self: Output, io: std.Io, allocator: std.mem.Allocator, report: c.Report) !void {
        const json = try @import("../../../src/domain/canonical_json.zig").encode(c.Report, allocator, report);
        try self.json.writeStreamingAll(io, json);
        try self.json.sync(io);
        try self.markdown.writeStreamingAll(io, try renderMarkdown(allocator, report));
        try self.markdown.sync(io);
    }
};

/// Terminal and Markdown share the same parser diagnostic projection.
pub fn terminal(allocator: std.mem.Allocator, report: c.Report, root: []const u8, run: []const u8) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writer.print("E2E result: {s}\n", .{@tagName(report.status)});
    const fields = [_]struct { label: []const u8, value: ?[]const u8 }{
        .{ .label = "Model step", .value = report.last_model_step },
        .{ .label = "Engine/harness error", .value = report.diagnostic },
        .{ .label = "Provider error", .value = report.provider_diagnostic },
        .{ .label = "Model validation error", .value = report.model_diagnostic },
        .{ .label = "Evidence capture error", .value = report.evidence_error },
    };
    for (fields) |field| if (field.value) |value| {
        try writer.print("{s}: ", .{field.label});
        // JSON escaping prevents model/config text from injecting terminal controls.
        try std.json.Stringify.value(value, .{}, writer);
        try writer.writeByte('\n');
    };
    if (report.candidate_error) |diagnostic| {
        try writeCandidateError(writer, diagnostic);
        try writer.writeAll("\n\n");
    }
    if (report.schema_error) |diagnostic| {
        try writer.writeAll("Schema validation: ");
        try std.json.Stringify.value(diagnostic, .{}, writer);
        try writer.writeAll("\n\n");
    }
    if (report.json_error) |diagnostic| {
        try writeJsonError(writer, diagnostic);
        try writer.writeByte('\n');
    }
    if (report.last_model_output) |path| try writer.print("Model output: {s}/{s}/{s}\n", .{ root, run, path });
    if (report.events_file) |path| try writer.print("Events: {s}/{s}/{s}\n", .{ root, run, path });
    try writer.print("Report: {s}/{s}/report.md\nDetails: {s}/{s}/report.json\n", .{ root, run, root, run });
    return out.toOwnedSlice();
}

fn writeCandidateError(writer: *std.Io.Writer, diagnostic: @import("../../../src/domain/candidate_validation_diagnostic.zig").Diagnostic) !void {
    try writer.writeAll("Candidate validation: ");
    try std.json.Stringify.value(diagnostic, .{}, writer);
}

fn writeJsonError(writer: *std.Io.Writer, diagnostic: @import("../../../src/domain/strict_json.zig").Diagnostic) !void {
    try writer.print("JSON error: {s}", .{@tagName(diagnostic.reason)});
    if (diagnostic.location) |position|
        try writer.print(" at line {d}, column {d} (byte offset {d})", .{ position.line, position.column, position.byte_offset });
}

/// Human view of the same structured report; it introduces no workflow verdict.
pub fn renderMarkdown(allocator: std.mem.Allocator, report: c.Report) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    const escape = @import("../report.zig").escape;
    try writer.print("# Spec E2E run\n\nResult: **{s}**\n\n{s}\n\n", .{ @tagName(report.status), explanation(report) });
    try writer.writeAll("Case: ");
    try escape(writer, report.case_id orelse "unavailable");
    try writer.writeAll("\n\nExecution: ");
    try escape(writer, report.execution_id orelse "unavailable");
    try writer.print("\n\nWorkflow outcome: {s}; publication: {s}; semantic quality: {s}.\n\n", .{
        if (report.workflow_outcome) |tag| @tagName(tag) else "not_run", @tagName(report.publication_check), @tagName(report.semantic_quality),
    });
    try writer.writeAll("Last model step: ");
    try escape(writer, report.last_model_step orelse "none");
    try writer.writeAll("\n\nEngine/harness diagnostic: ");
    try escape(writer, report.diagnostic orelse "none");
    try writer.writeAll("; provider: ");
    try escape(writer, report.provider_diagnostic orelse "none");
    try writer.writeAll("; model validation: ");
    try escape(writer, report.model_diagnostic orelse "none");
    try writer.writeAll(".\n\n");
    if (report.candidate_error) |diagnostic| {
        try writeCandidateError(writer, diagnostic);
        try writer.writeAll("\n\n");
    }
    if (report.schema_error) |diagnostic| {
        try writer.writeAll("Schema validation: ");
        try std.json.Stringify.value(diagnostic, .{}, writer);
        try writer.writeAll("\n\n");
    }
    if (report.json_error) |diagnostic| {
        try writeJsonError(writer, diagnostic);
        try writer.writeAll("\n\n");
    }
    if (report.last_model_output) |path| {
        try writer.print("Rejected or completed model output: [open text]({s}). This is untrusted diagnostic data.\n\n", .{path});
    }
    if (report.events_file) |path| try writer.print("Every step and validation result: [events]({s}).\n\n", .{path});
    if (report.evidence_root) |path| try writer.print("Model-call inputs and responses: [{s}/]({s}/).\n\n", .{ path, path });
    if (report.evidence_error) |reason| {
        try writer.writeAll("Evidence capture failed: ");
        try escape(writer, reason);
        try writer.writeAll(". This run has incomplete evidence.\n\n");
    }
    try writer.print("Model calls: {d}. Accounted tokens: {d}. Usage complete: {}.\n\n", .{ report.model_calls, report.total_tokens, report.usage_complete });
    if (report.last_model_usage) |usage| try writer.print("Last model call: {d} input + {d} output = {d} tokens.\n\n", .{ usage.input_tokens, usage.output_tokens, usage.total_tokens });
    for (report.models) |model| {
        try writer.writeAll("Generation slot ");
        try escape(writer, model.slot);
        try writer.writeAll(": ");
        try escape(writer, model.provider);
        try writer.writeAll(" / ");
        try escape(writer, model.model);
        try writer.writeAll("\n\n");
    }
    if (report.evaluation_configuration) |config| {
        try writer.writeAll("Judge: ");
        try escape(writer, config.model);
        if (config.region) |region| try writer.print(" in {s}", .{@tagName(region)});
        try writer.writeAll(".\n\n");
    }
    if (report.specification) |path| {
        try writer.writeAll("Published specification beneath project/: ");
        try escape(writer, path);
        try writer.writeAll("\n\n");
    }
    try writer.writeAll("## Evidence for workflow improvement\n\n" ++
        "Use the failure step and diagnostics to locate the failed workflow operation. " ++
        "case.json and inputs.json retain the selected case and captured configuration, workflow resources, references, rubric and evaluator settings. " ++
        "project/ contains the isolated inputs and any actual engine output. report.json provides the structured run record for automated comparisons.\n\n" ++
        "When grading completes, the criterion scores, explanations and source/specification quotations below identify coverage, grounding and clarity defects. " ++
        "Compare runs with the same source, rubric revision and model settings, and retain failures and low scores. " ++
        "The report does not automatically tune or approve the workflow.\n\n");
    if (report.evaluation) |evaluation| {
        try writer.writeAll(try @import("../report.zig").markdown(allocator, evaluation));
    } else {
        try writer.writeAll("No rubric grade is available. This run provides failure evidence only; it does not establish the quality of a generated specification.\n");
    }
    return out.toOwnedSlice();
}

fn explanation(report: c.Report) []const u8 {
    return switch (report.status) {
        .input_invalid => "Input setup failed before workflow execution. Check the diagnostic and captured inputs. Use scripts/e2e-spec.sh to load the checkout's .env.e2e; direct Zig invocations require the TEST_EVALUATION_* settings and test credential in their environment.",
        .harness_error => "The harness encountered an operational error. Any retained candidate or score does not make this a completed E2E run.",
        .bootstrap_failed => "The engine rejected project/workflow configuration before generation. Inspect the bootstrap diagnostic and captured project resources.",
        .workflow_failed => if (report.provider_diagnostic != null and std.mem.eql(u8, report.provider_diagnostic.?, "output_limit"))
            "The provider stopped generation at its output limit before returning a complete candidate. The engine sets no per-call output token limit; its token budget is cumulative across the workflow. The engine rejected partial output, so no published specification was available to grade. Inspect the model assignment, prompt and schema at the reported step; no harness retry or partial-output substitution was applied."
        else
            "The workflow did not complete. Inspect its outcome and separate provider/model diagnostics; a failed, cancelled or clarification-blocked invocation cannot supply a fresh specification for grading.",
        .publication_missing, .artifact_missing, .artifact_unreadable, .artifact_changed => "The invocation did not provide all expected, unchanged published artifacts. Inspect publication evidence and the retained project; file existence alone cannot establish success.",
        .fixture_changed => "Source inputs changed during execution. This run is not accepted as a stable E2E comparison; use the retained capture to inspect what was evaluated.",
        .generated => "The engine published its validated specification; rubric grading has not completed.",
        .evaluator_failed => "Generation completed, but the evaluator failed. The published specification remains available; this result has no quality grade.",
        .quality_unresolved => "Generation completed, but the judge could not resolve every required criterion. Inspect the criterion evidence and uncertainty below.",
        .passed => "Generation, publication checks and rubric scoring completed. Inspect the score and criterion findings below; a completed evaluation may still report poor quality.",
    };
}
