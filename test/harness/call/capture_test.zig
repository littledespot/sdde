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
    .provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2" } },
    .model_slot = "sample-slot",
    .workflow_id = "sample-workflow",
    .workflow_version = 3,
    .request_step = "prepare-sample",
    .content = &.{ .{ .guidance = "MOCK guidance" }, .{ .user = "MOCK request" } },
    .protocol_prompt = @import("../../../src/domain/model_controls.zig").response_format_guidance,
    .schema = "{\"type\":\"object\",\"properties\":{},\"additionalProperties\":false}",
    .response_mode = .prompt_only,
    .controls = .{ .temperature = .zero, .max_output_tokens = .{ .value = 123 } },
    .reasoning_effort = "low",
    .operation_kind = .inference,
};
const context: Context = .{
    .schema = .@"model-call-evidence/v1",
    .call = 9,
    .origin = .{ .request = .{ .value = 72 }, .attempt = .{ .value = 3 } },
    .request_step = description.request_step,
    .slot = description.model_slot,
    .attempt = 3,
    .model = description.model,
    .region = description.provider_config.aws_bedrock.region,
    .kind = .inference,
    .reasoning_effort = description.reasoning_effort,
    .content = description.content,
    .response_schema = description.schema,
    .response_mode = description.response_mode,
};
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

test "capture selection rejects incomplete redacted replay and noninference records" {
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
    invalid = call;
    invalid.description.?.operation_kind = .input_token_count;
    try std.testing.expectError(error.CaptureNotInference, capture.select(&.{invalid}, context, description.workflow_id, 9, body));
    var count = context;
    count.kind = .input_token_count;
    count.origin.kind = .input_token_count;
    try std.testing.expectError(error.CaptureNotInference, capture.select(&.{call}, count, description.workflow_id, 9, body));
}

test "capture selection compares all recorded context fields and exact request bytes" {
    inline for (.{ "request_step", "slot", "model", "reasoning_effort", "response_schema" }) |field| {
        var mismatch = context;
        @field(mismatch, field) = "MOCK-mismatch";
        try std.testing.expectError(error.CaptureMismatch, capture.select(&.{call}, mismatch, description.workflow_id, 9, body));
    }
    inline for (.{ "request_step", "model_slot", "model", "workflow_id", "schema", "reasoning_effort" }) |field| {
        var mismatch = call;
        @field(mismatch.description.?, field) = "MOCK-mismatch";
        try std.testing.expectError(error.CaptureMismatch, capture.select(&.{mismatch}, context, description.workflow_id, 9, body));
    }
    var mismatch = context;
    mismatch.content = &.{ .{ .guidance = "different MOCK guidance" }, .{ .user = "MOCK request" } };
    try std.testing.expectError(error.CaptureMismatch, capture.select(&.{call}, mismatch, description.workflow_id, 9, body));
    mismatch.content = &.{ .{ .user = "MOCK guidance" }, .{ .user = "MOCK request" } };
    try std.testing.expectError(error.CaptureMismatch, capture.select(&.{call}, mismatch, description.workflow_id, 9, body));
    mismatch = context;
    mismatch.region = .@"us-west-2";
    try std.testing.expectError(error.CaptureMismatch, capture.select(&.{call}, mismatch, description.workflow_id, 9, body));
    mismatch = context;
    mismatch.response_mode = .native_schema;
    try std.testing.expectError(error.CaptureMismatch, capture.select(&.{call}, mismatch, description.workflow_id, 9, body));
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

test "shared context retains v1 wire shape and rejects unknown version fields and inconsistent origin" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try std.json.Stringify.valueAlloc(a, context, .{});
    try std.testing.expectEqualDeep(context, try Context.decode(a, bytes));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"schema\":\"model-call-evidence/v1\"") != null);
    for ([_][2][]const u8{
        .{ "model-call-evidence/v1", "model-call-evidence/v2" },
        .{ "\"call\":9", "\"call\":9,\"extra\":true" },
        .{ "\"call\":9", "\"call\":9,\"call\":10" },
    }) |change| {
        try std.testing.expectError(error.InvalidJsonDocument, Context.decode(a, try std.mem.replaceOwned(u8, a, bytes, change[0], change[1])));
    }
    for ([_][2][]const u8{
        .{ "\"call\":9", "\"call\":0" },
        .{ "\"attempt\":3", "\"attempt\":2" },
        .{ "prepare-sample", "../outside" },
    }) |change| {
        try std.testing.expectError(error.InvalidCallContext, Context.decode(a, try std.mem.replaceOwned(u8, a, bytes, change[0], change[1])));
    }
}

const config_bytes =
    \\{"logs":{"level":"debug","console":false},"models":{"slots":{"sample-slot":{"provider":"aws-bedrock","model":"MOCK-model","reasoningEffort":"low","maxOutputTokens":123}}},"paths":{"specs":"documents/","references":"references","specsArchive":"documents/archive","workflows":"workflow-definitions","toolchainPreset":"presets","principles":"principles","templates":"templates","providers":"settings/.sddproviders.json"}}
;
const run_path = "runs/unrelated-run";
const provider_bytes = "MOCK provider catalogue read without workflow execution";
const case_bytes =
    \\{"schema":"spec-e2e-case/v1","id":"MOCK-case","workflow_id":"sample-workflow","feature":"nested/feature","reference":"selected","config":"fixture/config.json","evaluation_case":"fixture/evaluation.json","evaluation_config":"fixture/evaluation-config.json","directories":[],"files":[{"source":"fixture/input.md","destination":"references/input.md"}],"expected_artifacts":["specification","reference_context","clarification_state","workflow_state"]}
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
    try write(root, run_path ++ "/evidence/generation/call-000009/context.json", try std.json.Stringify.valueAlloc(a, context, .{}));
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
        .origin = context.origin,
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
    try std.testing.expectEqual(@as(?u32, 123), loaded.config.models.slots.map.get("sample-slot").?.maxOutputTokens);
    try std.testing.expectEqual(@as(u32, 123), loaded.call.description.?.controls.max_output_tokens.?.value);
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
    try write(root.dir, path, try std.mem.replaceOwned(u8, a, bytes, "model-request-debug/v3", "model-request-debug/v2"));
    try std.testing.expectError(error.InvalidDebugArchive, capture.load(io, std.testing.allocator, root.dir, run_path, description.workflow_id, 9));
}
