//! Development invocation of the configured workflow through production ports.
const std = @import("std");
const c = @import("contracts.zig");
const fixture = @import("fixture.zig");
const root = @import("../../../src/composition/root.zig");
const values = @import("../../../src/application/pipeline_values.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, project: std.Io.Dir, selected: c.Case, captured: fixture.Capture, key: ?[]const u8, report: *c.Report) !?[]const u8 {
    var toolchain = @import("../../../src/adapters/filesystem/toolchain_authority_source.zig").Adapter.init(io, project);
    var parser: @import("../../../src/adapters/parsers/toolchain_documents.zig").Adapter = .{};
    var reference: @import("../../../src/adapters/filesystem/reference_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project };
    var feature: @import("../../../src/adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project };
    var inputs: @import("../../../src/adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project };
    var outputs: @import("../../../src/adapters/filesystem/workflow_output.zig").Adapter = .{ .io = io, .project_root = project };
    var corpus: @import("../../../src/adapters/filesystem/reference_corpus_source.zig").Adapter = .{ .io = io, .project_root = project };
    var markdown: @import("../../../src/adapters/parsers/markdown_reference.zig").Adapter = .{ .io = io };
    var identities: @import("../../../src/adapters/system/reference_state_identity.zig").Adapter = .{ .io = io };
    var native: @import("../../../src/composition/native_workflow_operations.zig").Assembly = undefined;
    native.init(allocator, toolchain.projectCapturer(), toolchain.presetEnumerator(), toolchain.presetCapturer(), parser.parser(), @import("../../../src/composition/toolchain_policy_registry.zig").registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, reference.inspector(), feature.inspector(), inputs.capturer(), @import("../../../src/adapters/parsers/clarification_inputs.zig").stateParser(), @import("../../../src/adapters/parsers/clarification_inputs.zig").formParser(), corpus.enumerator(), corpus.capturer(), markdown.decoderPort(), .{ .fold_fn = @import("unicode_normalization").caseFold }, identities.source(), .{ .boundary_fn = @import("unicode_normalization").lexicalBoundary });
    native.publish_output.action.writer = outputs.port();
    native.capture_workflow_state.action.source = inputs.workflowStateCapturer();
    var boot = root.runInProjectWithRegistry(io, allocator, project, .{}, &native.registry);
    defer boot.deinit();
    switch (boot) {
        .ready => {},
        .failed => |reason| {
            report.status = .bootstrap_failed;
            report.diagnostic = @tagName(reason);
            return null;
        },
        .cancelled => {
            report.status = .workflow_failed;
            report.workflow_outcome = .cancelled;
            return null;
        },
    }
    const roots = boot.ready.roots.registry();
    native.bindRoots(roots);
    const configured = roots.featureArtifactRoots();
    try fixture.validateOutputs(captured, configured, allocator);
    try fixture.validateEvaluationSources(allocator, captured, boot.ready.config.config().paths.references, selected.reference);
    const directory = try @import("../../../src/domain/feature_directory.zig").validate(allocator, .{ .bytes = selected.feature }, .{ .specs = configured.specs, .archive = configured.archive });
    const resolved = try @import("../../../src/domain/workflow_artifact_registry.zig").resolveFeaturePaths(allocator, configured, directory);
    report.status = .harness_error;
    var providers = @import("../../../src/composition/model_provider_bootstrap.zig").Assembly.init(io, allocator, project, .{}, &@import("../../../src/composition/provider_model_contracts.zig").registry);
    var clock: @import("../../../src/adapters/system/provider_operation_clock.zig").Adapter = .{ .io = io };
    var provider_runtime: @import("../../../src/composition/model_provider_runtime.zig").Assembly = .{
        .environment = null,
        .operations = &native.model_requests,
        .authorization = .{ .allocator = allocator },
        .transport = .{ .io = io, .clock = clock.clock(), .runtime = .{} },
    };
    defer provider_runtime.deinit();
    // The internal test credential supplies real authorization; the production
    // provider runtime owns binding, leases, dispatch and HTTPS invocation.
    const snapshot = try @import("../../../src/adapters/provider/bedrock_api_key.zig").Snapshot.capture(allocator, key);
    provider_runtime.authorization.material = if (snapshot) |value| .{ .ready = value } else .unavailable;
    var invocation = @import("../../../src/composition/engine_invocation.zig").Assembly.init(allocator, &boot.ready, &.{ selected.workflow_id, "--feature", selected.feature, "--reference", selected.reference }, &native.registry, providers.bind(), .{});
    defer invocation.deinit();
    invocation.provider_clock = clock.clock();
    invocation.provider_runtime = &provider_runtime;

    // Exactly one ordinary invocation. No scenario loop or substituted selection
    // callbacks, and no call to the regression driver's run/step methods.
    const result = @import("../../../src/application/workflow_engine_orchestrator.zig").run(invocation.bindings());
    report.workflow_outcome = result.executionStatus();
    switch (result) {
        .execution => |outcome| if (outcome != .ok) {
            report.diagnostic = @tagName(outcome);
        },
        .execution_rejected => |reason| report.diagnostic = reason.diagnostic(),
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
        try @import("observation.zig").capture(allocator, runner, report);
        if (runner.envelope.slots[@intFromEnum(@import("../../../src/domain/pipeline.zig").DataKey.published_workflow_output)] != null) {
            const published = try values.read(&.{ .slots = runner.envelope.slots }, @import("../../../src/application/workflow_output_binding.zig").published_schema, bool);
            if (published.*) publication = .{ .confirmed = try values.read(&.{ .slots = runner.envelope.slots }, @import("../../../src/application/workflow_output_binding.zig").prepared_schema, @import("../../../src/domain/workflow_output.zig").Prepared) };
        }
    }
    const observed = try @import("oracle.zig").inspect(io, allocator, project, outcome, publication, selected.expected_artifacts, resolved);
    report.status = observed.status;
    report.missing_artifact = observed.missing_artifact;
    report.specification = observed.specification;
    report.publication_check = if (observed.status == .generated) .passed else .failed;
    if (observed.status == .publication_missing) report.diagnostic = "WORKFLOW_OUTPUT_NOT_PUBLISHED";
    if (observed.status == .artifact_changed) report.diagnostic = "PUBLISHED_ARTIFACT_CHANGED";
    return observed.specification_bytes;
}
