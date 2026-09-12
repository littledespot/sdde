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
    evaluation_case: []const u8,
    evaluation_config: []const u8,
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
    try evaluator.path(value.evaluation_case);
    try evaluator.path(value.evaluation_config);
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
    evaluated,
    input_invalid,
    harness_error,
    bootstrap_failed,
    workflow_failed,
    publication_missing,
    artifact_missing,
    artifact_unreadable,
    fixture_changed,
    artifact_changed,
    generated,
    evaluator_failed,
    quality_unresolved,
};
pub const Report = struct {
    schema: []const u8 = "spec-e2e-report/v1",
    origin: enum { live } = .live,
    started_at_utc: []const u8,
    execution_id: ?[]const u8 = null,
    case_source: ?[]const u8 = null,
    case_id: ?[]const u8 = null,
    workflow_id: ?[]const u8 = null,
    status: Status,
    workflow_outcome: ?@import("../../../src/domain/workflow.zig").OutcomeTag = null,
    model_calls: usize = 0,
    last_model_step: ?[]const u8 = null,
    models: []const evaluator.GenerationModel = &.{},
    total_tokens: u128 = 0,
    last_model_usage: ?@import("../../../src/domain/llm_provider_operation.zig").ProviderUsage = null,
    usage_complete: bool = true,
    diagnostic: ?[]const u8 = null,
    provider_diagnostic: ?[]const u8 = null,
    model_diagnostic: ?[]const u8 = null,
    candidate_error: ?@import("../../../src/domain/candidate_validation_diagnostic.zig").Diagnostic = null,
    candidate_model_call: ?usize = null,
    candidate_model_step: ?[]const u8 = null,
    candidate_model_output: ?[]const u8 = null,
    schema_error: ?@import("../../../src/domain/model_schema_diagnostic.zig").Description = null,
    retry_error: ?@import("../../../src/domain/workflow_retry.zig").Exhaustion.Description = null,
    json_error: ?@import("../../../src/domain/strict_json.zig").Diagnostic = null,
    events_file: ?[]const u8 = null,
    evidence_root: ?[]const u8 = null,
    evidence_error: ?[]const u8 = null,
    last_model_call: ?usize = null,
    last_model_output: ?[]const u8 = null,
    missing_artifact: ?Artifact = null,
    specification: ?[]const u8 = null,
    publication_check: enum { not_run, passed, failed } = .not_run,
    semantic_quality: enum { not_evaluated, scored, unresolved, evaluator_error } = .not_evaluated,
    evaluation_configuration: ?@import("../configuration.zig").Config = null,
    evaluation: ?@import("../report.zig").Report = null,
};
