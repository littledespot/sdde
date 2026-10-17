//! Read-only development evidence for human qualification of a grader. Expected
//! specimen labels never enter the judge packet and never qualify a grader alone.
const std = @import("std");
const c = @import("contracts.zig");
const files = @import("files.zig");
const configuration = @import("configuration.zig");
const judgment = @import("judgment.zig");
const acceptance = @import("acceptance.zig");
const packet = @import("packet.zig");
const reports = @import("report.zig");
const review_identity = @import("review_identity.zig");

pub const Paths = c.GradingQualificationPaths;
pub const Error = std.mem.Allocator.Error || error{ InvalidGraderQualification, Cancelled };
pub const Expected = enum { passed, failed };
pub const Source = struct { id: []const u8, sha256: []const u8 };
pub const Specimen = struct { id: []const u8, path: []const u8, sha256: []const u8, expected: Expected };
pub const Panel = struct {
    schema: enum { @"grader-calibration-panel/v1" },
    case_id: []const u8,
    sources: []const Source,
    rubric_sha256: []const u8,
    specimens: []const Specimen,
};
pub const HumanReview = struct {
    schema: enum { @"grader-calibration-review/v1" },
    outcome: union(enum) {
        pending,
        reviewed: struct { reviewer: []const u8, reviewed_at_utc: []const u8, panel_sha256: []const u8 },
    },
};
pub const SpecimenReport = struct { id: []const u8, path: []const u8, sha256: []const u8 };
pub const Qualification = struct {
    schema: enum { @"grader-qualification/v1" },
    outcome: union(enum) {
        pending,
        qualified: struct {
            reviewer: []const u8,
            reviewed_at_utc: []const u8,
            panel_sha256: []const u8,
            review_sha256: []const u8,
            judge_config_sha256: []const u8,
            protocol_sha256: []const u8,
            reports: []const SpecimenReport,
        },
    },
};
pub const Proof = @import("grading_evidence.zig").Proof;
pub const Reason = @import("grading_evidence.zig").Reason;
pub const Evidence = @import("grading_evidence.zig").Evidence;

pub fn parsePanel(a: std.mem.Allocator, bytes: []const u8) Error!Panel {
    const value = try decode(Panel, a, bytes);
    if (!c.id(value.case_id) or value.sources.len == 0 or !digest(value.rubric_sha256)) return error.InvalidGraderQualification;
    for (value.sources, 0..) |source, index| {
        if (!c.id(source.id) or !digest(source.sha256)) return error.InvalidGraderQualification;
        for (value.sources[0..index]) |prior| if (std.mem.eql(u8, prior.id, source.id)) return error.InvalidGraderQualification;
    }
    var positive: usize = 0;
    var negative: usize = 0;
    for (value.specimens, 0..) |specimen, index| {
        if (!c.id(specimen.id) or !digest(specimen.sha256)) return error.InvalidGraderQualification;
        try path(specimen.path);
        for (value.specimens[0..index]) |prior| {
            if (std.mem.eql(u8, prior.id, specimen.id) or std.mem.eql(u8, prior.path, specimen.path)) return error.InvalidGraderQualification;
        }
        switch (specimen.expected) {
            .passed => positive += 1,
            .failed => negative += 1,
        }
    }
    if (positive < 2 or negative == 0) return error.InvalidGraderQualification;
    return value;
}

pub fn parseReview(a: std.mem.Allocator, bytes: []const u8) Error!HumanReview {
    const value = try decode(HumanReview, a, bytes);
    switch (value.outcome) {
        .pending => {},
        .reviewed => |review| if (!review_identity.validReviewer(review.reviewer) or !review_identity.validUtcTimestamp(review.reviewed_at_utc) or !digest(review.panel_sha256)) return error.InvalidGraderQualification,
    }
    return value;
}

pub fn parseQualification(a: std.mem.Allocator, bytes: []const u8) Error!Qualification {
    const value = try decode(Qualification, a, bytes);
    switch (value.outcome) {
        .pending => {},
        .qualified => |qualified| {
            if (!review_identity.validReviewer(qualified.reviewer) or !review_identity.validUtcTimestamp(qualified.reviewed_at_utc) or
                !digest(qualified.panel_sha256) or !digest(qualified.review_sha256) or
                !digest(qualified.judge_config_sha256) or !digest(qualified.protocol_sha256) or qualified.reports.len == 0) return error.InvalidGraderQualification;
            for (qualified.reports, 0..) |report, index| {
                if (!c.id(report.id) or !digest(report.sha256)) return error.InvalidGraderQualification;
                try path(report.path);
                for (qualified.reports[0..index]) |prior| {
                    if (std.mem.eql(u8, prior.id, report.id) or std.mem.eql(u8, prior.path, report.path)) return error.InvalidGraderQualification;
                }
            }
        },
    }
    return value;
}

/// All bytes are read through the shared safe capture adapter. An unavailable or
/// obsolete proof remains unresolved; malformed declarations fail closed.
pub fn inspect(io: std.Io, a: std.mem.Allocator, root: std.Io.Dir, paths: Paths, selected: c.Case, rubric_bytes: []const u8, sources: []const c.Document, judge_config: configuration.Config) Error!Evidence {
    try validatePaths(paths);
    _ = c.parseCase(a, try std.json.Stringify.valueAlloc(a, selected, .{})) catch |err| return invalid(err);
    if (!try sameJson(a, paths, selected.grading_qualification)) return error.InvalidGraderQualification;
    const rubric = c.parseRubric(a, rubric_bytes) catch |err| return invalid(err);
    configuration.validate(judge_config) catch |err| return invalid(err);
    const panel_bytes = (try read(io, a, root, paths.panel)) orelse return .{ .unresolved = .panel_missing };
    const panel = try parsePanel(a, panel_bytes);
    if (!std.mem.eql(u8, panel.case_id, selected.id) or !sameHash(rubric_bytes, panel.rubric_sha256) or
        panel.sources.len != sources.len or sources.len != selected.sources.len) return .{ .unresolved = .panel_stale };
    for (sources, selected.sources) |source, declared| {
        if (!std.mem.eql(u8, source.id, declared.id) or !c.text(source.text)) return error.InvalidGraderQualification;
        const bound = for (panel.sources) |candidate| {
            if (std.mem.eql(u8, source.id, candidate.id)) break candidate;
        } else return .{ .unresolved = .panel_stale };
        if (!sameHash(source.text, bound.sha256)) return .{ .unresolved = .panel_stale };
    }
    // Check every specimen even while review is pending. A proposed panel cannot
    // silently refer to changed bytes or nonexistent examples.
    const specimens = try a.alloc([]const u8, panel.specimens.len);
    for (panel.specimens, specimens) |specimen, *bytes| {
        bytes.* = (try read(io, a, root, specimen.path)) orelse return .{ .unresolved = .specimen_missing };
        if (!sameHash(bytes.*, specimen.sha256)) return .{ .unresolved = .specimen_stale };
        if (!c.text(bytes.*)) return error.InvalidGraderQualification;
    }
    const review_bytes = (try read(io, a, root, paths.review)) orelse return .{ .unresolved = .review_missing };
    const review = try parseReview(a, review_bytes);
    switch (review.outcome) {
        .pending => return .{ .unresolved = .review_pending },
        .reviewed => |approved| if (!sameHash(panel_bytes, approved.panel_sha256)) return .{ .unresolved = .review_stale },
    }
    const qualification_bytes = (try read(io, a, root, paths.qualification)) orelse return .{ .unresolved = .qualification_missing };
    const qualification = try parseQualification(a, qualification_bytes);
    const approved = switch (qualification.outcome) {
        .pending => return .{ .unresolved = .qualification_pending },
        .qualified => |approved| approved,
    };
    if (!sameHash(panel_bytes, approved.panel_sha256) or !sameHash(review_bytes, approved.review_sha256) or
        !std.mem.eql(u8, try configSha256(a, judge_config), approved.judge_config_sha256) or
        !std.mem.eql(u8, try protocolSha256(a), approved.protocol_sha256)) return .{ .unresolved = .qualification_stale };
    if (approved.reports.len != panel.specimens.len) return error.InvalidGraderQualification;
    for (approved.reports) |record| {
        const index = for (panel.specimens, 0..) |specimen, index| {
            if (std.mem.eql(u8, specimen.id, record.id)) break index;
        } else return error.InvalidGraderQualification;
        const bytes = (try read(io, a, root, record.path)) orelse return .{ .unresolved = .report_missing };
        if (!sameHash(bytes, record.sha256)) return .{ .unresolved = .report_stale };
        const report = reports.parse(a, bytes) catch |err| return invalid(err);
        if (!try matches(a, report, selected, rubric, rubric_bytes, sources, specimens[index], judge_config)) return .{ .unresolved = .report_mismatch };
        const native = judgment.validate(a, null, report.capture, try std.json.Stringify.valueAlloc(a, judgment.Proposal{ .results = report.outcome.evaluated.results }, .{})) catch |err| return invalid(err);
        if (!try sameJson(a, native, report.outcome.evaluated)) return .{ .unresolved = .report_mismatch };
        // Qualification requires complete judgments even for a specimen whose
        // known critical failure would already reject production acceptance.
        if (native.assessment != .scored) return .{ .unresolved = .report_unresolved };
        const quality = acceptance.quality(rubric, native);
        switch (quality) {
            .unresolved => return .{ .unresolved = .report_unresolved },
            .passed => if (panel.specimens[index].expected != .passed) return .{ .unresolved = .verdict_mismatch },
            .failed => if (panel.specimens[index].expected != .failed) return .{ .unresolved = .verdict_mismatch },
        }
    }
    return .{ .qualified = .{
        .panel_sha256 = try sha256(a, panel_bytes),
        .review_sha256 = try sha256(a, review_bytes),
        .qualification_sha256 = try sha256(a, qualification_bytes),
        .judge_config_sha256 = try configSha256(a, judge_config),
        .protocol_sha256 = try protocolSha256(a),
    } };
}

pub fn sha256(a: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]const u8 {
    var hashed: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hashed, .{});
    return a.dupe(u8, &std.fmt.bytesToHex(hashed, .lower));
}

pub fn configSha256(a: std.mem.Allocator, config: configuration.Config) std.mem.Allocator.Error![]const u8 {
    return sha256(a, try std.json.Stringify.valueAlloc(a, config, .{}));
}

pub fn protocolSha256(a: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
    return packet.protocolSha256(a);
}

fn matches(a: std.mem.Allocator, report: reports.Report, selected: c.Case, rubric: c.Rubric, rubric_bytes: []const u8, sources: []const c.Document, specimen: []const u8, config: configuration.Config) Error!bool {
    if (!std.mem.eql(u8, report.schema, "evaluation-report/v3") or !std.mem.eql(u8, report.prompt_revision, packet.revision) or
        !std.mem.eql(u8, report.judgment_schema, judgment.schema_revision) or report.outcome != .evaluated or
        report.judgment_diagnostic != null or report.capture.generation.origin != .supplied) return false;
    const protocol_sha256 = report.protocol_sha256 orelse return false;
    if (!std.mem.eql(u8, protocol_sha256, try protocolSha256(a))) return false;
    c.validateCapture(report.capture) catch |err| return invalid(err);
    const original_case = c.parseCase(a, report.capture.case_bytes) catch |err| return invalid(err);
    const original_rubric = c.parseRubric(a, report.capture.rubric_bytes) catch |err| return invalid(err);
    if (!try sameJson(a, original_case, selected) or !try sameJson(a, report.capture.case, selected) or
        !try sameJson(a, original_rubric, rubric) or !try sameJson(a, report.capture.rubric, rubric) or
        !std.mem.eql(u8, report.capture.rubric_bytes, rubric_bytes) or !std.mem.eql(u8, report.capture.specification, specimen) or
        !try sameJson(a, report.capture.sources, sources) or !try sameJson(a, report.configuration, config)) return false;
    configuration.validate(report.configuration) catch |err| return invalid(err);
    if (report.attempts.len == 0 or report.attempts.len > @as(usize, config.retry_limit) + 1) return false;
    var total: u128 = 0;
    for (report.attempts, 0..) |attempt, index| {
        if (attempt.ordinal != index + 1) return false;
        if (attempt.request_id) |id| if (!c.id(id)) return error.InvalidGraderQualification;
        const usage = attempt.usage orelse return false;
        if (reports.Usage.init(usage.input_tokens, usage.output_tokens, usage.total_tokens) == null) return error.InvalidGraderQualification;
        total += usage.total_tokens;
        if (attempt.failure) |failure| {
            if (index + 1 == report.attempts.len or (failure != .provider_failed and failure != .rate_limited)) return false;
            if (attempt.identity != .unavailable and !attempt.identity.validFor(config)) return false;
        } else if (index + 1 != report.attempts.len or !attempt.identity.validFor(config)) return false;
    }
    return total <= config.total_token_budget;
}

fn validatePaths(paths: Paths) Error!void {
    const values = [_][]const u8{ paths.panel, paths.review, paths.qualification };
    for (values, 0..) |value, index| {
        try path(value);
        for (values[0..index]) |prior| if (std.mem.eql(u8, prior, value)) return error.InvalidGraderQualification;
    }
}

fn read(io: std.Io, a: std.mem.Allocator, root: std.Io.Dir, name: []const u8) Error!?[]const u8 {
    return files.read(io, a, root, name) catch |err| switch (err) {
        error.InputUnavailable => null,
        else => return invalid(err),
    };
}

fn path(value: []const u8) Error!void {
    c.path(value) catch return error.InvalidGraderQualification;
}

fn decode(comptime T: type, a: std.mem.Allocator, bytes: []const u8) Error!T {
    return c.decode(T, a, bytes) catch |err| return invalid(err);
}

fn sameJson(a: std.mem.Allocator, left: anytype, right: @TypeOf(left)) std.mem.Allocator.Error!bool {
    return std.mem.eql(u8, try std.json.Stringify.valueAlloc(a, left, .{}), try std.json.Stringify.valueAlloc(a, right, .{}));
}

fn invalid(err: anyerror) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.Cancelled => error.Cancelled,
        else => error.InvalidGraderQualification,
    };
}

fn digest(value: []const u8) bool {
    if (value.len != 64) return false;
    for (value) |byte| if (!std.ascii.isDigit(byte) and (byte < 'a' or byte > 'f')) return false;
    return true;
}

fn sameHash(bytes: []const u8, expected: []const u8) bool {
    var hashed: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hashed, .{});
    return std.mem.eql(u8, &std.fmt.bytesToHex(hashed, .lower), expected);
}
