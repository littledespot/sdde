//! Offline production requests with explicit frozen-protocol fixtures. Scripted
//! exchanges prove harness boundaries only, never current live compatibility.
const std = @import("std");
const fixture = @import("../harness/e2e/fixture.zig");
const contracts = @import("../harness/e2e/contracts.zig");
const invoke = @import("../harness/e2e/invoke.zig");
const files = @import("../harness/files.zig");
const evidence = @import("../harness/evidence.zig");
const artifacts = @import("../../src/domain/workflow_artifact_registry.zig");
const inspection = @import("../harness/compatibility/inspection.zig");

const cases = [_][]const u8{
    "test/e2e/wf-001-hello-world/node-vitest/workflow.case.json",
    "test/e2e/wf-002-loan-renewal/workflow.case.json",
};
const Scenario = enum {
    complete,
    empty_server_tool_usage_prefix,
    null_server_tool_usage,
    array_server_tool_usage,
    unknown_server_tool_usage,
    unknown_usage,
    cancelled,
    partial_cancelled,
    transport_failed,
    partial_transport_failed,
    missing_usage,
    malformed_provider,
    noncandidate_stop,
    schema_invalid,
    malformed_candidate,
    capture_failed,
};
const payload = "{\"kind\":\"claims\",\"claims\":[]}";
const key = "MOCK-offline-compatibility-key";
const response_prefix = "{\"output\":{\"message\":{";

fn digest(bytes: []const u8) [32]u8 {
    var value: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &value, .{});
    return value;
}

const PrefixCancellation = struct {
    wire: *@import("../../src/model_transport_test_fixture.zig").Wire,

    fn port(self: *PrefixCancellation) @import("../../src/adapters/provider/model_http_transport.zig").Port {
        return .{ .context = @ptrCast(self), .exchange_fn = exchange };
    }

    fn exchange(context: *@import("../../src/adapters/provider/model_http_transport.zig").Context, a: std.mem.Allocator, request: @import("../../src/adapters/provider/model_http_transport.zig").Request) @import("../../src/adapters/provider/model_http_transport.zig").Error!@import("../../src/adapters/provider/model_http_transport.zig").Response {
        const self: *PrefixCancellation = @ptrCast(@alignCast(context));
        std.debug.assert(request.response_body_on_error != null);
        request.response_body_on_error.?.* = .{ .bytes = response_prefix, .complete = false };
        return self.wire.port().exchange(a, request);
    }
};

fn body(a: std.mem.Allocator, scenario: Scenario) ![]const u8 {
    if (scenario == .malformed_provider) return "{";
    if (scenario == .empty_server_tool_usage_prefix) return @embedFile("../../src/test_fixtures/bedrock_converse_usage/response.json");
    const text = try std.json.Stringify.valueAlloc(a, switch (scenario) {
        .schema_invalid => "{}",
        .malformed_candidate => "not JSON",
        .complete, .null_server_tool_usage, .array_server_tool_usage, .unknown_server_tool_usage, .unknown_usage, .cancelled, .partial_cancelled, .transport_failed, .partial_transport_failed, .missing_usage, .malformed_provider, .noncandidate_stop, .capture_failed => payload,
        .empty_server_tool_usage_prefix => unreachable,
    }, .{});
    const usage = switch (scenario) {
        .missing_usage => "",
        .null_server_tool_usage => ",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12,\"serverToolUsage\":null}",
        .array_server_tool_usage => ",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12,\"serverToolUsage\":[]}",
        .unknown_server_tool_usage => ",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12,\"serverToolUsage\":{\"unknown\":0}}",
        .unknown_usage => ",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12,\"unknown\":0}",
        .complete, .empty_server_tool_usage_prefix, .cancelled, .partial_cancelled, .transport_failed, .partial_transport_failed, .malformed_provider, .noncandidate_stop, .schema_invalid, .malformed_candidate, .capture_failed => ",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12}",
    };
    return std.fmt.allocPrint(
        a,
        "{{\"output\":{{\"message\":{{\"role\":\"assistant\",\"content\":[{{\"reasoningContent\":{{\"reasoningText\":{{\"text\":\"MOCK supplied reasoning\",\"signature\":\"MOCK opaque signature\"}}}}}},{{\"text\":{s}}}]}}}},\"stopReason\":\"{s}\"{s},\"metrics\":{{\"latencyMs\":7}}}}",
        .{ text, if (scenario == .noncandidate_stop) "max_tokens" else "end_turn", usage },
    );
}

fn absent(io: std.Io, root: std.Io.Dir, path: []const u8) !void {
    if (root.openFile(io, path, .{ .mode = .read_only, .follow_symlinks = false, .allow_directory = false })) |file| {
        file.close(io);
        return error.UnexpectedWorkflowPublication;
    } else |err| try std.testing.expectEqual(error.FileNotFound, err);
}

fn runScenario(case_path: []const u8, scenario: Scenario) !void {
    return runScenarioWithBinding(case_path, scenario, .frozen_protocol);
}

fn runScenarioWithBinding(case_path: []const u8, scenario: Scenario, binding: enum { frozen_protocol, drifted_protocol }) !void {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(io, "run/project");
    const run = try temporary.dir.openDir(io, "run", .{});
    defer run.close(io);
    const project = try run.openDir(io, "project", .{});
    defer project.close(io);

    const shipped = try contracts.parse(a, try files.read(io, a, .cwd(), case_path));
    var selected = if (binding == .frozen_protocol) try @import("frozen_protocol_fixture.zig").select(a, shipped) else shipped;
    if (binding == .drifted_protocol) selected.config = @import("frozen_protocol_fixture.zig").mock_bad_input_config_source;
    const case_bytes = try std.json.Stringify.valueAlloc(a, selected, .{});
    const captured = try fixture.capture(io, a, .cwd(), selected);
    try @import("../harness/output.zig").write(io, run, "case.json", case_bytes);
    try fixture.materialize(io, project, captured);
    var wire: @import("../../src/model_transport_test_fixture.zig").Wire = .{
        .expected_json = true,
        .cancelled = scenario == .cancelled or scenario == .partial_cancelled,
        .inference_body = try body(a, scenario),
    };
    wire.result = .{ .received = .{ .status = 200, .request_id = "MOCK-bedrock-request-id", .body = wire.inference_body } };
    if (scenario == .transport_failed or scenario == .partial_transport_failed) wire.result = .{ .failed = .{
        .cause = .transport_failed,
        .retry_class = .policy_eligible,
        .delivery = .accepted_or_unknown,
        .diagnostic = .{ .phase = .response_headers, .cause = .connection_reset },
        .body = if (scenario == .partial_transport_failed) .{ .bytes = response_prefix, .complete = false } else null,
    } };
    var prefix_cancellation: PrefixCancellation = .{ .wire = &wire };
    var probe: invoke.Probe = .{};
    var report: contracts.Report = .{
        .schema = .@"spec-e2e-report/v9",
        .started_at_utc = "2026-10-15T00:00:00Z",
        .case_id = selected.id,
        .workflow_id = selected.workflow_id,
        .status = .input_invalid,
    };
    const store: evidence.Store = .{ .io = io, .allocator = a, .run = run, .secrets = &.{key} };
    if (scenario == .capture_failed) {
        // A directory where the exclusive evidence file belongs injects a sink
        // failure before transport forwarding, without replacing production IO.
        try run.createDirPath(io, try evidence.Store.path(a, .generation, 1, .context));
    }
    const published = invoke.run(io, a, project, selected, captured, @import("../harness/environment.zig").bedrockOnly(key), store, &report, .{
        .purpose = .{ .single_exchange = &probe },
        .transport = if (scenario == .partial_cancelled) prefix_cancellation.port() else wire.port(),
    }) catch |err| {
        if (binding == .drifted_protocol) {
            // Preflight rejects before a captured call exists. Final evidence
            // correlation independently rejects that absent call; the retained
            // primary diagnostic must still identify the frozen policy drift.
            try std.testing.expectEqual(error.MissingRequestEvidence, err);
            try std.testing.expectEqual(.binding_rejected, probe.boundary);
            try std.testing.expectEqual(@as(usize, 0), probe.physical_sends);
            try std.testing.expectEqual(@as(usize, 0), wire.calls);
            try std.testing.expectEqualStrings("FrozenBindingRejected", report.evidence_error.?);
            try std.testing.expectEqual(.harness_error, report.status);
            try std.testing.expect(report.workflow_outcome != .ok);
            try std.testing.expect(report.specification == null);
            try std.testing.expectEqual(.not_run, report.publication_check);
            try std.testing.expect(report.evaluation_inputs == null);
            var current = try (@import("../../src/actions/config/decode_sddtoolkit_config.zig").Action{}).execute(a, try files.read(io, a, project, ".sddtoolkit.json"));
            defer current.deinit();
            try std.testing.expectEqualStrings("medium", current.value().models.slots.map.get("spec_generation").?.reasoningEffort.?);
            try fixture.verifySources(io, a, .cwd(), captured);
            return;
        }
        if (scenario != .capture_failed) return err;
        try std.testing.expectEqual(error.EvidenceCaptureFailed, err);
        try std.testing.expectEqual(@as(usize, 0), wire.calls);
        try std.testing.expectEqual(@as(usize, 0), probe.physical_sends);
        try std.testing.expectEqual(.capture_failed, probe.boundary);
        try std.testing.expect(probe.request_sha256 == null);
        try std.testing.expect(probe.response_sha256 == null);
        try std.testing.expect(report.evidence_error != null);
        try std.testing.expect(report.specification == null);
        try std.testing.expect(report.workflow_outcome != null and report.workflow_outcome.? != .ok);
        return;
    };
    if (binding == .drifted_protocol) return error.TestExpectedError;
    if (scenario == .capture_failed) return error.TestExpectedError;
    try std.testing.expect(published == null);
    try std.testing.expectEqual(@as(usize, 1), wire.calls);
    try std.testing.expectEqual(@as(usize, 1), probe.physical_sends);
    try std.testing.expectEqual(.exchange_finished, probe.boundary);
    try std.testing.expect(report.workflow_outcome != null and report.workflow_outcome.? != .ok);
    try std.testing.expect(report.terminal_rejection != null);
    try std.testing.expect(report.specification == null);
    try std.testing.expectEqual(.not_run, report.publication_check);
    try std.testing.expect(report.evaluation_inputs == null);
    // The probe terminates at invoke-model. Later production parsing, payload
    // validation and repairs must remain unexecuted even for invalid text.
    try std.testing.expect(report.model_diagnostic == null);
    try std.testing.expect(report.json_error == null);
    try std.testing.expect(report.schema_error == null);
    try std.testing.expect(report.last_protocol_rejection == null);
    try std.testing.expect(report.candidate_error == null);
    try std.testing.expectEqual(@as(usize, 0), report.repairs.len);
    try std.testing.expectEqual(@as(usize, 1), report.last_model_call.?);
    try std.testing.expectEqual(@as(usize, 1), report.model_calls);

    const has_usage = switch (scenario) {
        .complete, .empty_server_tool_usage_prefix, .noncandidate_stop, .schema_invalid, .malformed_candidate => true,
        .null_server_tool_usage, .array_server_tool_usage, .unknown_server_tool_usage, .unknown_usage, .cancelled, .partial_cancelled, .transport_failed, .partial_transport_failed, .missing_usage, .malformed_provider, .capture_failed => false,
    };
    try std.testing.expectEqual(has_usage, report.usage_complete);
    if (has_usage) {
        const recorded: @import("../../src/domain/llm_provider_operation.zig").ProviderUsage = if (scenario == .empty_server_tool_usage_prefix)
            .{ .input_tokens = 2106, .output_tokens = 148, .total_tokens = 2254 }
        else
            .{ .input_tokens = 10, .output_tokens = 2, .total_tokens = 12 };
        try std.testing.expectEqual(@as(u128, recorded.total_tokens), report.total_tokens);
        try std.testing.expectEqualDeep(recorded, report.last_model_usage.?);
        try std.testing.expectEqual(.cancelled, report.terminal_rejection.?.kind);
    } else {
        try std.testing.expectEqual(@as(u128, 0), report.total_tokens);
        try std.testing.expect(report.last_model_usage == null);
    }
    var config = try (@import("../../src/actions/config/decode_sddtoolkit_config.zig").Action{}).execute(a, captured.config);
    defer config.deinit();
    try absent(io, project, try std.fs.path.join(a, &.{ config.value().paths.specs, selected.feature, artifacts.specification_filename }));
    try absent(io, project, try std.fs.path.join(a, &.{ config.value().paths.workflows, "features", selected.feature, "state", artifacts.workflow_state_filename }));
    try fixture.verifySources(io, a, .cwd(), captured);

    var readback = try @import("../harness/call/capture.zig").load(io, a, temporary.dir, "run", selected.workflow_id, 1);
    defer readback.deinit();
    try std.testing.expectEqualStrings("openai.gpt-oss-20b-1:0", readback.context.common().model);
    try std.testing.expectEqualStrings("aws-bedrock", readback.context.current.provider);
    try std.testing.expectEqual(.@"ap-southeast-2", readback.context.current.provider_config.aws_bedrock.region);
    try std.testing.expectEqual(.inference, readback.context.common().kind);
    try std.testing.expectEqual(.native_schema, readback.context.common().response_mode);
    try std.testing.expect(readback.call.replay == null);
    try std.testing.expect(readback.call.request_complete);
    try std.testing.expect(readback.call.source_snapshot != null);
    try std.testing.expectEqualStrings(selected.workflow_id, readback.call.description.?.workflow_id);
    try std.testing.expect(std.mem.indexOf(u8, readback.call.request.?, "\"maxTokens\":16384") != null);
    try std.testing.expectEqualStrings("low", readback.call.description.?.reasoning_effort.?);
    try std.testing.expectEqual(.fixed, readback.call.description.?.controls.temperature.?);
    try std.testing.expect(std.mem.indexOf(u8, readback.call.request.?, key) == null);
    try std.testing.expectEqualDeep(digest(readback.call.request.?), probe.request_sha256.?);
    const actual_response: ?[]const u8 = switch (scenario) {
        .cancelled, .transport_failed => null,
        .partial_cancelled, .partial_transport_failed => response_prefix,
        .complete, .empty_server_tool_usage_prefix, .null_server_tool_usage, .array_server_tool_usage, .unknown_server_tool_usage, .unknown_usage, .missing_usage, .malformed_provider, .noncandidate_stop, .schema_invalid, .malformed_candidate => wire.inference_body,
        .capture_failed => unreachable,
    };
    if (actual_response) |bytes| {
        try std.testing.expectEqualDeep(digest(bytes), probe.response_sha256.?);
    } else {
        try std.testing.expect(probe.response_sha256 == null);
    }
    const request = try @import("../../src/domain/strict_json.zig").decode(std.json.Value, a, readback.call.request.?, .{ .maximum_depth = 64 });
    try std.testing.expect(request.object.contains("outputConfig"));
    const additional = request.object.get("additionalModelRequestFields").?.object;
    try std.testing.expectEqualStrings("low", additional.get("reasoning_effort").?.string);
    try std.testing.expect(!additional.contains("text"));
    try std.testing.expectEqual(@as(f64, 0.1), request.object.get("inferenceConfig").?.object.get("temperature").?.float);

    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const assessed = try inspection.inspect(io, a, &environment, temporary.dir, "run", selected.workflow_id, probe, report);
    const expected_status: inspection.Status = switch (scenario) {
        .complete => .compatible,
        .empty_server_tool_usage_prefix, .schema_invalid, .malformed_candidate, .noncandidate_stop => .incompatible,
        .null_server_tool_usage, .array_server_tool_usage, .unknown_server_tool_usage, .unknown_usage, .cancelled, .partial_cancelled, .transport_failed, .partial_transport_failed, .missing_usage, .malformed_provider, .capture_failed => .inconclusive,
    };
    try std.testing.expectEqual(expected_status, assessed.status);
    try std.testing.expect(assessed.request_identity != null);
    try std.testing.expectEqualDeep(readback.context.common().origin, assessed.request_identity.?.origin);
    try std.testing.expectEqualStrings(readback.call.id, assessed.request_identity.?.call);
    try std.testing.expectEqualStrings(readback.call.description.?.model, assessed.description.?.model);
    const request_hex = std.fmt.bytesToHex(probe.request_sha256.?, .lower);
    try std.testing.expectEqualStrings(&request_hex, assessed.request_sha256.?);
    if (probe.response_sha256) |hash| {
        const response_hex = std.fmt.bytesToHex(hash, .lower);
        try std.testing.expectEqualStrings(&response_hex, assessed.response_sha256.?);
    } else {
        try std.testing.expect(assessed.response_sha256 == null);
    }
    if (scenario != .cancelled and scenario != .partial_cancelled and scenario != .transport_failed and scenario != .partial_transport_failed) {
        try std.testing.expectEqual(@as(u16, 200), assessed.http_status.?);
        try std.testing.expectEqualStrings("MOCK-bedrock-request-id", assessed.provider_request_id.?);
    }
    try std.testing.expectEqual(@as(usize, 1), wire.calls); // Readback never sends.
    if (has_usage) {
        try std.testing.expectEqualDeep(report.last_model_usage.?, assessed.usage.?);
        try std.testing.expectEqualStrings(if (scenario == .noncandidate_stop) "max_tokens" else "end_turn", assessed.reported_stop.?);
        try std.testing.expectEqual(@as(usize, 1), assessed.validation.reasoning.len);
        if (scenario == .empty_server_tool_usage_prefix) {
            try std.testing.expectEqualStrings("We need a claim: business: start success, display Hello World, output date time UTC. Provide citations lines 5-7.", assessed.validation.reasoning[0].text.text);
            try std.testing.expect(assessed.validation.reasoning[0].text.signature == null);
        } else {
            try std.testing.expectEqualStrings("MOCK supplied reasoning", assessed.validation.reasoning[0].text.text);
            try std.testing.expectEqualStrings("MOCK opaque signature", assessed.validation.reasoning[0].text.signature.?);
        }
    }
    switch (scenario) {
        .complete => {
            try std.testing.expectEqual(.valid, assessed.validation.extraction);
            try std.testing.expectEqual(.valid, assessed.validation.json);
            try std.testing.expectEqual(.valid, assessed.validation.schema);
            try std.testing.expectEqualStrings(payload, assessed.validation.model_text.?);
            try std.testing.expect(std.mem.indexOf(u8, assessed.validation.model_text.?, "supplied reasoning") == null);
            try checkTampering(io, a, &environment, temporary.dir, run, selected.workflow_id, probe, report, readback.call);
        },
        .empty_server_tool_usage_prefix => {
            // The retained claims carry model wording, which ADR 0036 removed.
            try std.testing.expectEqual(.valid, assessed.validation.extraction);
            try std.testing.expectEqual(.valid, assessed.validation.json);
            try std.testing.expectEqual(.invalid, assessed.validation.schema);
            try std.testing.expectEqual(.removed_leading_brace_quote, assessed.validation.normalization);
            try std.testing.expect(std.mem.startsWith(u8, assessed.validation.model_text.?, "{\"{ "));
            try std.testing.expectEqualStrings("claims", assessed.validation.parsed.?.object.get("kind").?.string);
            try std.testing.expectEqual(@as(usize, 3), assessed.validation.parsed.?.object.get("claims").?.array.items.len);
        },
        .null_server_tool_usage, .array_server_tool_usage, .unknown_server_tool_usage, .unknown_usage => {
            const reason = switch (scenario) {
                .null_server_tool_usage, .array_server_tool_usage => "Expected provider response object",
                .unknown_server_tool_usage, .unknown_usage => "Unknown provider response field",
                else => unreachable,
            };
            const path = switch (scenario) {
                .null_server_tool_usage, .array_server_tool_usage => "/usage/serverToolUsage",
                .unknown_server_tool_usage => "/usage/serverToolUsage/unknown",
                .unknown_usage => "/usage/unknown",
                else => unreachable,
            };
            try std.testing.expect(assessed.usage == null);
            try std.testing.expectEqual(.invalid, assessed.validation.extraction);
            try std.testing.expectEqual(.unavailable, assessed.validation.json);
            try std.testing.expectEqual(.unavailable, assessed.validation.schema);
            try std.testing.expectEqualStrings(reason, assessed.reason.?);
            try std.testing.expectEqualStrings(reason, assessed.candidate_diagnostic.?);
            try std.testing.expectEqualStrings(reason, assessed.validation.reason.?);
            try std.testing.expectEqualStrings(path, assessed.validation.path.?);
        },
        .schema_invalid => {
            try std.testing.expectEqual(.valid, assessed.validation.json);
            try std.testing.expectEqual(.invalid, assessed.validation.schema);
        },
        .malformed_candidate => {
            try std.testing.expectEqual(.valid, assessed.validation.extraction);
            try std.testing.expectEqual(.invalid, assessed.validation.json);
        },
        .noncandidate_stop => {
            try std.testing.expectEqual(.invalid, assessed.validation.extraction);
            try std.testing.expectEqual(.unavailable, assessed.validation.json);
        },
        .missing_usage, .malformed_provider => try std.testing.expect(assessed.usage == null),
        .cancelled, .transport_failed => try std.testing.expect(assessed.response_file == null),
        .partial_cancelled, .partial_transport_failed => {
            try std.testing.expect(assessed.response_file != null);
            try std.testing.expectEqualStrings(response_prefix, try files.read(io, a, run, assessed.response_file.?));
            try std.testing.expectEqualStrings(response_prefix, readback.call.response.?);
            try std.testing.expectEqual(.unavailable, assessed.validation.extraction);
            try std.testing.expectEqual(.unavailable, assessed.validation.json);
            try std.testing.expectEqual(.unavailable, assessed.validation.schema);
            try std.testing.expect(assessed.usage == null);
        },
        .capture_failed => unreachable,
    }
    try retainOfflineReport(io, a, run, case_path, report, probe, assessed);
}

fn checkTampering(io: std.Io, a: std.mem.Allocator, environment: *const std.process.Environ.Map, root: std.Io.Dir, run: std.Io.Dir, workflow: []const u8, probe: invoke.Probe, report: contracts.Report, original: @import("../../src/domain/request_debugger.zig").Call) !void {
    const request_path = try evidence.Store.path(a, .generation, 1, .request);
    const response_path = try evidence.Store.path(a, .generation, 1, .response);
    const outcome_path = try evidence.Store.path(a, .generation, 1, .outcome);
    const outcome_bytes = try files.read(io, a, run, outcome_path);
    // Retained wire bytes cannot be substituted while keeping the native log's
    // identity, schema and prepared-request association.
    try run.writeFile(io, .{ .sub_path = request_path, .data = "{}" });
    try std.testing.expectError(error.CaptureMismatch, inspection.inspect(io, a, environment, root, "run", workflow, probe, report));
    try run.writeFile(io, .{ .sub_path = request_path, .data = original.request.? });
    try run.writeFile(io, .{ .sub_path = response_path, .data = "{}" });
    try std.testing.expectError(error.CaptureMismatch, inspection.inspect(io, a, environment, root, "run", workflow, probe, report));
    try run.writeFile(io, .{ .sub_path = response_path, .data = original.response.? });
    var foreign_origin = report;
    foreign_origin.last_model_origin.?.attempt.value += 1;
    try std.testing.expectError(error.CaptureMismatch, inspection.inspect(io, a, environment, root, "run", workflow, probe, foreign_origin));
    var foreign_usage = report;
    foreign_usage.last_model_usage.?.input_tokens += 1;
    foreign_usage.last_model_usage.?.total_tokens += 1;
    try std.testing.expectError(error.CaptureMismatch, inspection.inspect(io, a, environment, root, "run", workflow, probe, foreign_usage));
    var foreign_status = report;
    foreign_status.exchange_evidence.?.status = 201;
    try std.testing.expectError(error.CaptureMismatch, inspection.inspect(io, a, environment, root, "run", workflow, probe, foreign_status));
    var foreign_request_id = report;
    foreign_request_id.exchange_evidence.?.request_id = "MOCK-foreign-provider-request-id";
    try std.testing.expectError(error.CaptureMismatch, inspection.inspect(io, a, environment, root, "run", workflow, probe, foreign_request_id));
    var outcome = try @import("../harness/contracts.zig").decode(@import("../harness/e2e/trace.zig").TransportOutcome, a, outcome_bytes);
    outcome.received.status = 201;
    try run.writeFile(io, .{ .sub_path = outcome_path, .data = try std.json.Stringify.valueAlloc(a, outcome, .{}) });
    try std.testing.expectError(error.CaptureMismatch, inspection.inspect(io, a, environment, root, "run", workflow, probe, report));
    try run.writeFile(io, .{ .sub_path = outcome_path, .data = try std.fmt.allocPrint(a, "{{\"unexpected\":true,{s}", .{outcome_bytes[1..]}) });
    try std.testing.expectError(error.InvalidEvaluationContract, inspection.inspect(io, a, environment, root, "run", workflow, probe, report));
    try run.writeFile(io, .{ .sub_path = outcome_path, .data = outcome_bytes });
    var missing_request_proof = probe;
    missing_request_proof.request_sha256 = null;
    try std.testing.expectError(error.CaptureIncomplete, inspection.inspect(io, a, environment, root, "run", workflow, missing_request_proof, report));
    var wrong_request_proof = probe;
    var wrong_request_digest = probe.request_sha256.?;
    wrong_request_digest[0] ^= 1;
    wrong_request_proof.request_sha256 = wrong_request_digest;
    try std.testing.expectError(error.CaptureMismatch, inspection.inspect(io, a, environment, root, "run", workflow, wrong_request_proof, report));
    var missing_response_proof = probe;
    missing_response_proof.response_sha256 = null;
    try std.testing.expectError(error.CaptureIncomplete, inspection.inspect(io, a, environment, root, "run", workflow, missing_response_proof, report));
    var wrong_response_proof = probe;
    var wrong_response_digest = probe.response_sha256.?;
    wrong_response_digest[0] ^= 1;
    wrong_response_proof.response_sha256 = wrong_response_digest;
    try std.testing.expectError(error.CaptureMismatch, inspection.inspect(io, a, environment, root, "run", workflow, wrong_response_proof, report));
    try std.testing.expectEqual(.compatible, (try inspection.inspect(io, a, environment, root, "run", workflow, probe, report)).status);
}

fn retainOfflineReport(io: std.Io, a: std.mem.Allocator, run: std.Io.Dir, case_path: []const u8, workflow: contracts.Report, probe: invoke.Probe, assessed: inspection.Inspection) !void {
    const reports = @import("../harness/compatibility/report.zig");
    const output = try @import("../harness/e2e/report.zig").Output.reserve(io, run);
    defer output.close(io);
    var value: reports.Report = .{
        .origin = .offline,
        .started_at_utc = workflow.started_at_utc,
        .case_source = case_path,
        .execution_id = "MOCK-offline-probe",
        .status = switch (assessed.status) {
            .compatible => .compatible,
            .incompatible => .incompatible,
            .inconclusive => .inconclusive,
        },
        .diagnostic = assessed.reason,
        .inspection = assessed,
    };
    reports.applyExecution(&value, probe, workflow);
    try reports.save(io, a, output, value);
    const report_json = try files.read(io, a, run, "report.json");
    // Reports are output-only projections: they are never imported as typed
    // engine authority. Inspect their JSON without introducing a report reader.
    var parsed = try @import("../../src/domain/strict_json.zig").parse(a, report_json, .{ .maximum_depth = 64 }, false, null);
    defer parsed.deinit();
    const retained = parsed.value.object;
    try std.testing.expectEqualStrings("offline", retained.get("origin").?.string);
    try std.testing.expectEqualStrings("none", retained.get("authority").?.string);
    try std.testing.expectEqualStrings("not_authorized", retained.get("publication").?.string);
    try std.testing.expectEqualStrings("not_assessed", retained.get("semantic_quality").?.string);
    try std.testing.expectEqualStrings(@tagName(workflow.workflow_outcome.?), retained.get("workflow_outcome").?.string);
    try std.testing.expectEqualStrings("1", retained.get("physical_sends").?.number_string);
    try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "{d}", .{workflow.total_tokens}), retained.get("total_accounted_tokens").?.number_string);
    try std.testing.expectEqual(workflow.usage_complete, retained.get("usage_complete").?.bool);
    if (workflow.usage_complete) {
        try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "{d}", .{workflow.total_tokens}), retained.get("total_actual_tokens").?.number_string);
    } else {
        try std.testing.expect(retained.get("total_actual_tokens").? == .null);
    }
    if (assessed.reason) |reason| {
        try std.testing.expectEqualStrings(reason, retained.get("diagnostic").?.string);
    } else {
        try std.testing.expect(retained.get("diagnostic").? == .null);
    }
    const projected = retained.get("inspection").?.object;
    try std.testing.expectEqualStrings(assessed.request_identity.?.call, projected.get("request_identity").?.object.get("call").?.string);
    try std.testing.expectEqualStrings(assessed.description.?.model, projected.get("description").?.object.get("model").?.string);
    try std.testing.expectEqualStrings(assessed.request_sha256.?, projected.get("request_sha256").?.string);
    if (assessed.response_sha256) |hash| {
        try std.testing.expectEqualStrings(hash, projected.get("response_sha256").?.string);
    } else {
        try std.testing.expect(projected.get("response_sha256").? == .null);
    }
    if (assessed.reported_stop) |stop| {
        try std.testing.expectEqualStrings(stop, projected.get("reported_stop").?.string);
    } else {
        try std.testing.expect(projected.get("reported_stop").? == .null);
    }
    const validation = projected.get("validation").?.object;
    try std.testing.expectEqual(assessed.validation.reasoning.len, validation.get("reasoning").?.array.items.len);
    if (assessed.validation.reason) |reason| try std.testing.expectEqualStrings(reason, validation.get("reason").?.string);
    if (assessed.validation.path) |path| try std.testing.expectEqualStrings(path, validation.get("path").?.string);
    try std.testing.expect(std.mem.indexOf(u8, try files.read(io, a, run, "report.md"), "no publication or workflow-completion authority") != null);
}

test "test.integration.provider_compatibility frozen protocol production requests stop after one accounted exchange in unrelated domains" {
    for (cases) |case_path| try runScenario(case_path, .complete);
}

test "test.integration.provider_compatibility drifted slot controls cannot substitute for the frozen protocol before send" {
    for (cases) |case_path| try runScenarioWithBinding(case_path, .complete, .drifted_protocol);
}

test "test.integration.provider_compatibility empty server tool metadata retains exact usage and shared prefix normalization in unrelated domains" {
    // This retained provider body exercises usage and prefix normalization only.
    // Its claims predate ADR 0036, so the current schema rejects them.
    for (cases) |case_path| try runScenario(case_path, .empty_server_tool_usage_prefix);
}

test "test.integration.provider_compatibility malformed server tool metadata and unknown usage retain precise rejection without token authority" {
    for (cases) |case_path| {
        for ([_]Scenario{ .null_server_tool_usage, .array_server_tool_usage, .unknown_server_tool_usage, .unknown_usage }) |scenario| try runScenario(case_path, scenario);
    }
}

test "test.integration.provider_compatibility cancellation and uncertain transport failure cannot retry or publish" {
    for (cases) |case_path| {
        for ([_]Scenario{ .cancelled, .partial_cancelled, .transport_failed, .partial_transport_failed }) |scenario| try runScenario(case_path, scenario);
    }
}

test "test.integration.provider_compatibility failed request capture prevents the first physical send" {
    for (cases) |case_path| try runScenario(case_path, .capture_failed);
}

test "test.integration.provider_compatibility missing usage malformed responses stops and invalid candidates remain diagnostic" {
    for (cases) |case_path| {
        for ([_]Scenario{ .missing_usage, .malformed_provider, .noncandidate_stop, .schema_invalid, .malformed_candidate }) |scenario| try runScenario(case_path, scenario);
    }
}

const ExperimentScenario = enum { known_usage, missing_usage, uncertain_delivery, native_budget_stop, capture_failure };

fn runExperimentCase(case_path: []const u8, scenario: ExperimentScenario) !void {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(io, "project");
    const project = try temporary.dir.openDir(io, "project", .{});
    defer project.close(io);
    const selected = try @import("frozen_protocol_fixture.zig").select(a, try contracts.parse(a, try files.read(io, a, .cwd(), case_path)));
    const captured = try fixture.capture(io, a, .cwd(), selected);
    try fixture.materialize(io, project, captured);
    var gate = try @import("../harness/baseline/dispatch.zig").Gate.init(.{ .maximum_sends = 1, .maximum_actual_tokens = 2_000_000 });
    var log = @import("../harness/e2e/trace.zig").CaptureLog.init(a);
    defer log.deinit();
    const normal_body = try body(a, if (scenario == .missing_usage) .missing_usage else .complete);
    const response = if (scenario == .native_budget_stop)
        try std.mem.replaceOwned(u8, a, normal_body, "\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12", "\"inputTokens\":100000,\"outputTokens\":1,\"totalTokens\":100001")
    else
        normal_body;
    var wire: @import("../../src/model_transport_test_fixture.zig").Wire = .{ .expected_json = true, .inference_body = response };
    wire.result = if (scenario == .uncertain_delivery) .{ .failed = .{
        .cause = .transport_failed,
        .retry_class = .policy_eligible,
        .delivery = .accepted_or_unknown,
    } } else .{ .received = .{ .status = 200, .body = response } };
    const store: evidence.Store = .{ .io = io, .allocator = a, .run = temporary.dir, .secrets = &.{key} };
    var report: contracts.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "2026-10-16T00:00:00Z", .status = .input_invalid };
    if (scenario == .capture_failure) try temporary.dir.createDirPath(io, try evidence.Store.path(a, .generation, 1, .context));
    const published = invoke.run(io, a, project, selected, captured, @import("../harness/environment.zig").bedrockOnly(key), store, &report, .{
        .purpose = .whole_workflow,
        .experiment = &gate,
        .capture = &log,
        .transport = wire.port(),
    }) catch |err| {
        if (scenario != .capture_failure) return err;
        try std.testing.expectEqual(error.EvidenceCaptureFailed, err);
        try std.testing.expectEqual(@as(usize, 0), wire.calls);
        try std.testing.expectEqual(@as(u64, 0), gate.snapshot().physical_sends);
        try std.testing.expectEqual(@as(usize, 0), log.records.items.len);
        try std.testing.expectEqual(@as(?@import("../harness/baseline/dispatch.zig").Reason, .evidence_failure), gate.snapshot().halt_reason);
        return;
    };
    if (scenario == .capture_failure) return error.TestExpectedError;
    try std.testing.expect(published == null);
    try std.testing.expectEqual(@as(usize, 1), wire.calls);
    try std.testing.expectEqual(@as(u64, 1), gate.snapshot().physical_sends);
    try std.testing.expectEqual(@as(u64, 1), gate.snapshot().reconciled_sends);
    try std.testing.expectEqual(@as(usize, 1), log.records.items.len);
    try std.testing.expectError(error.ExperimentHalted, gate.beforeSend());
    try std.testing.expect(report.workflow_outcome != .ok and report.specification == null);
    try std.testing.expect(report.evaluation_inputs == null);
    const receipt = log.records.items[0];
    try std.testing.expectEqual(@as(usize, 1), receipt.call);
    try std.testing.expectEqual(@as(u64, 1), receipt.experiment_send.?.ordinal);
    try std.testing.expectEqualDeep(report.last_model_origin.?, receipt.origin);
    const raw_context = try files.read(io, a, temporary.dir, try evidence.Store.path(a, .generation, 1, .context));
    const raw_request = try files.read(io, a, temporary.dir, try evidence.Store.path(a, .generation, 1, .request));
    try std.testing.expectEqualDeep(digest(raw_context), receipt.context_sha256);
    try std.testing.expectEqualDeep(digest(raw_request), receipt.request_sha256);
    const known = scenario == .known_usage or scenario == .native_budget_stop;
    try std.testing.expectEqual(known, gate.snapshot().usage_complete);
    if (known) {
        const tokens: u128 = if (scenario == .native_budget_stop) 100001 else 12;
        try std.testing.expectEqual(@as(?u128, tokens), gate.snapshot().total_actual_tokens);
        try std.testing.expectEqual(tokens, report.total_tokens);
        try std.testing.expectEqualDeep(report.last_model_usage, receipt.usage);
        if (scenario == .native_budget_stop) try std.testing.expectEqual(.token_budget, report.terminal_rejection.?.kind);
    } else {
        try std.testing.expect(gate.snapshot().total_actual_tokens == null);
        try std.testing.expect(receipt.usage == null);
    }
    try std.testing.expectEqual(scenario == .uncertain_delivery, receipt.uncertain_delivery);
    if (scenario != .uncertain_delivery) {
        const raw_response = try files.read(io, a, temporary.dir, try evidence.Store.path(a, .generation, 1, .response));
        try std.testing.expectEqualStrings(response, raw_response);
        try std.testing.expectEqualDeep(digest(response), receipt.response_sha256.?);
        try std.testing.expect(receipt.raw_response_available);
    }
    if (scenario == .known_usage) {
        const raw_output = try files.read(io, a, temporary.dir, try evidence.Store.path(a, .generation, 1, .model_output));
        try std.testing.expectEqualStrings(payload, raw_output);
        try std.testing.expectEqualDeep(digest(raw_output), receipt.model_output_sha256.?);
        try std.testing.expect(receipt.model_output_available);
    }
    try fixture.verifySources(io, a, .cwd(), captured);
}

test "test.integration.provider_compatibility experiment gate retains authentic-boundary receipts and native accounting before stops" {
    for (cases) |case_path| for ([_]ExperimentScenario{ .known_usage, .missing_usage, .uncertain_delivery, .native_budget_stop, .capture_failure }) |scenario| {
        try runExperimentCase(case_path, scenario);
    };
}
