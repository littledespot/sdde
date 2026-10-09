const std = @import("std");
const debug = @import("../../../src/domain/request_debugger.zig");

pub const Report = struct {
    schema: []const u8 = "call-diagnostic-report/v1",
    started_at_utc: []const u8,
    options: @import("options.zig").Options,
    parent_run: []const u8,
    parent_call: []const u8,
    original_binding: debug.Description,
    effective_binding: debug.Description,
    context_path: []const u8,
    request_path: []const u8,
    trials: []const @import("trial.zig").Trial = &.{},
    semantic_quality: enum { not_assessed } = .not_assessed,
    workflow: enum { not_run } = .not_run,
    publication: enum { not_run } = .not_run,
    rubric: enum { not_run } = .not_run,

    pub fn succeeded(self: Report) bool {
        if (self.trials.len != self.options.repeats) return false;
        for (self.trials) |trial| if (trial.outcome != .completed) return false;
        return true;
    }
};

/// Redact after provider JSON decoding, before either retained projection. The
/// Markdown renderer consumes the same sanitized data as the JSON report, so
/// Markdown escaping cannot obscure a credential from the redaction owner.
pub fn save(io: std.Io, allocator: std.mem.Allocator, output: @import("../e2e/report.zig").Output, report: Report, key: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try std.json.Stringify.valueAlloc(a, report, .{ .whitespace = .indent_2 });
    var sanitized = try @import("../../../src/domain/model_log_redaction.zig").sanitize(a, bytes, &.{key});
    defer sanitized.deinit(a);
    // This is the closed round trip of our typed projection. std.json.Value in
    // validation.parsed retains its arbitrary candidate shape as untrusted data.
    var safe = try std.json.parseFromSlice(Report, a, sanitized.bytes, .{
        .allocate = .alloc_always,
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = false,
        .max_value_len = sanitized.bytes.len,
    });
    defer safe.deinit();
    const rendered = try markdown(a, safe.value);
    try output.json.writeStreamingAll(io, sanitized.bytes);
    try output.json.sync(io);
    try output.markdown.writeStreamingAll(io, rendered);
    try output.markdown.sync(io);
}

pub fn markdown(a: std.mem.Allocator, report: Report) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(a);
    defer out.deinit();
    const w = &out.writer;
    const escape = @import("../report.zig").escape;
    try w.writeAll("# Captured call diagnostic\n\nWorkflow: ");
    try escape(w, report.options.workflow);
    try w.print("; captured call: {d}; step: ", .{report.options.call});
    try escape(w, report.effective_binding.request_step);
    try w.writeAll("\n\nModel: ");
    try escape(w, report.effective_binding.model);
    try w.writeAll("; reasoning: ");
    try escape(w, report.effective_binding.reasoning_effort orelse "none");
    try w.print("\n\nTrials recorded: {d}/{d}. Protocol checks: {s}.\n\n", .{ report.trials.len, report.options.repeats, if (report.succeeded()) "passed" else "failed or incomplete" });
    try w.writeAll("Semantic quality is not assessed. Workflow execution, publication and rubric evaluation did not run.\n\n");
    for (report.trials) |trial| {
        try w.print("## Trial {d}\n\nOutcome: {s}; elapsed: {d} ms", .{ trial.ordinal, @tagName(trial.outcome), @divTrunc(trial.elapsed_ns, std.time.ns_per_ms) });
        if (trial.status) |status| try w.print("; HTTP {d}", .{status});
        try w.print("\n\nExtraction: {s}; JSON: {s}; schema: {s}.\n\n", .{ @tagName(trial.validation.extraction), @tagName(trial.validation.json), @tagName(trial.validation.schema) });
        if (trial.validation.input_tokens) |tokens| try w.print("Input tokens: {d}. ", .{tokens});
        if (trial.validation.output_tokens) |tokens| try w.print("Output tokens: {d}. ", .{tokens});
        if (trial.diagnostic) |diagnostic| {
            try w.writeAll("Diagnostic: ");
            try escape(w, diagnostic);
        }
        try w.print("\n\n[Request](logs/debugger/{s}.request.json) · [Response](logs/debugger/{s}.response.json)\n\n", .{ trial.request_id, trial.request_id });
        if (trial.validation.model_text) |text| {
            try w.writeAll("Output (untrusted):\n\n");
            try escape(w, text);
            try w.writeAll("\n\n");
        }
    }
    return out.toOwnedSlice();
}
