const std = @import("std");
const capture = @import("capture.zig");
const debug = @import("../../../src/domain/request_debugger.zig");
const context_contract = @import("../e2e/call_context.zig");
const Context = context_contract.CallContext;
const format = @import("../../../src/domain/feature_log_format.zig");
const body = "{\"MOCK\":\"captured wire body\"}";
const description: debug.Description = .{
    .provider = "aws-bedrock",
    .model = "MOCK-model",
    .provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .family = .@"gpt-oss", .max_output_tokens = .{ .tokens = 16000 }, .request_timeout = .{ .milliseconds = 180000 } } },
    .model_slot = "sample-slot",
    .workflow_id = "sample-workflow",
    .workflow_version = 3,
    .request_step = "prepare-sample",
    .content = &.{ .{ .guidance = "MOCK guidance" }, .{ .user = "MOCK request" } },
    .protocol_prompt = @import("../../../src/domain/model_controls.zig").response_format_guidance,
    .schema = "{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":false}",
    .response_mode = .prompt_only,
    .controls = .{ .temperatures = @import("../../../src/test_fixtures/model_temperatures.zig").temperatures },
    .reasoning_effort = "low",
    .operation_kind = .inference,
};
const current: Context = .{
    .schema = .@"model-call-evidence/v3",
    .call = 9,
    .origin = .{ .request = .{ .value = 72 }, .attempt = .{ .value = 3 } },
    .request_step = description.request_step,
    .slot = description.model_slot,
    .attempt = 3,
    .provider = description.provider,
    .model = description.model,
    .provider_config = description.provider_config,
    .kind = .inference,
    .reasoning_effort = description.reasoning_effort,
    .content = description.content,
    .response_schema = description.schema,
    .response_mode = description.response_mode,
};
const context: context_contract.Captured = .{ .current = current };
const call: debug.Call = .{
    .run = "MOCK-run",
    .sequence = 201,
    .execution_order = 1,
    .id = "request-72-inference-3",
    .workflow = description.workflow_id,
    .action = "invoke-model",
    .node = "invoke-sample",
    .request_step = description.request_step,
    .slot = description.model_slot,
    .kind = "initial",
    .original = "request-72-inference-3",
    .parent = null,
    .description = description,
    .request = body,
    .request_complete = true,
};

test "capture selection joins canonical identity independently of physical ordinal and log sequence" {
    var other = call;
    other.id = "request-0-inference-1";
    other.sequence = 9;
    const selected = try capture.select(&.{ other, call }, context, description.workflow_id, 9, body);
    try std.testing.expectEqualStrings(call.id, selected.id);
    try std.testing.expectEqual(@as(u64, 201), selected.sequence);
    try std.testing.expectEqualDeep(description.controls, selected.description.?.controls);
    try std.testing.expect(selected.source_snapshot == null);
    for ([_][]const u8{ "review-document", "another-generic-workflow" }) |workflow| {
        var representative = call;
        representative.workflow = workflow;
        representative.description.?.workflow_id = workflow;
        try std.testing.expectEqualStrings(workflow, (try capture.select(&.{representative}, context, workflow, 9, body)).workflow);
    }
}

test "capture selection rejects missing and duplicate execution-local identities before comparing bytes" {
    try std.testing.expectError(error.CaptureMissing, capture.select(&.{}, context, description.workflow_id, 9, body));
    var duplicate = call;
    duplicate.run = "another-MOCK-run";
    duplicate.request = "different wire bytes";
    try std.testing.expectError(error.CaptureAmbiguous, capture.select(&.{ call, duplicate }, context, description.workflow_id, 9, body));
    duplicate.workflow = "other-workflow";
    try std.testing.expectEqualStrings(call.run, (try capture.select(&.{ duplicate, call }, context, description.workflow_id, 9, body)).run);
    try std.testing.expectError(error.CaptureMismatch, capture.select(&.{call}, context, description.workflow_id, 201, body));
}

test "capture selection rejects incomplete redacted and replay records" {
    inline for (.{ "request_complete", "request", "description" }) |field| {
        var invalid = call;
        if (comptime std.mem.eql(u8, field, "request_complete")) invalid.request_complete = false else @field(invalid, field) = null;
        try std.testing.expectError(error.CaptureIncomplete, capture.select(&.{invalid}, context, description.workflow_id, 9, body));
    }
    var invalid = call;
    invalid.redacted = true;
    try std.testing.expectError(error.CaptureRedacted, capture.select(&.{invalid}, context, description.workflow_id, 9, body));
    invalid = call;
    invalid.replay = .exact;
    try std.testing.expectError(error.CaptureMismatch, capture.select(&.{invalid}, context, description.workflow_id, 9, body));
}

test "capture selection compares all recorded context fields and exact request bytes" {
    inline for (.{ "request_step", "slot", "model", "reasoning_effort", "response_schema" }) |field| {
        var mismatch = current;
        @field(mismatch, field) = "MOCK-mismatch";
        try std.testing.expectError(error.CaptureMismatch, capture.select(&.{call}, .{ .current = mismatch }, description.workflow_id, 9, body));
    }
    inline for (.{ "request_step", "model_slot", "model", "workflow_id", "schema", "reasoning_effort" }) |field| {
        var mismatch = call;
        @field(mismatch.description.?, field) = "MOCK-mismatch";
        try std.testing.expectError(error.CaptureMismatch, capture.select(&.{mismatch}, context, description.workflow_id, 9, body));
    }
    var mismatch = current;
    mismatch.content = &.{ .{ .guidance = "different MOCK guidance" }, .{ .user = "MOCK request" } };
    try std.testing.expectError(error.CaptureMismatch, capture.select(&.{call}, .{ .current = mismatch }, description.workflow_id, 9, body));
    mismatch.content = &.{ .{ .user = "MOCK guidance" }, .{ .user = "MOCK request" } };
    try std.testing.expectError(error.CaptureMismatch, capture.select(&.{call}, .{ .current = mismatch }, description.workflow_id, 9, body));
    mismatch = current;
    mismatch.provider_config = .{ .aws_bedrock = .{ .region = .@"us-west-2", .family = .@"gpt-oss", .max_output_tokens = .{ .tokens = 16000 }, .request_timeout = .{ .milliseconds = 180000 } } };
    try std.testing.expectError(error.CaptureMismatch, capture.select(&.{call}, .{ .current = mismatch }, description.workflow_id, 9, body));
    mismatch = current;
    mismatch.provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .family = .@"gpt-oss", .max_output_tokens = .{ .tokens = 4096 }, .request_timeout = .{ .milliseconds = 180000 } } };
    try std.testing.expectError(error.CaptureMismatch, capture.select(&.{call}, .{ .current = mismatch }, description.workflow_id, 9, body));
    mismatch = current;
    mismatch.provider = "anthropic";
    mismatch.provider_config = .{ .anthropic = .{ .max_output_tokens = .{ .tokens = 16000 }, .request_timeout = .{ .milliseconds = 180000 } } };
    try std.testing.expectError(error.CaptureMismatch, capture.select(&.{call}, .{ .current = mismatch }, description.workflow_id, 9, body));
    mismatch = current;
    mismatch.response_mode = .native_schema;
    try std.testing.expectError(error.CaptureMismatch, capture.select(&.{call}, .{ .current = mismatch }, description.workflow_id, 9, body));
    try std.testing.expectError(error.CaptureMismatch, capture.select(&.{call}, context, description.workflow_id, 9, body ++ " "));
}

test "capture preserves source evidence and rejects foreign node or redacted source snapshots" {
    const Snapshot = @import("../../../src/domain/request_source_snapshot.zig").Snapshot;
    const snapshot: Snapshot = .{
        .workflow = description.workflow_id,
        .document = .{ .path = "sample/workflow.yaml", .content = "MOCK workflow", .redacted = false },
        .caller = .{ .step = call.node, .chain = &.{.{ .subgraph = null, .id = "invoke", .kind = .operation, .target = call.action, .declaration = "MOCK invocation" }} },
        .preparation = .{ .step = description.request_step, .chain = &.{.{ .subgraph = null, .id = "prepare", .kind = .operation, .target = "prepare-model-request", .declaration = "MOCK preparation" }} },
        .resources = &.{
            .{ .role = .prompt, .alias = "prompt", .kind = .prompt, .document = .{ .path = "sample/prompt.md", .content = "MOCK prompt", .redacted = false } },
            .{ .role = .result, .alias = "result", .kind = .result_schema, .document = .{ .path = "sample/result.json", .content = description.schema, .redacted = false } },
        },
        .selection = .{ .definition = null, .part = null, .paths = &.{} },
    };
    try snapshot.validate();
    var source = call;
    source.source_snapshot = snapshot;
    try std.testing.expectEqualDeep(snapshot, (try capture.select(&.{source}, context, description.workflow_id, 9, body)).source_snapshot.?);
    source.source_snapshot.?.caller.step = "foreign-node";
    try std.testing.expectError(error.CaptureMismatch, capture.select(&.{source}, context, description.workflow_id, 9, body));
    source.source_snapshot = snapshot;
    source.source_snapshot.?.document.redacted = true;
    try std.testing.expectError(error.CaptureRedacted, capture.select(&.{source}, context, description.workflow_id, 9, body));
}

test "shared context retains v3 wire shape and rejects unknown version fields and inconsistent origin" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try std.json.Stringify.valueAlloc(a, current, .{});
    try std.testing.expectEqualDeep(current, try Context.decode(a, bytes));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"schema\":\"model-call-evidence/v3\"") != null);
    // The current shape records the catalogue entry's deadline.
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"request_timeout\":180000") != null);
    for ([_][2][]const u8{
        .{ "model-call-evidence/v3", "model-call-evidence/v2" },
        .{ "model-call-evidence/v3", "model-call-evidence/v4" },
        .{ ",\"request_timeout\":180000", "" },
        .{ "\"request_timeout\":180000", "\"request_timeout\":0" },
        .{ "\"request_timeout\":180000", "\"request_timeout\":\"180000\"" },
        .{ "\"call\":9", "\"call\":9,\"extra\":true" },
        .{ "\"call\":9", "\"call\":9,\"call\":10" },
    }) |change| {
        try std.testing.expectError(error.InvalidJsonDocument, Context.decode(a, try std.mem.replaceOwned(u8, a, bytes, change[0], change[1])));
    }
    for ([_][2][]const u8{
        .{ "\"call\":9", "\"call\":0" },
        .{ "\"attempt\":3", "\"attempt\":2" },
        .{ "prepare-sample", "../outside" },
        // A configuration of one family cannot accompany another provider.
        .{ "\"provider\":\"aws-bedrock\"", "\"provider\":\"anthropic\"" },
    }) |change| {
        try std.testing.expectError(error.InvalidCallContext, Context.decode(a, try std.mem.replaceOwned(u8, a, bytes, change[0], change[1])));
    }
}

test "captured contexts dispatch on their exact schema and keep v2 and v1 as historical evidence" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const current_bytes = try std.json.Stringify.valueAlloc(a, current, .{});
    const decoded = try context_contract.Captured.decode(a, current_bytes);
    try std.testing.expect(decoded == .current);
    try std.testing.expect(decoded.recordsConfig(description.provider, description.provider_config));
    try std.testing.expect(!decoded.recordsConfig(description.provider, .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .family = .@"gpt-oss", .max_output_tokens = .{ .tokens = 4096 }, .request_timeout = .{ .milliseconds = 180000 } } }));
    // A current capture records the deadline too.
    try std.testing.expect(!decoded.recordsConfig(description.provider, .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .family = .@"gpt-oss", .max_output_tokens = .{ .tokens = 16000 }, .request_timeout = .{ .milliseconds = 60000 } } }));

    // A v2 capture keeps its own closed configuration, recorded before the deadline.
    const v2: context_contract.HistoricalCallContextV2 = .{
        .schema = .@"model-call-evidence/v2",
        .call = current.call,
        .origin = current.origin,
        .request_step = current.request_step,
        .slot = current.slot,
        .attempt = current.attempt,
        .provider = current.provider,
        .model = current.model,
        .provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .family = .@"gpt-oss", .max_output_tokens = .{ .tokens = 16000 } } },
        .kind = current.kind,
        .reasoning_effort = current.reasoning_effort,
        .content = current.content,
        .response_schema = current.response_schema,
        .response_mode = current.response_mode,
    };
    const v2_bytes = try std.json.Stringify.valueAlloc(a, v2, .{});
    try std.testing.expect(std.mem.indexOf(u8, v2_bytes, "request_timeout") == null);
    const previous = try context_contract.Captured.decode(a, v2_bytes);
    try std.testing.expect(previous == .historical_v2);
    try std.testing.expectEqualDeep(decoded.common(), previous.common());
    // It records every configuration value except the deadline it predates.
    try std.testing.expect(previous.recordsConfig(description.provider, description.provider_config));
    try std.testing.expect(previous.recordsConfig(description.provider, .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .family = .@"gpt-oss", .max_output_tokens = .{ .tokens = 16000 }, .request_timeout = .{ .milliseconds = 60000 } } }));
    try std.testing.expect(!previous.recordsConfig(description.provider, .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .family = .@"gpt-oss", .max_output_tokens = .{ .tokens = 4096 }, .request_timeout = .{ .milliseconds = 180000 } } }));
    try std.testing.expect(!previous.recordsConfig(description.provider, .{ .aws_bedrock = .{ .region = .@"us-west-2", .family = .@"gpt-oss", .max_output_tokens = .{ .tokens = 16000 }, .request_timeout = .{ .milliseconds = 180000 } } }));
    try std.testing.expect(!previous.recordsConfig(description.provider, .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .family = .converse, .max_output_tokens = .{ .tokens = 16000 }, .request_timeout = .{ .milliseconds = 180000 } } }));
    try std.testing.expect(!previous.recordsConfig("anthropic", .{ .anthropic = .{ .max_output_tokens = .{ .tokens = 16000 }, .request_timeout = .{ .milliseconds = 180000 } } }));
    // An Anthropic v2 capture records its maximum and names its own provider.
    var anthropic_v2 = v2;
    anthropic_v2.provider = "anthropic";
    anthropic_v2.provider_config = .{ .anthropic = .{ .max_output_tokens = .{ .tokens = 128000 } } };
    const anthropic_v2_bytes = try std.json.Stringify.valueAlloc(a, anthropic_v2, .{});
    const anthropic_previous = try context_contract.Captured.decode(a, anthropic_v2_bytes);
    try std.testing.expect(anthropic_previous.recordsConfig("anthropic", .{ .anthropic = .{ .max_output_tokens = .{ .tokens = 128000 }, .request_timeout = .{ .milliseconds = 180000 } } }));
    try std.testing.expect(!anthropic_previous.recordsConfig("aws-bedrock", .{ .anthropic = .{ .max_output_tokens = .{ .tokens = 128000 }, .request_timeout = .{ .milliseconds = 180000 } } }));
    for ([_][2][]const u8{
        // The v2 shape is closed: it never carries the deadline it predates,
        // nor the test-only family, nor another provider's identity.
        .{ "\"max_output_tokens\":16000}", "\"max_output_tokens\":16000,\"request_timeout\":180000}" },
        .{ "\"call\":9", "\"call\":9,\"extra\":true" },
    }) |change| {
        const rejected = try std.mem.replaceOwned(u8, a, v2_bytes, change[0], change[1]);
        try std.testing.expect(!std.mem.eql(u8, rejected, v2_bytes));
        try std.testing.expectError(error.InvalidJsonDocument, context_contract.Captured.decode(a, rejected));
    }
    try std.testing.expectError(error.InvalidJsonDocument, context_contract.Captured.decode(a, try std.mem.replaceOwned(u8, a, v2_bytes, "{\"aws_bedrock\":{\"region\":\"ap-southeast-2\",\"family\":\"gpt-oss\",\"max_output_tokens\":16000}}", "{\"deadline_only\":{}}")));
    try std.testing.expectError(error.InvalidCallContext, context_contract.Captured.decode(a, try std.mem.replaceOwned(u8, a, v2_bytes, "\"provider\":\"aws-bedrock\"", "\"provider\":\"anthropic\"")));
    try std.testing.expectError(error.InvalidCallContext, context_contract.Captured.decode(a, try std.mem.replaceOwned(u8, a, v2_bytes, "\"call\":9", "\"call\":0")));
    // A v2 body labelled v3, and a v3 body labelled v2, reject.
    try std.testing.expectError(error.InvalidJsonDocument, context_contract.Captured.decode(a, try std.mem.replaceOwned(u8, a, v2_bytes, "model-call-evidence/v2", "model-call-evidence/v3")));
    try std.testing.expectError(error.InvalidJsonDocument, context_contract.Captured.decode(a, try std.mem.replaceOwned(u8, a, current_bytes, "model-call-evidence/v3", "model-call-evidence/v2")));
    const historical: context_contract.HistoricalCallContextV1 = .{
        .schema = .@"model-call-evidence/v1",
        .call = current.call,
        .origin = current.origin,
        .request_step = current.request_step,
        .slot = current.slot,
        .attempt = current.attempt,
        .model = current.model,
        .region = .@"ap-southeast-2",
        .kind = current.kind,
        .reasoning_effort = current.reasoning_effort,
        .content = current.content,
        .response_schema = current.response_schema,
        .response_mode = current.response_mode,
    };
    const historical_bytes = try std.json.Stringify.valueAlloc(a, historical, .{});
    const old = try context_contract.Captured.decode(a, historical_bytes);
    try std.testing.expect(old == .historical_v1);
    try std.testing.expectEqualDeep(decoded.common(), old.common());
    // A v1 capture records only a Bedrock region.
    try std.testing.expect(old.recordsConfig("aws-bedrock", description.provider_config));
    try std.testing.expect(!old.recordsConfig("aws-bedrock", .{ .aws_bedrock = .{ .region = .@"us-west-2", .family = .@"gpt-oss", .max_output_tokens = .{ .tokens = 16000 }, .request_timeout = .{ .milliseconds = 180000 } } }));
    try std.testing.expect(!old.recordsConfig("anthropic", .{ .anthropic = .{ .max_output_tokens = .{ .tokens = 16000 }, .request_timeout = .{ .milliseconds = 180000 } } }));
    // Unknown versions and a v1 body labelled v2 or v3 reject.
    try std.testing.expectError(error.InvalidCallContext, context_contract.Captured.decode(a, try std.mem.replaceOwned(u8, a, current_bytes, "model-call-evidence/v3", "model-call-evidence/v9")));
    try std.testing.expectError(error.InvalidJsonDocument, context_contract.Captured.decode(a, try std.mem.replaceOwned(u8, a, historical_bytes, "model-call-evidence/v1", "model-call-evidence/v2")));
    try std.testing.expectError(error.InvalidJsonDocument, context_contract.Captured.decode(a, try std.mem.replaceOwned(u8, a, historical_bytes, "model-call-evidence/v1", "model-call-evidence/v3")));
}

const config_bytes =
    \\{"logs":{"level":"debug","console":false},"workflowTokenBudget":100000,"temperature":0.1,"temperatureRunawayRetry":1,"models":{"slots":{"sample-slot":{"provider":"aws-bedrock","model":"MOCK-model","reasoningEffort":"low"}}},"paths":{"specs":"documents/","references":"references","specsArchive":"documents/archive","workflows":"workflow-definitions","toolchainPreset":"presets","principles":"principles","templates":"templates","providers":"settings/.sddproviders.json"}}
;
const run_path = "runs/unrelated-run";
const provider_bytes = "MOCK provider catalogue read without workflow execution";
const case_bytes =
    \\{"schema":"spec-e2e-case/v3","id":"MOCK-case","expected_outcome":"publication","workflow_id":"sample-workflow","feature":"nested/feature","reference":"selected","config":"fixture/config.json","evaluation_case":"fixture/evaluation.json","directories":[],"files":[{"source":"fixture/input.md","destination":"references/input.md"}],"expected_artifacts":["specification","reference_context","clarification_state","workflow_state"]}
;

const Sink = struct {
    allocator: std.mem.Allocator,
    rows: std.ArrayList(u8) = .empty,
    sequence: u64 = 200,
    fn barrier(self: *Sink) @import("../../../src/ports/telemetry_barrier.zig").Barrier {
        return .{ .context = self, .process_fn = event, .select_prompt_fn = selected, .process_prompt_fn = prompt };
    }
    fn event(_: *anyopaque, _: @import("../../../src/domain/telemetry.zig").WorkflowTelemetryFact) @import("../../../src/domain/feature_log_stream.zig").Outcome {
        return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
    }
    fn selected(_: *anyopaque, _: @import("../../../src/domain/sanitized_prompt_log.zig").SanitizedPromptFragment) bool {
        return true;
    }
    fn prompt(pointer: *anyopaque, fragment: @import("../../../src/domain/sanitized_prompt_log.zig").SanitizedPromptFragment) @import("../../../src/domain/feature_log_stream.zig").Outcome {
        const self: *Sink = @ptrCast(@alignCast(pointer));
        self.sequence += 1;
        const bytes = format.serializePrompt(self.allocator, .{
            .log_policy_id = .{ .bytes = "MOCK-policy" },
            .binding_id = .{ .bytes = "MOCK-binding" },
            .segment_ordinal = 1,
            .event_id = .{ .bytes = "MOCK-event" },
            .sequence = self.sequence,
            .occurred_at_utc = "2026-09-20T00:00:00Z",
            .monotonic_offset = 1,
            .run_id = .{ .bytes = call.run },
            .feature_id = .{ .bytes = "nested/feature" },
            .fragment = fragment,
        }) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        self.rows.appendSlice(self.allocator, bytes) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        return .{ .persisted = .{ .sequence = self.sequence, .segment_ordinal = 1, .bytes_written = bytes.len, .flushed = true } };
    }
};

fn write(root: std.Io.Dir, path: []const u8, bytes: []const u8) !void {
    const io = std.testing.io;
    if (std.fs.path.dirname(path)) |parent| try root.createDirPath(io, parent);
    try root.writeFile(io, .{ .sub_path = path, .data = bytes });
}

fn fixture(a: std.mem.Allocator, root: std.Io.Dir) !void {
    try write(root, run_path ++ "/case.json", case_bytes);
    try write(root, run_path ++ "/project/.sddtoolkit.json", config_bytes);
    try write(root, run_path ++ "/project/settings/.sddproviders.json", provider_bytes);
    try write(root, run_path ++ "/evidence/generation/call-000009/context.json", try std.json.Stringify.valueAlloc(a, current, .{}));
    try write(root, run_path ++ "/evidence/generation/call-000009/request.json", body);
    var sink: Sink = .{ .allocator = a };
    try sink.rows.appendSlice(a, format.prompt_heading);
    var logger: @import("../../../src/application/model_exchange_capture.zig").Capture = .{ .allocator = a, .logs = sink.barrier() };
    defer logger.deinit();
    logger.begin(.{
        .workflow = try @import("../../../src/domain/telemetry.zig").WorkflowShortcode.parse("MOCK"),
        .workflow_id = .{ .bytes = description.workflow_id },
        .node = .{ .bytes = call.node },
        .action = .{ .bytes = call.action },
        .operation = .{ .bytes = description.request_step },
        .model_slot = .{ .bytes = description.model_slot },
        .origin = current.origin,
        .description = description,
    });
    defer logger.end();
    try std.testing.expectEqual(.recorded, logger.port().capture(.request, .{ .provider_body = body }, &.{}));
    try write(root, run_path ++ "/project/documents/nested/feature/logs/prompts/MOCK-run/binding/0001.log", sink.rows.items);
}

test "capture loads configured feature and provider locations and preserves request ownership" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var root = std.testing.tmpDir(.{});
    defer root.cleanup();
    try fixture(arena.allocator(), root.dir);
    var loaded = try capture.load(std.testing.io, std.testing.allocator, root.dir, run_path, description.workflow_id, 9);
    defer loaded.deinit();
    try std.testing.expectEqualStrings(body, loaded.call.request.?);
    try std.testing.expectEqualStrings(provider_bytes, loaded.provider_catalogue);
    try std.testing.expectEqualStrings("documents/nested/feature", loaded.feature_path);
    try std.testing.expectEqualStrings(run_path ++ "/evidence/generation/call-000009/context.json", loaded.context_path);
    try std.testing.expectEqualStrings("settings/.sddproviders.json", loaded.config.paths.providers);
    try std.testing.expectEqualStrings("low", loaded.config.models.slots.map.get("sample-slot").?.reasoningEffort.?);
    try std.testing.expectEqual(@as(f64, 0.1), loaded.call.description.?.controls.temperature(.configured).?.value);
    try std.testing.expectError(error.CapturedWorkflowMismatch, capture.load(std.testing.io, std.testing.allocator, root.dir, run_path, "different-workflow", 9));
    try std.testing.expectError(error.InputUnavailable, capture.load(std.testing.io, std.testing.allocator, root.dir, run_path, description.workflow_id, 1));
}

test "capture input paths reject traversal configured escape and symlinked evidence" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = std.testing.tmpDir(.{});
    defer root.cleanup();
    const io = std.testing.io;
    try fixture(a, root.dir);
    for ([_][]const u8{ "../unrelated-run", "/unrelated-run", "runs/%2e%2e/outside", "runs//unrelated-run" }) |path| {
        try std.testing.expectError(error.InvalidEvaluationContract, capture.load(io, std.testing.allocator, root.dir, path, description.workflow_id, 9));
    }
    for ([_][2][]const u8{ .{ "documents/", "../outside" }, .{ "settings/.sddproviders.json", "../.sddproviders.json" } }) |replacement| {
        try write(root.dir, run_path ++ "/project/.sddtoolkit.json", try std.mem.replaceOwned(u8, a, config_bytes, replacement[0], replacement[1]));
        try std.testing.expectError(error.BootstrapRootResolutionError, capture.load(io, std.testing.allocator, root.dir, run_path, description.workflow_id, 9));
    }
    try write(root.dir, run_path ++ "/project/.sddtoolkit.json", config_bytes);
    try root.dir.deleteFile(io, run_path ++ "/evidence/generation/call-000009/request.json");
    try root.dir.symLink(io, "context.json", run_path ++ "/evidence/generation/call-000009/request.json", .{});
    try std.testing.expectError(error.InputUnavailable, capture.load(io, std.testing.allocator, root.dir, run_path, description.workflow_id, 9));
}

test "capture rejects evidence redaction and legacy descriptions instead of reconstructing controls" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = std.testing.tmpDir(.{});
    defer root.cleanup();
    const io = std.testing.io;
    try fixture(a, root.dir);
    try write(root.dir, run_path ++ "/evidence/generation/call-000009/request.json", "[REDACTED_CREDENTIAL]");
    try std.testing.expectError(error.CaptureRedacted, capture.load(io, std.testing.allocator, root.dir, run_path, description.workflow_id, 9));
    try write(root.dir, run_path ++ "/evidence/generation/call-000009/request.json", body);
    const path = run_path ++ "/project/documents/nested/feature/logs/prompts/MOCK-run/binding/0001.log";
    const bytes = try @import("../files.zig").read(io, a, root.dir, path);
    // A legacy version of a different length would break the archive's
    // retained-byte column first; trailing JSON whitespace keeps the row length.
    const current_quoted = @import("../../../src/domain/model_request_description.zig").current_version ++ "\"";
    const legacy = "model-request-debug/v9\"" ++ " " ** (current_quoted.len - "model-request-debug/v9\"".len);
    try write(root.dir, path, try std.mem.replaceOwned(u8, a, bytes, current_quoted, legacy));
    try std.testing.expectError(error.UnsupportedDebugDescriptionVersion, capture.load(io, std.testing.allocator, root.dir, run_path, description.workflow_id, 9));
}
