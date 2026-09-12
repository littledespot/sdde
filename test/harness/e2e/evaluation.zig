//! Join a successful publication to the independent rubric evaluator.
const std = @import("std");
const c = @import("contracts.zig");
const evaluator = @import("../contracts.zig");
const fixture = @import("fixture.zig");

pub fn inputs(allocator: std.mem.Allocator, report: c.Report, captured: fixture.Evaluation, specification: []const u8, execution_id: []const u8) !evaluator.Capture {
    if (report.status != .generated or report.workflow_outcome != .ok or report.publication_check != .passed or report.specification == null) return error.GenerationNotCompleted;
    const value: evaluator.Capture = .{
        .evaluation_id = try std.mem.concat(allocator, u8, &.{ "eval-", execution_id }),
        .case = captured.case,
        .case_bytes = captured.case_bytes,
        .rubric = captured.rubric,
        .rubric_bytes = captured.rubric_bytes,
        .sources = captured.sources,
        .specification = specification,
        .generation = .{
            .origin = .live_generation,
            .workflow_status = .completed,
            .execution_id = execution_id,
            .models = report.models,
        },
    };
    try evaluator.validateCapture(value);
    return value;
}

pub fn apply(report: *c.Report, result: @import("../report.zig").Report) void {
    report.evaluation = result;
    switch (result.outcome) {
        .evaluator_error => |failure| {
            report.status = .evaluator_failed;
            report.semantic_quality = .evaluator_error;
            report.diagnostic = @tagName(failure);
        },
        .evaluated => |judgment| {
            report.status = if (judgment.assessment == .scored) .evaluated else .quality_unresolved;
            report.semantic_quality = if (judgment.assessment == .scored) .scored else .unresolved;
        },
    }
}
