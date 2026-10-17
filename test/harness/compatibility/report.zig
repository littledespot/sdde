//! Compatibility reports are diagnostic artifacts, never workflow authority.
const std = @import("std");
const inspection = @import("inspection.zig");
const c = @import("../e2e/contracts.zig");

pub const Report = struct {
    schema: enum { @"provider-compatibility-report/v1" } = .@"provider-compatibility-report/v1",
    origin: enum { live, offline } = .live,
    started_at_utc: []const u8,
    case_source: []const u8,
    execution_id: []const u8,
    build: @FieldType(c.Report, "build") = null,
    status: enum { input_invalid, compatible, incompatible, inconclusive, harness_error } = .input_invalid,
    diagnostic: ?[]const u8 = null,
    maximum_physical_sends: u32 = 1,
    physical_sends: usize = 0,
    boundary: @import("../e2e/trace.zig").Trace.Boundary = .open,
    workflow_outcome: ?@import("../../../src/domain/workflow.zig").OutcomeTag = null,
    workflow_diagnostic: ?[]const u8 = null,
    terminal_rejection: ?c.TerminalRejection = null,
    total_accounted_tokens: u128 = 0,
    total_actual_tokens: ?u128 = 0,
    usage_complete: bool = true,
    inspection: inspection.Inspection = .{},
    authority: enum { none } = .none,
    semantic_quality: enum { not_assessed } = .not_assessed,
    publication: enum { not_authorized } = .not_authorized,
};

/// Native accounting facts stay distinct from unknown actual consumption.
pub fn applyExecution(report: *Report, probe: @import("../e2e/invoke.zig").Probe, workflow: c.Report) void {
    report.physical_sends = probe.physical_sends;
    report.boundary = probe.boundary;
    report.workflow_outcome = workflow.workflow_outcome;
    report.workflow_diagnostic = workflow.diagnostic;
    report.terminal_rejection = workflow.terminal_rejection;
    report.total_accounted_tokens = workflow.total_tokens;
    report.usage_complete = probe.physical_sends == 0 or workflow.usage_complete;
    report.total_actual_tokens = if (report.usage_complete) workflow.total_tokens else null;
}

pub fn render(a: std.mem.Allocator, report: Report) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(a);
    defer out.deinit();
    const w = &out.writer;
    try w.print("# Bedrock compatibility\n\nStatus: **{s}**. Physical sends: **{d}/{d}**.\n\nWorkflow outcome: `{s}`; boundary: `{s}`.\n\n", .{ @tagName(report.status), report.physical_sends, report.maximum_physical_sends, if (report.workflow_outcome) |value| @tagName(value) else "not_started", @tagName(report.boundary) });
    try w.writeAll("This is provider/schema compatibility evidence. Semantic quality is not assessed; the result grants no publication or workflow-completion authority.\n\n");
    if (report.build) |build| {
        try w.writeAll("Build revision: ");
        try std.json.Stringify.value(build.source.revision, .{}, w);
        try w.print("; modified: `{}`.\n\n", .{build.source.modified});
    }
    if (report.diagnostic orelse report.inspection.reason) |reason| {
        try w.writeAll("Diagnostic: ");
        try std.json.Stringify.value(reason, .{}, w);
        try w.writeAll("\n\n");
    }
    if (report.inspection.request_file) |path| try w.print("[Exact request]({s})\n\n", .{path});
    if (report.inspection.response_file) |path| try w.print("[Exact response]({s})\n\n", .{path});
    try w.writeAll("Settings, identity, stop, usage and supplied reasoning are retained in report.json:\n\n```json\n");
    // JSON escaping keeps untrusted diagnostic text inert in the Markdown view.
    try std.json.Stringify.value(.{ .description = report.inspection.description, .identity = report.inspection.request_identity, .reported_stop = report.inspection.reported_stop, .candidate_diagnostic = report.inspection.candidate_diagnostic, .usage = report.inspection.usage, .validation = report.inspection.validation }, .{ .whitespace = .indent_2 }, w);
    try w.writeAll("\n```\n");
    return out.toOwnedSlice();
}

pub fn save(io: std.Io, a: std.mem.Allocator, output: @import("../e2e/report.zig").Output, report: Report) !void {
    const markdown = try render(a, report);
    defer a.free(markdown);
    const json = try std.json.Stringify.valueAlloc(a, report, .{ .whitespace = .indent_2 });
    defer a.free(json);
    try output.markdown.writeStreamingAll(io, markdown);
    try output.markdown.sync(io);
    try output.json.writeStreamingAll(io, json);
    try output.json.sync(io);
}
