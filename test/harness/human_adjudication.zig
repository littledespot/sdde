//! Pure human adjudication of one immutable retained E2E report. The original
//! workflow and advisory model report remain unchanged.
const std = @import("std");
const c = @import("contracts.zig");
const native = @import("e2e/contracts.zig");
const gate = @import("e2e/acceptance.zig");
const judgment = @import("judgment.zig");
const identity = @import("review_identity.zig");
const strict = @import("../../src/domain/strict_json.zig");

pub const Error = std.mem.Allocator.Error || error{InvalidHumanAdjudication};
pub const Review = struct {
    schema: enum { @"human-spec-adjudication/v1" },
    outcome: union(enum) {
        pending,
        reviewed: struct {
            reviewer: []const u8,
            reviewed_at_utc: []const u8,
            report_sha256: []const u8,
            proposal: judgment.Proposal,
        },
    },
};
pub const Adjudication = struct {
    schema: enum { @"spec-adjudication/v1" } = .@"spec-adjudication/v1",
    original_report_sha256: []const u8,
    review_sha256: []const u8,
    reviewer: ?[]const u8,
    reviewed_at_utc: ?[]const u8,
    human_judgment: ?judgment.Result,
    acceptance: gate.Result,
};

/// All returned strings and judgments belong to the caller's arena. Only a
/// reviewed declaration can supply semantic acceptance; pending is unresolved.
pub fn evaluate(a: std.mem.Allocator, review_bytes: []const u8, original_report_bytes: []const u8) Error!Adjudication {
    const original = try parseOriginal(a, original_report_bytes);
    const review = c.decode(Review, a, review_bytes) catch |err| return invalid(err);
    const original_hash = try hash(a, original_report_bytes);
    var result: Adjudication = .{
        .original_report_sha256 = original_hash,
        .review_sha256 = try hash(a, review_bytes),
        .reviewer = null,
        .reviewed_at_utc = null,
        .human_judgment = null,
        .acceptance = try gate.evaluate(a, original),
    };
    const reviewed = switch (review.outcome) {
        .pending => return result,
        .reviewed => |reviewed| reviewed,
    };
    if (!identity.validReviewer(reviewed.reviewer) or !identity.validUtcTimestamp(reviewed.reviewed_at_utc) or
        !std.mem.eql(u8, reviewed.report_sha256, original_hash)) return error.InvalidHumanAdjudication;
    // The capture is created at the production publication handoff, before an
    // advisory provider call. A grader's returned capture cannot substitute it.
    const input = original.evaluation_inputs orelse return error.InvalidHumanAdjudication;
    try validateCapture(a, input);
    const human = judgment.validate(a, null, input, try std.json.Stringify.valueAlloc(a, reviewed.proposal, .{})) catch |err| return invalid(err);
    result.reviewer = reviewed.reviewer;
    result.reviewed_at_utc = reviewed.reviewed_at_utc;
    result.human_judgment = human;
    result.acceptance = try gate.evaluateHuman(a, original, human);
    return result;
}

fn parseOriginal(a: std.mem.Allocator, bytes: []const u8) Error!native.Report {
    const limits: strict.Limits = .{ .maximum_depth = 128 };
    var tree = strict.parse(a, bytes, limits, false, null) catch |err| return invalid(err);
    defer tree.deinit();
    if (tree.value != .object or !tree.value.object.contains("schema") or !tree.value.object.contains("origin")) return error.InvalidHumanAdjudication;
    const report = strict.decode(native.Report, a, bytes, limits) catch |err| return invalid(err);
    if (report.schema != .@"spec-e2e-report/v4" or report.origin != .live) return error.InvalidHumanAdjudication;
    return report;
}

fn validateCapture(a: std.mem.Allocator, input: c.Capture) Error!void {
    c.validateCapture(input) catch |err| return invalid(err);
    const selected = c.parseCase(a, input.case_bytes) catch |err| return invalid(err);
    const rubric = c.parseRubric(a, input.rubric_bytes) catch |err| return invalid(err);
    if (!std.mem.eql(u8, try std.json.Stringify.valueAlloc(a, selected, .{}), try std.json.Stringify.valueAlloc(a, input.case, .{})) or
        !std.mem.eql(u8, try std.json.Stringify.valueAlloc(a, rubric, .{}), try std.json.Stringify.valueAlloc(a, input.rubric, .{}))) return error.InvalidHumanAdjudication;
}

fn hash(a: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return a.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
}

fn invalid(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidHumanAdjudication;
}
