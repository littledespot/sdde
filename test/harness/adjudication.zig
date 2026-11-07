//! Pure adjudication of one immutable retained E2E report from a
//! `spec-adjudication-record/v1`. The original workflow report remains unchanged.
const std = @import("std");
const c = @import("contracts.zig");
const native = @import("e2e/contracts.zig");
const gate = @import("e2e/acceptance.zig");
const judgment = @import("judgment.zig");
const identity = @import("review_identity.zig");
const strict = @import("../../src/domain/strict_json.zig");

pub const Error = std.mem.Allocator.Error || error{InvalidAdjudication};
pub const Record = struct {
    schema: enum { @"spec-adjudication-record/v1" },
    reviewer: []const u8,
    reviewed_at_utc: []const u8,
    proposal: judgment.Proposal,
};
pub const Adjudication = struct {
    schema: enum { @"spec-adjudication/v3" } = .@"spec-adjudication/v3",
    reviewer: []const u8,
    reviewed_at_utc: []const u8,
    judgment: judgment.Result,
    acceptance: gate.Result,
};

/// All returned strings and judgments belong to the caller's arena.
pub fn evaluate(a: std.mem.Allocator, record_bytes: []const u8, original_report_bytes: []const u8) Error!Adjudication {
    const original = try parseOriginal(a, original_report_bytes);
    const record = c.decode(Record, a, record_bytes) catch |err| return invalid(err);
    if (!identity.validReviewer(record.reviewer) or !identity.validUtcTimestamp(record.reviewed_at_utc)) return error.InvalidAdjudication;
    // The capture is created at the production publication handoff, before any
    // adjudication. A capture supplied elsewhere cannot substitute it.
    const input = original.evaluation_inputs orelse return error.InvalidAdjudication;
    try validateCapture(a, input);
    const scored = judgment.validate(a, null, input, try std.json.Stringify.valueAlloc(a, record.proposal, .{})) catch |err| return invalid(err);
    return .{
        .reviewer = record.reviewer,
        .reviewed_at_utc = record.reviewed_at_utc,
        .judgment = scored,
        .acceptance = try gate.evaluateJudgment(a, original, scored),
    };
}

fn parseOriginal(a: std.mem.Allocator, bytes: []const u8) Error!native.Report {
    const limits: strict.Limits = .{ .maximum_depth = 128 };
    var tree = strict.parse(a, bytes, limits, false, null) catch |err| return invalid(err);
    defer tree.deinit();
    if (tree.value != .object or !tree.value.object.contains("schema") or !tree.value.object.contains("origin")) return error.InvalidAdjudication;
    const report = strict.decode(native.Report, a, bytes, limits) catch |err| return invalid(err);
    if (report.schema != .@"spec-e2e-report/v15" or report.origin != .live) return error.InvalidAdjudication;
    return report;
}

fn validateCapture(a: std.mem.Allocator, input: c.Capture) Error!void {
    c.validateCapture(input) catch |err| return invalid(err);
    const selected = c.parseCase(a, input.case_bytes) catch |err| return invalid(err);
    const rubric = c.parseRubric(a, input.rubric_bytes) catch |err| return invalid(err);
    if (!std.mem.eql(u8, try std.json.Stringify.valueAlloc(a, selected, .{}), try std.json.Stringify.valueAlloc(a, input.case, .{})) or
        !std.mem.eql(u8, try std.json.Stringify.valueAlloc(a, rubric, .{}), try std.json.Stringify.valueAlloc(a, input.rubric, .{}))) return error.InvalidAdjudication;
}

fn invalid(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidAdjudication;
}
