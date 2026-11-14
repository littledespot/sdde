const std = @import("std");
const evaluator = @import("../contracts.zig");
const relative = @import("../../../src/domain/relative_directory_path.zig");
const execution = @import("../../../src/domain/workflow_execution.zig");
const workflow_retry = @import("../../../src/domain/workflow_retry.zig");
pub const Artifact = enum { specification, reference_context, clarification_state, workflow_state };
pub const ExpectedOutcome = enum { publication, clarification };
pub const Copy = struct { source: []const u8, destination: []const u8 };
pub const Case = struct {
    schema: []const u8,
    id: []const u8,
    workflow_id: []const u8,
    expected_outcome: ExpectedOutcome,
    feature: []const u8,
    reference: []const u8,
    config: []const u8,
    evaluation_case: []const u8,
    directories: []const []const u8,
    files: []const Copy,
    expected_artifacts: []const Artifact,
};

pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) !Case {
    const value = try evaluator.decode(Case, allocator, bytes);
    if (!std.mem.eql(u8, value.schema, "spec-e2e-case/v3") or value.id.len == 0 or value.id.len > 128 or
        @import("../../../src/domain/workflow.zig").WorkflowId.parse(value.workflow_id) == null or
        value.files.len == 0 or value.files.len > 128 or value.directories.len > 32 or
        value.expected_artifacts.len != @typeInfo(Artifact).@"enum".fields.len) return error.InvalidE2ECase;
    try evaluator.path(value.feature);
    try evaluator.path(value.reference);
    try evaluator.path(value.config);
    try evaluator.path(value.evaluation_case);
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
    input_invalid,
    harness_error,
    bootstrap_failed,
    workflow_failed,
    awaiting_clarification,
    workflow_invalid,
    workflow_blocked,
    workflow_cancelled,
    publication_missing,
    artifact_missing,
    artifact_unreadable,
    fixture_changed,
    artifact_changed,
    generated,
    threshold_unconfigured,
};

/// What a rejection adds to its tag in a report: the same for every projection of one, so each is said once.
fn reasonOf(value: execution.Rejection) ?execution.AuthorityReason {
    return if (value == .authority) value.authority else null;
}

fn detailOf(value: execution.Rejection) ?[]const u8 {
    return switch (value) {
        .gate => |reason| @tagName(reason),
        .logging => |reason| @tagName(reason),
        .token_budget => |reason| @errorName(reason),
        .operation_failed => value.diagnostic(),
        .model_capture => |reason| reason.diagnostic(),
        .authority, .cancelled, .deadline_exhausted, .retry_limit => null,
    };
}

/// An authority reason sits beside the kind `authority` and nowhere else.
fn reasonPaired(is_authority: bool, reason: ?execution.AuthorityReason) bool {
    return is_authority == (reason != null);
}

/// Serializable projection of a native rejection; no inferred domain verdict.
pub const TerminalRejection = struct {
    kind: std.meta.Tag(execution.Rejection),
    /// Why the runner stopped on its own authority: non-null exactly when `kind` is `authority`.
    reason: ?execution.AuthorityReason = null,
    detail: ?[]const u8 = null,
    capture_failure: ?@import("../../../src/domain/model_capture_failure.zig").Failure = null,

    pub fn fromNative(value: execution.Rejection) TerminalRejection {
        return .{ .kind = std.meta.activeTag(value), .reason = reasonOf(value), .detail = detailOf(value), .capture_failure = if (value == .model_capture) value.model_capture else null };
    }

    /// Decoding rejects a reason on any other kind, and an authority rejection that names none.
    pub fn jsonParse(a: std.mem.Allocator, source: *std.json.Scanner, options: std.json.ParseOptions) std.json.ParseError(std.json.Scanner)!TerminalRejection {
        const wire = try std.json.innerParse(Wire, a, source, options);
        if (!reasonPaired(wire.kind == .authority, wire.reason)) return error.UnexpectedToken;
        return .{ .kind = wire.kind, .reason = wire.reason, .detail = wire.detail, .capture_failure = wire.capture_failure };
    }

    /// The same members without the pairing check; decoding only.
    const Wire = struct {
        kind: std.meta.Tag(execution.Rejection),
        reason: ?execution.AuthorityReason = null,
        detail: ?[]const u8 = null,
        capture_failure: ?@import("../../../src/domain/model_capture_failure.zig").Failure = null,
    };
    comptime {
        for (std.meta.fields(TerminalRejection)) |field| std.debug.assert(@FieldType(Wire, field.name) == field.type);
        std.debug.assert(std.meta.fields(Wire).len == std.meta.fields(TerminalRejection).len);
    }
};

/// Serializable projection of the rejection a later one replaced. A capture failure is recorded while its
/// call runs, so it is its own first cause and never one that was replaced: the kind is over the writer's
/// `execution.FirstCause`, which has no such member, so a report cannot name one.
pub const FirstCause = struct {
    kind: std.meta.Tag(execution.FirstCause),
    /// Why the runner stopped on its own authority: non-null exactly when `kind` is `authority`.
    reason: ?execution.AuthorityReason = null,
    detail: ?[]const u8 = null,
    /// What an exhausted retry limit counted, as `Report.retry_error` gives it for a terminal one:
    /// non-null exactly when `kind` is `retry_limit`.
    exhaustion: ?workflow_retry.Exhaustion.Description = null,

    /// The allocator owns the exhaustion's operation name.
    pub fn fromNative(a: std.mem.Allocator, value: execution.FirstCause) std.mem.Allocator.Error!FirstCause {
        const rejected = value.rejection();
        return .{ .kind = std.meta.activeTag(value), .reason = reasonOf(rejected), .detail = detailOf(rejected), .exhaustion = if (value == .retry_limit) try value.retry_limit.describe(a) else null };
    }

    /// The same cause as the projection of a rejection, which has no place for an exhaustion's facts.
    pub fn asTerminal(self: FirstCause) TerminalRejection {
        return .{ .kind = switch (self.kind) {
            inline else => |tag| @field(std.meta.Tag(execution.Rejection), @tagName(tag)),
        }, .reason = self.reason, .detail = self.detail };
    }

    /// Decoding rejects a reason on any other kind, an authority cause that names none, exhaustion facts on
    /// any other kind and a retry exhaustion without them.
    pub fn jsonParse(a: std.mem.Allocator, source: *std.json.Scanner, options: std.json.ParseOptions) std.json.ParseError(std.json.Scanner)!FirstCause {
        const wire = try std.json.innerParse(Wire, a, source, options);
        if (!reasonPaired(wire.kind == .authority, wire.reason) or (wire.kind == .retry_limit) != (wire.exhaustion != null)) return error.UnexpectedToken;
        return .{ .kind = wire.kind, .reason = wire.reason, .detail = wire.detail, .exhaustion = wire.exhaustion };
    }

    /// The same members without the pairing checks; decoding only.
    const Wire = struct {
        kind: std.meta.Tag(execution.FirstCause),
        reason: ?execution.AuthorityReason = null,
        detail: ?[]const u8 = null,
        exhaustion: ?workflow_retry.Exhaustion.Description = null,
    };
    comptime {
        for (std.meta.fields(FirstCause)) |field| std.debug.assert(@FieldType(Wire, field.name) == field.type);
        std.debug.assert(std.meta.fields(Wire).len == std.meta.fields(FirstCause).len);
    }
};
pub const Attempt = struct {
    origin: @import("../../../src/domain/model_candidate_origin.zig").Origin,
    step: []const u8,
    /// The request's native purpose and owner, which attribute its consumption to a stage.
    purpose: @import("../../../src/domain/model_request_identity.zig").RequestPurposeKind,
    owner_kind: std.meta.Tag(@import("../../../src/domain/model_request_identity.zig").ImmutableUnitOwnerId),
    /// ADR 0039: the attempt ordinal a runaway re-send repeats, otherwise null.
    resends: ?u32 = null,
    accounting: std.meta.Tag(@import("../../../src/domain/workflow_token_accounting.zig").Reconciliation),
    usage: ?@import("../../../src/domain/llm_provider_operation.zig").ProviderUsage,
};
pub const ProtocolRejection = struct {
    call: usize,
    origin: @import("../../../src/domain/model_candidate_origin.zig").Origin,
    reason: []const u8,
    json_error: ?@import("../../../src/domain/strict_json.zig").Diagnostic,
    composition_error: ?@import("../../../src/domain/model_text_composition.zig").Diagnostic = null,
    schema_error: ?@import("../../../src/domain/model_schema_diagnostic.zig").Description,
};
pub const ProviderRejection = struct {
    call: ?usize,
    origin: ?@import("../../../src/domain/model_candidate_origin.zig").Origin,
    reason: []const u8,
    content: ?@import("../../../src/domain/llm_provider_operation.zig").ProviderContentDiagnostic,
};
pub const NativeRejection = struct {
    sequence: usize,
    step: []const u8,
    evidence: union(enum) {
        candidate: @import("../../../src/domain/candidate_validation_diagnostic.zig").Diagnostic,
        protocol: ProtocolRejection,
        provider: ProviderRejection,
        runner: TerminalRejection,
        operation: @import("../../../src/domain/workflow_execution.zig").OperationRejection,
    },
};
pub const WorkLink = struct { key: @import("../../../src/domain/pipeline.zig").DataKey, invalidated_at: usize };
pub const Correction = struct {
    sequence: usize,
    step: []const u8,
    repair: ?@import("../../../src/domain/workflow_retry.zig").Transition,
    rejection: ?@import("../../../src/domain/operation_error.zig").Code(@import("../../../src/domain/workflow_execution.zig").OperationError),
    invalidated: []const @import("../../../src/domain/pipeline.zig").DataKey,
    rebuilt: []const WorkLink,
};
pub const ExchangeEvidence = struct {
    raw_response: ?[]const u8,
    text: enum { available, response_absent, budget_stop, not_projected, capture_failed },
    status: ?u16,
    exception: ?[]const u8,
    request_id: ?[]const u8,
    transport: ?@import("../../../src/domain/llm_provider_operation.zig").TransportDiagnostic,
};
pub const Report = struct {
    schema: enum { @"spec-e2e-report/v19" },
    origin: enum { live } = .live,
    started_at_utc: []const u8,
    build: ?struct {
        source: @import("../../../build/provenance.zig").Identity,
        zig_version: []const u8,
        target: []const u8,
        optimize: []const u8,
        inputs_file: ?[]const u8 = null,
        reconstruction: enum { not_captured, captured, incomplete, redacted } = .not_captured,
    } = null,
    execution_id: ?[]const u8 = null,
    case_source: ?[]const u8 = null,
    case_id: ?[]const u8 = null,
    evaluation_case_id: ?[]const u8 = null,
    workflow_id: ?[]const u8 = null,
    expected_outcome: ?ExpectedOutcome = null,
    acceptance: @import("acceptance.zig").Result = .{ .unresolved = .not_evaluated },
    status: Status,
    workflow_outcome: ?@import("../../../src/domain/workflow.zig").OutcomeTag = null,
    clarifications: []const @import("../../../src/domain/run_outcome.zig").Clarification = &.{},
    terminal_step: ?[]const u8 = null,
    terminal_rejection: ?TerminalRejection = null,
    /// The rejection a later one replaced during the run, kept whole beside the terminal one.
    /// Null for a lone failure; never a capture failure, which is its own first cause.
    first_cause: ?FirstCause = null,
    last_operation_rejection: ?@import("../../../src/domain/workflow_execution.zig").OperationRejection = null,
    /// Reconciled inference operations, including proven non-delivery.
    model_calls: usize = 0,
    not_sent_operations: usize = 0,
    token_accounting: ?@import("../../../src/domain/workflow_token_accounting.zig").Snapshot = null,
    retry_settings: []const @import("../../../src/domain/workflow_retry.zig").Observation = &.{},
    attempts: []const Attempt = &.{},
    last_model_step: ?[]const u8 = null,
    last_model_origin: ?@import("../../../src/domain/model_candidate_origin.zig").Origin = null,
    models: []const evaluator.GenerationModel = &.{},
    total_tokens: u128 = 0,
    last_model_usage: ?@import("../../../src/domain/llm_provider_operation.zig").ProviderUsage = null,
    usage_complete: bool = true,
    diagnostic: ?[]const u8 = null,
    provider_diagnostic: ?[]const u8 = null,
    provider_origin: ?@import("../../../src/domain/model_candidate_origin.zig").Origin = null,
    provider_content_diagnostic: ?@import("../../../src/domain/llm_provider_operation.zig").ProviderContentDiagnostic = null,
    model_diagnostic: ?[]const u8 = null,
    last_protocol_rejection: ?ProtocolRejection = null,
    last_provider_rejection: ?ProviderRejection = null,
    first_native_rejection: ?NativeRejection = null,
    /// Read-only replay of shared mechanical text rules over admitted native
    /// values. Missing capture is distinct from a measured zero escape count.
    admission_audit: ?@import("../baseline/admission.zig").Audit = null,
    admission_exchanges: []const @import("../baseline/admission.zig").Exchange = &.{},
    admission_escape: ?@import("../baseline/admission.zig").Metric = null,
    corrections: []const Correction = &.{},
    outstanding_work: []const WorkLink = &.{},
    exchange_evidence: ?ExchangeEvidence = null,
    candidate_error: ?@import("../../../src/domain/candidate_validation_diagnostic.zig").Diagnostic = null,
    repairs: []const @import("../../../src/domain/atomic_repair.zig").Merge = &.{},
    candidate_model_call: ?usize = null,
    candidate_model_step: ?[]const u8 = null,
    candidate_model_output: ?[]const u8 = null,
    schema_error: ?@import("../../../src/domain/model_schema_diagnostic.zig").Description = null,
    retry_error: ?@import("../../../src/domain/workflow_retry.zig").Exhaustion.Description = null,
    json_error: ?@import("../../../src/domain/strict_json.zig").Diagnostic = null,
    composition_error: ?@import("../../../src/domain/model_text_composition.zig").Diagnostic = null,
    events_file: ?[]const u8 = null,
    evidence_root: ?[]const u8 = null,
    evidence_error: ?[]const u8 = null,
    last_model_call: ?usize = null,
    last_model_output: ?[]const u8 = null,
    missing_artifact: ?Artifact = null,
    specification: ?[]const u8 = null,
    publication_check: enum { not_run, passed, failed } = .not_run,
    /// ADR 0041: the incomplete set a failed or blocked run published. Its step,
    /// diagnostic and outcome are `terminal_step`, `diagnostic` and `workflow_outcome`,
    /// and its bytes stay in the run's `project/`. Null until E0 writes it.
    incomplete_publication: ?[]const Artifact = null,
    /// Exact source, rubric and published bytes for offline adjudication.
    evaluation_inputs: ?evaluator.Capture = null,
};
