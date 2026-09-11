const std = @import("std");
const evaluator = @import("../contracts.zig");
const relative = @import("../../../src/domain/relative_directory_path.zig");
pub const Artifact = enum { specification, reference_context, clarification_state, workflow_state };
pub const Copy = struct { source: []const u8, destination: []const u8 };
pub const Case = struct {
    schema: []const u8,
    id: []const u8,
    workflow_id: []const u8,
    feature: []const u8,
    reference: []const u8,
    config: []const u8,
    provider_script: []const u8,
    expected_specification: []const u8,
    directories: []const []const u8,
    files: []const Copy,
    expected_artifacts: []const Artifact,
};

pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) !Case {
    const value = try evaluator.decode(Case, allocator, bytes);
    if (!std.mem.eql(u8, value.schema, "spec-e2e-case/v1") or value.id.len == 0 or value.id.len > 128 or
        @import("../../../src/domain/workflow.zig").WorkflowId.parse(value.workflow_id) == null or
        value.files.len == 0 or value.files.len > 128 or value.directories.len > 32 or
        value.expected_artifacts.len != @typeInfo(Artifact).@"enum".fields.len) return error.InvalidE2ECase;
    try evaluator.path(value.feature);
    try evaluator.path(value.reference);
    try evaluator.path(value.config);
    try evaluator.path(value.provider_script);
    try evaluator.path(value.expected_specification);
    for (value.directories, 0..) |directory, index| {
        try evaluator.path(directory);
        if (relative.contains(".sddtoolkit.json", directory)) return error.InvalidE2ECase;
        for (value.directories[0..index]) |prior| if (std.ascii.eqlIgnoreCase(prior, directory)) return error.InvalidE2ECase;
    }
    for (value.files, 0..) |file, index| {
        try evaluator.path(file.source);
        try evaluator.path(file.destination);
        if (relative.contains(".sddtoolkit.json", file.destination)) return error.InvalidE2ECase;
        for (value.directories) |directory| if (relative.contains(file.destination, directory)) return error.InvalidE2ECase;
        for (value.files[0..index]) |prior| {
            if (relative.contains(prior.destination, file.destination) or relative.contains(file.destination, prior.destination)) return error.InvalidE2ECase;
        }
    }
    for (value.expected_artifacts, 0..) |artifact, index| {
        if (std.mem.indexOfScalar(Artifact, value.expected_artifacts[0..index], artifact) != null) return error.InvalidE2ECase;
    }
    return value;
}

pub const Status = enum {
    passed,
    input_invalid,
    harness_error,
    bootstrap_failed,
    workflow_failed,
    publication_missing,
    artifact_missing,
    artifact_unreadable,
    fixture_changed,
    content_mismatch,
};
pub const Report = struct {
    schema: []const u8 = "spec-e2e-report/v1",
    origin: enum { scripted } = .scripted,
    started_at_utc: []const u8,
    case_id: ?[]const u8 = null,
    workflow_id: ?[]const u8 = null,
    status: Status,
    workflow_outcome: ?@import("../../../src/domain/workflow.zig").OutcomeTag = null,
    model_calls: usize = 0,
    diagnostic: ?[]const u8 = null,
    missing_artifact: ?Artifact = null,
    specification: ?[]const u8 = null,
    publication_check: enum { not_run, passed, failed } = .not_run,
    fixture_content_check: enum { not_run, matched, mismatched } = .not_run,
    semantic_quality: enum { not_evaluated } = .not_evaluated,
};
