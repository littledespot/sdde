//! Development acceptance joins native outcomes and mechanical publication
//! evidence. Humans own semantic acceptance; no model grades an E2E run.
const std = @import("std");
const c = @import("contracts.zig");
const grading = @import("../contracts.zig");
const judgment = @import("../judgment.zig");
const admission = @import("../baseline/admission.zig");
const quality_policy = @import("../acceptance.zig");
const relative = @import("../../../src/domain/relative_directory_path.zig");

pub const Failure = enum {
    unexpected_outcome,
    native_workflow_failed,
    harness_failed,
    publication_failed,
    artifact_failed,
    admission_escape,
    admission_evidence_invalid,
    critical_failed,
    threshold_failed,
    grading_mismatch,
};
pub const Reason = enum {
    not_evaluated,
    missing_expected_outcome,
    missing_admission_evidence,
    missing_grading_evidence,
    grading_unresolved,
    invalid_clarifications,
    human_adjudication_required,
};
pub const Result = union(enum) { passed, failed: Failure, unresolved: Reason };
pub const Error = std.mem.Allocator.Error;

/// A completed publication remains unresolved until source-bound human review.
/// Stored acceptance and status names never substitute for native evidence.
pub fn evaluate(a: std.mem.Allocator, report: c.Report) Error!Result {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const native = try mechanical(scratch.allocator(), report);
    if (native != .passed) return native;
    if (report.expected_outcome == .publication) return .{ .unresolved = .human_adjudication_required };
    return .passed;
}

/// The human-review adapter owns reviewer/date/hash attestation. This boundary
/// still checks native publication and revalidates the supplied human judgment
/// against the exact captured source and published specification.
pub fn evaluateHuman(a: std.mem.Allocator, report: c.Report, human_result: judgment.Result) Error!Result {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const allocator = scratch.allocator();
    const native = try mechanical(allocator, report);
    if (native != .passed) return native;
    if (report.expected_outcome != .publication) return .{ .failed = .unexpected_outcome };
    const inputs = report.evaluation_inputs.?;
    const checked = judgment.validate(allocator, null, inputs, try std.json.Stringify.valueAlloc(allocator, judgment.Proposal{ .results = human_result.results }, .{})) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return .{ .failed = .grading_mismatch };
    };
    return switch (quality_policy.quality(inputs.rubric, checked)) {
        .passed => .passed,
        .failed => |failure| .{ .failed = switch (failure) {
            .critical_failed => .critical_failed,
            .threshold_failed => .threshold_failed,
        } },
        .unresolved => .{ .unresolved = .grading_unresolved },
    };
}

pub fn apply(a: std.mem.Allocator, report: *c.Report) Error!void {
    report.acceptance = try evaluate(a, report.*);
}

pub fn commandSucceeded(a: std.mem.Allocator, report: c.Report) Error!bool {
    return try evaluate(a, report) == .passed;
}

fn mechanical(a: std.mem.Allocator, report: c.Report) Error!Result {
    const expected = report.expected_outcome orelse return .{ .unresolved = .missing_expected_outcome };
    if (report.evidence_error != null) return .{ .failed = .harness_failed };
    if (report.status == .threshold_unconfigured and report.workflow_outcome == null) return .{ .unresolved = .grading_unresolved };
    switch (report.status) {
        .input_invalid, .harness_error, .bootstrap_failed, .fixture_changed => return .{ .failed = .harness_failed },
        .artifact_missing, .artifact_unreadable, .artifact_changed => return .{ .failed = .artifact_failed },
        .publication_missing => return .{ .failed = .publication_failed },
        else => {},
    }
    const outcome = report.workflow_outcome orelse return .{ .unresolved = .not_evaluated };
    switch (outcome) {
        .ok => if (expected != .publication) return .{ .failed = .unexpected_outcome },
        .needs_user => if (expected != .clarification) return .{ .failed = .unexpected_outcome },
        .more, .failed, .invalid, .blocked, .cancelled => return .{ .failed = .native_workflow_failed },
    }
    if (report.missing_artifact != null) return .{ .failed = .artifact_failed };
    if (report.publication_check != .passed or report.specification == null) return .{ .failed = .publication_failed };
    relative.validate(report.specification.?) catch return .{ .failed = .artifact_failed };
    const admitted = try nativeAdmission(a, report);
    if (admitted != .passed) return admitted;
    return switch (expected) {
        .publication => publication(a, report),
        .clarification => clarification(report),
    };
}

fn nativeAdmission(a: std.mem.Allocator, report: c.Report) Error!Result {
    const audit = report.admission_audit orelse return .{ .unresolved = .missing_admission_evidence };
    admission.validate(a, audit, report.admission_exchanges) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return .{ .failed = .admission_evidence_invalid };
    };
    const actual = admission.measure(audit, report.admission_exchanges) catch return .{ .failed = .admission_evidence_invalid };
    if (actual.escaped_values != 0 or actual.escaped_origins != 0) return .{ .failed = .admission_escape };
    const recorded = report.admission_escape orelse return .{ .unresolved = .missing_admission_evidence };
    if (!try sameJson(a, actual, recorded)) return .{ .failed = .admission_evidence_invalid };
    if (actual.status != .measured) return .{ .unresolved = .missing_admission_evidence };
    return .passed;
}

fn publication(a: std.mem.Allocator, report: c.Report) Error!Result {
    switch (report.status) {
        .generated => {},
        else => return .{ .failed = .harness_failed },
    }
    const inputs = report.evaluation_inputs orelse return .{ .unresolved = .missing_grading_evidence };
    const execution = report.execution_id orelse return .{ .unresolved = .missing_grading_evidence };
    const case_id = report.evaluation_case_id orelse return .{ .unresolved = .missing_grading_evidence };
    grading.validateCapture(inputs) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return .{ .failed = .grading_mismatch };
    };
    const original_case = grading.parseCase(a, inputs.case_bytes) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return .{ .failed = .grading_mismatch };
    };
    const original_rubric = grading.parseRubric(a, inputs.rubric_bytes) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return .{ .failed = .grading_mismatch };
    };
    if (!try sameJson(a, original_case, inputs.case) or !try sameJson(a, original_rubric, inputs.rubric) or
        !sameGeneration(report, inputs.generation) or !std.mem.eql(u8, execution, inputs.generation.execution_id orelse "") or
        !std.mem.eql(u8, case_id, inputs.case.id) or !sameSources(report, inputs.sources)) return .{ .failed = .grading_mismatch };
    return .passed;
}

fn clarification(report: c.Report) Result {
    if (report.status != .awaiting_clarification or report.evaluation_inputs != null)
        return .{ .failed = .unexpected_outcome };
    if (report.clarifications.len == 0) return .{ .unresolved = .invalid_clarifications };
    const directory = std.fs.path.dirname(report.specification.?) orelse return .{ .unresolved = .invalid_clarifications };
    for (report.clarifications, 0..) |form, index| {
        if (form.id.ordinal == 0 or form.id.ordinal > 99 or form.path.root != .specs) return .{ .unresolved = .invalid_clarifications };
        relative.validate(form.path.root_relative) catch return .{ .unresolved = .invalid_clarifications };
        relative.validate(form.path.project_relative) catch return .{ .unresolved = .invalid_clarifications };
        const filename = form.id.filename();
        const parent = std.fs.path.dirname(form.path.project_relative) orelse return .{ .unresolved = .invalid_clarifications };
        const root_parent = std.fs.path.dirname(form.path.root_relative) orelse return .{ .unresolved = .invalid_clarifications };
        const clarify = @import("../../../src/domain/workflow_artifact_registry.zig").clarification_directory_name;
        if (!std.mem.eql(u8, std.fs.path.basename(form.path.project_relative), &filename) or
            !std.mem.eql(u8, std.fs.path.basename(form.path.root_relative), &filename) or
            !std.mem.eql(u8, std.fs.path.basename(parent), clarify) or !std.mem.eql(u8, std.fs.path.basename(root_parent), clarify) or
            !std.mem.eql(u8, std.fs.path.dirname(parent) orelse "", directory) or
            !std.mem.endsWith(u8, form.path.project_relative, form.path.root_relative)) return .{ .unresolved = .invalid_clarifications };
        for (report.clarifications[0..index]) |prior| {
            if (std.meta.eql(prior.id, form.id) or std.mem.eql(u8, prior.path.project_relative, form.path.project_relative)) return .{ .unresolved = .invalid_clarifications };
        }
    }
    return .passed;
}

fn sameGeneration(report: c.Report, generated: grading.Generation) bool {
    if (generated.origin != .live_generation or generated.workflow_status != .completed or report.models.len == 0 or generated.models.len != report.models.len) return false;
    for (report.models) |expected| {
        const matching = for (generated.models) |model| {
            if (std.mem.eql(u8, model.slot, expected.slot)) break model;
        } else return false;
        if (!std.mem.eql(u8, expected.provider, matching.provider) or !std.mem.eql(u8, expected.model, matching.model)) return false;
    }
    return true;
}

fn sameSources(report: c.Report, sources: []const grading.Document) bool {
    const audited = report.admission_audit orelse return false;
    if (audited.sources.len != sources.len) return false;
    for (sources) |source| {
        var expected: usize = 0;
        var actual: usize = 0;
        for (sources) |other| if (std.mem.eql(u8, source.text, other.text)) {
            expected += 1;
        };
        for (audited.sources) |other| if (std.mem.eql(u8, source.text, other.bytes)) {
            actual += 1;
        };
        if (expected != actual) return false;
    }
    return true;
}

fn sameJson(a: std.mem.Allocator, left: anytype, right: @TypeOf(left)) Error!bool {
    const left_bytes = try std.json.Stringify.valueAlloc(a, left, .{});
    defer a.free(left_bytes);
    const right_bytes = try std.json.Stringify.valueAlloc(a, right, .{});
    defer a.free(right_bytes);
    return std.mem.eql(u8, left_bytes, right_bytes);
}
