//! Development invocation of the configured workflow through production ports.
const std = @import("std");
const c = @import("contracts.zig");
const fixture = @import("fixture.zig");
const root = @import("../../../src/composition/root.zig");
const values = @import("../../../src/application/pipeline_values.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, project: std.Io.Dir, selected: c.Case, captured: fixture.Capture, key: ?[]const u8, store: @import("../evidence.zig").Store, report: *c.Report) !?[]const u8 {
    var runtime: root.Runtime = undefined;
    runtime.init(io, allocator, project, .{});
    defer runtime.deinit();
    switch (runtime.boot) {
        .ready => {},
        .failed => |reason| {
            report.status = .bootstrap_failed;
            report.diagnostic = @tagName(reason);
            return null;
        },
        .cancelled => {
            report.status = .workflow_cancelled;
            report.workflow_outcome = .cancelled;
            return null;
        },
    }
    const roots = runtime.boot.ready.roots.registry();
    const configured = roots.featureArtifactRoots();
    try fixture.validateOutputs(captured, configured, allocator);
    try fixture.validateEvaluationSources(allocator, captured, runtime.boot.ready.config.config().paths.references, selected.reference);
    const directory = try @import("../../../src/domain/feature_directory.zig").validate(allocator, .{ .bytes = selected.feature }, .{ .specs = configured.specs, .archive = configured.archive });
    const resolved = try @import("../../../src/domain/workflow_artifact_registry.zig").resolveFeaturePaths(allocator, configured, directory);
    report.status = .harness_error;
    // The isolated credential uses the same authorization and provider bindings.
    const snapshot = try @import("../../../src/adapters/provider/bedrock_api_key.zig").Snapshot.capture(allocator, key);
    var invocation = runtime.invocation(&.{ selected.workflow_id, "--feature", selected.feature, "--reference", selected.reference }, .{ .snapshot = snapshot });
    defer invocation.deinit();

    var trace = try @import("trace.zig").Trace.init(store, &invocation);
    defer trace.close();
    report.events_file = "events.jsonl";
    report.evidence_root = "evidence";
    // One production invocation. The observer forwards every selection, step
    // and HTTPS exchange unchanged, retaining diagnostic evidence as it occurs.
    const result = @import("../../../src/application/workflow_engine_orchestrator.zig").run(trace.port());
    if (trace.failure != null or result.executionStatus() != .ok) {
        if (trace.last_step) |step| report.terminal_step = try allocator.dupe(u8, step.bytes);
        if (result == .execution_rejected) report.terminal_rejection = c.TerminalRejection.fromNative(result.execution_rejected);
    }
    if (trace.calls != 0) {
        report.last_model_call = trace.calls;
        if (trace.output_written) report.last_model_output = try @import("../evidence.zig").Store.path(allocator, .generation, trace.calls, .model_output);
    }
    if (trace.failure) |failure| {
        report.status = .harness_error;
        report.evidence_error = @errorName(failure);
    }
    report.workflow_outcome = result.executionStatus();
    switch (result) {
        .execution => |outcome| if (outcome == .failed) {
            report.diagnostic = @tagName(outcome);
        },
        .execution_rejected => |reason| {
            report.diagnostic = reason.diagnostic();
            if (reason == .retry_limit) report.retry_error = try reason.retry_limit.describe(allocator);
        },
        .bootstrap_failed => |reason| {
            report.status = .bootstrap_failed;
            report.diagnostic = @tagName(reason);
            return null;
        },
        .invocation_invalid => {
            report.status = .input_invalid;
            report.diagnostic = "INVALID_WORKFLOW_INVOCATION";
            return null;
        },
    }
    const outcome = report.workflow_outcome orelse {
        report.status = .workflow_failed;
        return null;
    };
    var publication: @import("oracle.zig").Publication = .not_observed;
    if (invocation.pipeline_runner) |*runner| {
        if (outcome == .needs_user) report.clarifications = try @import("../../../src/application/workflow_clarification_report.zig").capture(allocator, &.{ .slots = runner.envelope.slots });
        try @import("observation.zig").capture(allocator, runner, report);
        try trace.last_rejection.project(allocator, trace.calls, report);
        try trace.correlate(allocator, report);
        if (runner.envelope.slots[@intFromEnum(@import("../../../src/domain/pipeline.zig").DataKey.published_workflow_output)] != null) {
            const published = try values.read(&.{ .slots = runner.envelope.slots }, @import("../../../src/application/workflow_output_binding.zig").published_schema, bool);
            if (published.*) publication = .{ .confirmed = try values.read(&.{ .slots = runner.envelope.slots }, @import("../../../src/application/workflow_output_binding.zig").prepared_schema, @import("../../../src/domain/workflow_output.zig").Prepared) };
        }
    }
    if (trace.failure != null) return error.EvidenceCaptureFailed;
    const observed = try @import("oracle.zig").inspect(io, allocator, project, outcome, publication, selected.expected_artifacts, resolved);
    report.status = observed.status;
    report.missing_artifact = observed.missing_artifact;
    report.specification = observed.specification;
    report.publication_check = if (outcome != .ok) .not_run else if (observed.status == .generated) .passed else .failed;
    if (observed.status == .publication_missing) report.diagnostic = "WORKFLOW_OUTPUT_NOT_PUBLISHED";
    if (observed.status == .artifact_changed) report.diagnostic = "PUBLISHED_ARTIFACT_CHANGED";
    return observed.specification_bytes;
}
