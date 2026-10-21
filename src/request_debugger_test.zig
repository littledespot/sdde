const std = @import("std");
const debug = @import("domain/request_debugger.zig");
const port = @import("ports/request_replay.zig");
const adapter = @import("adapters/provider/request_replay.zig");
const service = @import("application/request_replay.zig");
const archive = @import("domain/request_debugger_archive.zig");
const capture = @import("application/model_exchange_capture.zig");
const format = @import("domain/feature_log_format.zig");
const schema = "{\"type\":\"object\",\"properties\":{\"answer\":{\"type\":\"string\",\"maxLength\":256}},\"required\":[\"answer\"],\"additionalProperties\":false}";
const description: debug.Description = .{
    .provider = "aws-bedrock",
    .model = "openai.gpt-oss-20b-1:0",
    .provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .max_output_tokens = .{ .tokens = 16000 } } },
    .model_slot = "generation",
    .workflow_id = "spec",
    .workflow_version = 1,
    .request_step = "generation-prepare",
    .content = &.{ .{ .guidance = "Generate an answer." }, .{ .user = "{\"claims\":[\"one\",\"two\"]}" } },
    .protocol_prompt = @import("domain/model_controls.zig").response_format_guidance,
    .schema = schema,
    .response_mode = .prompt_only,
    .controls = .{ .temperature = .fixed },
    .reasoning_effort = "low",
    .operation_kind = .inference,
};
const Fixture = struct {
    wire: @import("bedrock_transport_test_fixture.zig").Wire = .{},
    environment: std.process.Environ.Map,
    compiler: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{},
    provider: adapter.Adapter = undefined,
    denied: bool = false,
    requests: usize = 0,
    responses: usize = 0,
    fail_request: bool = false,
    fail_response: bool = false,
    saved: ?debug.RequestRecord = null,
    request_profile: @import("domain/llm_provider_contracts.zig").BedrockRequestProfile = .openai_oss,
    fn init(self: *Fixture, a: std.mem.Allocator) !void {
        self.* = .{ .environment = .init(a) };
        try self.environment.put("AWS_BEARER_TOKEN_BEDROCK", "test-secret-never-log");
        self.provider = .{ .authorization = .{ .context = @ptrCast(self), .authorize_fn = authorize }, .environment = &self.environment, .transport = self.wire.port(), .clock = .{ .context = @ptrCast(self), .now_fn = now }, .compiler = self.compiler.compiler() };
    }
    fn authorize(ctx: *port.Context, value: debug.Description) port.Error!@import("domain/llm_provider_contracts.zig").BedrockRequestProfile {
        const self: *Fixture = @ptrCast(@alignCast(ctx));
        if (self.denied or !std.mem.eql(u8, value.model, description.model)) return error.ReplayUnauthorized;
        return self.request_profile;
    }
    fn now(_: *@import("ports/provider_authorization_lease.zig").Context) error{ClockUnavailable}!u64 {
        return 100;
    }
    fn storeRequest(ctx: *port.Context, _: std.mem.Allocator, value: debug.RequestRecord) port.Error!void {
        const self: *Fixture = @ptrCast(@alignCast(ctx));
        if (self.fail_request) return error.ReplayStorageFailure;
        self.requests += 1;
        self.saved = value;
    }
    fn storeResponse(ctx: *port.Context, _: std.mem.Allocator, _: debug.ResponseRecord) port.Error!void {
        const self: *Fixture = @ptrCast(@alignCast(ctx));
        if (self.fail_response) return error.ReplayStorageFailure;
        self.responses += 1;
    }
    fn replay(self: *Fixture) service.Service {
        return .{ .provider = self.provider.provider(), .store = .{ .context = @ptrCast(self), .request_fn = storeRequest, .response_fn = storeResponse } };
    }
    fn parent(self: *Fixture, a: std.mem.Allocator) !debug.Call {
        return .{ .run = "run-one", .sequence = 1, .id = "request-7-inference-1", .workflow = "spec", .action = "invoke-model", .node = "generation-invoke", .request_step = description.request_step, .slot = "generation", .kind = "initial", .original = "request-7-inference-1", .parent = null, .description = description, .request = try self.provider.provider().prepare(a, description), .request_complete = true };
    }
};

test "exact replay retains byte equality and modified replay changes only selected content" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture: Fixture = undefined;
    try fixture.init(a);
    defer fixture.environment.deinit();
    var parent = try fixture.parent(a);
    parent.source_snapshot = sourceFixture();
    const result = try fixture.replay().replay(a, replayIdentity("a" ** 32, 1), parent, .{ .call = 0, .mode = .exact });
    try std.testing.expectEqualStrings("debugger-session", result.request.run);
    try std.testing.expectEqual(@as(u64, 1), result.request.sequence);
    try std.testing.expectEqualDeep(parent.source_snapshot, result.request.source_snapshot);
    try std.testing.expect(!result.request.source_overrides);
    try std.testing.expectEqualStrings(parent.request.?, result.request.body);
    try std.testing.expectEqualStrings(parent.id, result.request.parent_call);
    try std.testing.expectEqual(@as(usize, 1), fixture.wire.calls);
    try std.testing.expectEqual(@as(usize, 1), fixture.responses);
    const modified = try fixture.replay().replay(a, replayIdentity("b" ** 32, 2), parent, .{ .call = 0, .mode = .modified, .edit = .{ .content = &.{ .{ .guidance = "Use this edited task prompt." }, .{ .user = "{\"claims\":[\"changed\"]}" } }, .schema = schema } });
    try std.testing.expect(std.mem.indexOf(u8, modified.request.body, "edited task prompt") != null);
    try std.testing.expect(std.mem.indexOf(u8, parent.request.?, "edited task prompt") == null);
    try std.testing.expectEqual(@as(usize, 2), fixture.wire.calls);
    try std.testing.expectEqualStrings(description.model, modified.request.description.model);
    try std.testing.expectEqualDeep(description.controls, result.request.description.controls);
    try std.testing.expectEqualDeep(description.controls, modified.request.description.controls);
    var parsed = try std.json.parseFromSlice(std.json.Value, a, modified.request.body, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i64, description.provider_config.aws_bedrock.max_output_tokens.tokens), parsed.value.object.get("inferenceConfig").?.object.get("maxTokens").?.integer);
    try std.testing.expectEqual(@as(u64, 2), fixture.saved.?.sequence);
    try std.testing.expect(modified.request.source_overrides);
    try std.testing.expectEqualDeep(parent.source_snapshot, modified.request.source_snapshot);
    var replayed_parent = parent;
    replayed_parent.description = modified.request.description;
    replayed_parent.request = modified.request.body;
    replayed_parent.source_overrides = true;
    const exact_again = try fixture.replay().replay(a, replayIdentity("c" ** 32, 3), replayed_parent, .{ .call = 0, .mode = .exact });
    try std.testing.expect(exact_again.request.source_overrides);
    try std.testing.expectEqualDeep(parent.source_snapshot, exact_again.request.source_snapshot);
}

test "replay sends the description's recorded model maximum unchanged" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture: Fixture = undefined;
    try fixture.init(a);
    defer fixture.environment.deinit();
    for ([_]u32{ 8192, 16000 }) |maximum| {
        var selected = description;
        selected.provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .max_output_tokens = .{ .tokens = maximum } } };
        const body = try fixture.provider.provider().prepare(a, selected);
        const parsed = try std.json.parseFromSlice(std.json.Value, a, body, .{});
        try std.testing.expectEqual(@as(i64, maximum), parsed.value.object.get("inferenceConfig").?.object.get("maxTokens").?.integer);
        // A persisted description round-trips the value; zero is not a maximum.
        try std.testing.expectEqual(maximum, (try debug.Description.decode(a, try std.json.Stringify.valueAlloc(a, selected, .{}))).provider_config.aws_bedrock.max_output_tokens.tokens);
    }
    // A recorded maximum is one positive integer: no decoded description holds
    // zero, a negative, an out-of-range, quoted, fractional or nested value.
    const bytes = try std.json.Stringify.valueAlloc(a, description, .{});
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, bytes, "\"max_output_tokens\":16000"));
    for ([_][]const u8{ "0", "-1", "5000000000", "\"16000\"", "16000.5", "null", "{\"tokens\":16000}" }) |value| {
        const rejected = try std.mem.replaceOwned(u8, a, bytes, "\"max_output_tokens\":16000", try std.fmt.allocPrint(a, "\"max_output_tokens\":{s}", .{value}));
        try std.testing.expectError(error.InvalidJsonDocument, debug.Description.decode(a, rejected));
    }
}

test "captured descriptions round-trip controls and reject a retired output allowance" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try std.json.Stringify.valueAlloc(a, description, .{});
    const restored = try debug.Description.decode(a, bytes);
    try std.testing.expectEqualDeep(description.controls, restored.controls);
    // ADR 0011: no description can carry an output-token allowance.
    const retired = try std.mem.replaceOwned(u8, a, bytes, "\"temperature\":\"fixed\"", "\"temperature\":\"fixed\",\"max_output_tokens\":{\"value\":16384}");
    try std.testing.expect(!std.mem.eql(u8, bytes, retired));
    try std.testing.expectError(error.InvalidJsonDocument, debug.Description.decode(a, retired));
    // The superseded v8 label, which recorded no model maximum output, cannot be read as current.
    const superseded = try std.mem.replaceOwned(u8, a, bytes, "model-request-debug/v9", "model-request-debug/v8");
    try std.testing.expect(!std.mem.eql(u8, bytes, superseded));
    try std.testing.expectError(error.InvalidJsonDocument, debug.Description.decode(a, superseded));
}

test "replay rejects redacted incomplete inconsistent and unauthorized requests before dispatch" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture: Fixture = undefined;
    try fixture.init(a);
    defer fixture.environment.deinit();
    const base = try fixture.parent(a);
    try std.testing.expectError(error.InvalidReplay, fixture.replay().replay(a, replayIdentity("a" ** 32, 0), base, .{ .call = 0, .mode = .exact }));
    var parent = base;
    parent.redacted = true;
    try std.testing.expectError(error.InvalidReplay, fixture.replay().replay(a, replayIdentity("a" ** 32, 1), parent, .{ .call = 0, .mode = .exact }));
    parent = base;
    parent.request_complete = false;
    try std.testing.expectError(error.InvalidReplay, fixture.replay().replay(a, replayIdentity("a" ** 32, 1), parent, .{ .call = 0, .mode = .exact }));
    parent = base;
    parent.request = "{}";
    try std.testing.expectError(error.InvalidReplay, fixture.replay().replay(a, replayIdentity("a" ** 32, 1), parent, .{ .call = 0, .mode = .exact }));
    fixture.denied = true;
    try std.testing.expectError(error.ReplayUnauthorized, fixture.replay().replay(a, replayIdentity("a" ** 32, 1), base, .{ .call = 0, .mode = .exact }));
    fixture.denied = false;
    for ([_][]const u8{ "{}", "{\"type\":\"object\",\"unknown\":true}" }) |invalid| try std.testing.expectError(error.InvalidReplay, fixture.replay().replay(a, replayIdentity("a" ** 32, 1), base, .{ .call = 0, .mode = .modified, .edit = .{ .content = description.content, .schema = invalid } }));
    try std.testing.expectError(error.InvalidReplay, fixture.replay().replay(a, replayIdentity("a" ** 32, 1), base, .{ .call = 0, .mode = .modified, .edit = .{ .content = &.{ .{ .guidance = "test-secret-never-log" }, .{ .user = "{}" } }, .schema = schema } }));
    try std.testing.expectEqual(@as(usize, 0), fixture.wire.calls);
    try std.testing.expectEqual(@as(usize, 0), fixture.requests);
}

test "exact replay rejects immutable legacy provider request bytes before storage or dispatch" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture: Fixture = undefined;
    try fixture.init(a);
    defer fixture.environment.deinit();
    var parent = try fixture.parent(a);
    // A retained old-wire request is an inspection record, never a request to
    // migrate or silently reconstruct for the current Converse endpoint.
    const legacy = try std.json.Stringify.valueAlloc(a, .{
        .messages = .{
            .{ .role = "developer", .content = .{
                .{ .type = "text", .text = "Generate an answer." },
                .{ .type = "text", .text = description.protocol_prompt },
                .{ .type = "text", .text = schema },
            } },
            .{ .role = "user", .content = .{.{ .type = "text", .text = "{\"claims\":[\"one\",\"two\"]}" }} },
        },
        .reasoning_effort = "low",
        .temperature = @as(f64, 0.1),
        .max_completion_tokens = @as(u32, 16384),
    }, .{});
    parent.request = legacy;
    const before = parent;
    try std.testing.expectError(error.InvalidReplay, fixture.replay().replay(a, replayIdentity("a" ** 32, 1), parent, .{ .call = 0, .mode = .exact }));
    try std.testing.expectEqualDeep(before, parent);
    try std.testing.expectEqualStrings(legacy, parent.request.?);
    try std.testing.expectEqual(@as(usize, 0), fixture.wire.calls);
    try std.testing.expectEqual(@as(usize, 0), fixture.requests);
    try std.testing.expectEqual(@as(usize, 0), fixture.responses);
}

test "request persistence precedes the only send and response storage failure cannot report success" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture: Fixture = undefined;
    try fixture.init(a);
    defer fixture.environment.deinit();
    const parent = try fixture.parent(a);
    fixture.fail_request = true;
    try std.testing.expectError(error.ReplayStorageFailure, fixture.replay().replay(a, replayIdentity("a" ** 32, 1), parent, .{ .call = 0, .mode = .exact }));
    try std.testing.expectEqual(@as(usize, 0), fixture.wire.calls);
    fixture.fail_request = false;
    fixture.fail_response = true;
    try std.testing.expectError(error.ReplayStorageFailure, fixture.replay().replay(a, replayIdentity("a" ** 32, 1), parent, .{ .call = 0, .mode = .exact }));
    try std.testing.expectEqual(@as(usize, 1), fixture.wire.calls);
    fixture.fail_response = false;
    fixture.wire.cancelled = true;
    const cancelled = try fixture.replay().replay(a, replayIdentity("b" ** 32, 2), parent, .{ .call = 0, .mode = .exact });
    try std.testing.expectEqual(.cancelled, cancelled.response.outcome);
    try std.testing.expectEqual(@as(usize, 2), fixture.wire.calls);
}

test "response inspection reuses extraction and reports the exact schema path and type" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture: Fixture = undefined;
    try fixture.init(a);
    defer fixture.environment.deinit();
    const response = try debugResponse(a, "{\"answer\":null}");
    const checked = try fixture.provider.provider().inspect(a, description, response);
    try std.testing.expectEqual(.valid, checked.extraction);
    try std.testing.expectEqual(.valid, checked.json);
    try std.testing.expectEqual(.invalid, checked.schema);
    try std.testing.expectEqualStrings("/answer", checked.path.?);
    try std.testing.expectEqualStrings("string", checked.expected.?);
    try std.testing.expectEqualStrings("null_value", checked.received.?);
    try std.testing.expectEqual(@as(?u64, 10), checked.input_tokens);
    var count_description = description;
    count_description.operation_kind = .input_token_count;
    const count = try fixture.provider.provider().inspect(a, count_description, "{\"inputTokens\":10}");
    try std.testing.expectEqual(.unavailable, count.extraction);
    try std.testing.expectEqual(.unavailable, count.schema);
}

test "response inspection admits retained native usage through existing normalization and selected schema" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture: Fixture = undefined;
    try fixture.init(a);
    defer fixture.environment.deinit();
    // Exact provider response and selected response_schema from the retained
    // 2026-10-15T20-29-20Z GPT-OSS-20B compatibility exchange. This is offline
    // codec/admission evidence; it does not claim live compatibility or quality.
    const bytes = @embedFile("test_fixtures/bedrock_converse_usage/response.json");
    var selected = description;
    selected.schema = @embedFile("test_fixtures/bedrock_converse_usage/schema.json");
    selected.field_policies = try @import("domain/model_candidate_json.zig").fieldBindings(@import("domain/reference_extraction_parser.zig").Response, a, .{ .reference_phase = .extraction });
    selected.response_mode = .native_schema;
    const checked = try fixture.provider.provider().inspect(a, selected, bytes);
    try std.testing.expectEqual(.valid, checked.extraction);
    try std.testing.expectEqual(.valid, checked.json);
    try std.testing.expectEqual(.valid, checked.schema);
    try std.testing.expectEqual(.removed_leading_brace_quote, checked.normalization);
    try std.testing.expectEqual(@as(?u64, 2106), checked.input_tokens);
    try std.testing.expectEqual(@as(?u64, 148), checked.output_tokens);
    try std.testing.expectEqual(@as(u64, 2254), checked.input_tokens.? + checked.output_tokens.?);
    try std.testing.expectEqual(@as(?u32, 923), checked.latency_ms);
    try std.testing.expect(checked.reason == null);
    const raw = try @import("domain/strict_json.zig").decode(std.json.Value, a, bytes, .{ .maximum_depth = 64 });
    const blocks = raw.object.get("output").?.object.get("message").?.object.get("content").?.array.items;
    const original_text = blocks[1].object.get("text").?.string;
    try std.testing.expectEqualStrings(original_text, checked.model_text.?);
    try std.testing.expect(std.mem.startsWith(u8, checked.model_text.?, "{\"{ \"kind\":"));
    try std.testing.expectEqual(@as(usize, 1), checked.reasoning.len);
    try std.testing.expectEqualStrings(blocks[0].object.get("reasoningContent").?.object.get("reasoningText").?.object.get("text").?.string, checked.reasoning[0].text.text);
    try std.testing.expectEqual(@as(?[]const u8, null), checked.reasoning[0].text.signature);
    const claims = checked.parsed.?.object.get("claims").?.array.items;
    try std.testing.expectEqual(@as(usize, 3), claims.len);
    try std.testing.expectEqualStrings("claims", checked.parsed.?.object.get("kind").?.string);
    try std.testing.expectEqualStrings("The application must start successfully.", claims[0].object.get("content").?.object.get("segments").?.string);
    try std.testing.expectEqual(@as(usize, 0), fixture.wire.calls);
}

test "response inspection preserves canonical envelope rejection reason and field path" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture: Fixture = undefined;
    try fixture.init(a);
    defer fixture.environment.deinit();
    const original = try debugResponse(a, "{\"answer\":\"kept\"}");
    const cases = [_]struct { usage: []const u8, reason: []const u8, path: []const u8 }{
        .{ .usage = "\"serverToolUsage\":null,", .reason = "Expected provider response object", .path = "/usage/serverToolUsage" },
        .{ .usage = "\"serverToolUsage\":[],", .reason = "Expected provider response object", .path = "/usage/serverToolUsage" },
        .{ .usage = "\"serverToolUsage\":{\"unsupported\":true},", .reason = "Unknown provider response field", .path = "/usage/serverToolUsage/unsupported" },
        .{ .usage = "\"serverToolUsage\":{},\"unregistered/~\":true,", .reason = "Unknown provider response field", .path = "/usage/unregistered~1~0" },
    };
    for (cases) |case| {
        const replacement = try std.mem.concat(a, u8, &.{ case.usage, "\"inputTokens\":" });
        const malformed = try std.mem.replaceOwned(u8, a, original, "\"inputTokens\":", replacement);
        try std.testing.expect(!std.mem.eql(u8, malformed, original));
        const checked = try fixture.provider.provider().inspect(a, description, malformed);
        try std.testing.expectEqual(.invalid, checked.extraction);
        try std.testing.expectEqual(.unavailable, checked.json);
        try std.testing.expectEqual(.unavailable, checked.schema);
        try std.testing.expectEqualStrings(case.reason, checked.reason.?);
        try std.testing.expectEqualStrings(case.path, checked.path.?);
        try std.testing.expect(checked.input_tokens == null);
        try std.testing.expect(checked.output_tokens == null);
        try std.testing.expect(checked.model_text == null);
    }
    try std.testing.expectEqual(@as(usize, 0), fixture.wire.calls);
}

const LogSink = struct {
    a: std.mem.Allocator,
    rows: std.ArrayList(u8) = .empty,
    events: std.ArrayList(u8) = .empty,
    sequence: u64 = 0,
    response_redacted: bool = false,
    response_truncated: bool = false,
    fn barrier(self: *LogSink) @import("ports/telemetry_barrier.zig").Barrier {
        return .{ .context = self, .process_fn = event, .select_prompt_fn = select, .process_prompt_fn = log };
    }
    fn event(ctx: *anyopaque, fact: @import("domain/telemetry.zig").WorkflowTelemetryFact) @import("domain/feature_log_stream.zig").Outcome {
        const self: *LogSink = @ptrCast(@alignCast(ctx));
        const row = format.serializeEvent(self.a, .{ .log_policy_id = .{ .bytes = "policy-1" }, .binding_id = .{ .bytes = "binding-1" }, .segment_ordinal = 1, .event_id = .{ .bytes = "event-1" }, .sequence = 1, .occurred_at_utc = "2026-09-20T00:00:00Z", .monotonic_offset = 1, .run_id = .{ .bytes = "run-one" }, .feature_id = .{ .bytes = "feature" }, .workflow_shortcode = fact.workflow_shortcode, .fact = fact.fact }) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        self.events.appendSlice(self.a, row) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        return .{ .persisted = .{ .sequence = 1, .segment_ordinal = 1, .bytes_written = row.len, .flushed = true } };
    }
    fn select(_: *anyopaque, _: @import("domain/sanitized_prompt_log.zig").SanitizedPromptFragment) bool {
        return true;
    }
    fn log(ctx: *anyopaque, fragment: @import("domain/sanitized_prompt_log.zig").SanitizedPromptFragment) @import("domain/feature_log_stream.zig").Outcome {
        const self: *LogSink = @ptrCast(@alignCast(ctx));
        if (fragment.direction == .response) {
            self.response_redacted = self.response_redacted or fragment.redacted;
            self.response_truncated = self.response_truncated or fragment.truncated;
        }
        self.sequence += 1;
        const row = format.serializePrompt(self.a, .{ .log_policy_id = .{ .bytes = "policy-1" }, .binding_id = .{ .bytes = "binding-1" }, .segment_ordinal = 1, .event_id = .{ .bytes = "event-1" }, .sequence = self.sequence, .occurred_at_utc = "2026-09-20T00:00:00Z", .monotonic_offset = 1, .run_id = .{ .bytes = "run-one" }, .feature_id = .{ .bytes = "feature" }, .fragment = fragment }) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        self.rows.appendSlice(self.a, row) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        return .{ .persisted = .{ .sequence = self.sequence, .segment_ordinal = 1, .bytes_written = row.len, .flushed = true } };
    }
};

test "debugger reconstructs full raw request description response and rejects missing chunks" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sink: LogSink = .{ .a = a };
    try sink.rows.appendSlice(a, format.prompt_heading);
    var logger: capture.Capture = .{ .allocator = a, .logs = sink.barrier() };
    defer logger.deinit();
    logger.begin(.{ .workflow = try @import("domain/telemetry.zig").WorkflowShortcode.parse("SPEC"), .workflow_id = .{ .bytes = "spec" }, .node = .{ .bytes = "generation-invoke" }, .action = .{ .bytes = "invoke-model" }, .operation = .{ .bytes = "generation-prepare" }, .model_slot = .{ .bytes = "generation" }, .origin = .{ .request = .{ .value = 7 }, .attempt = .{ .value = 1 } }, .description = description });
    defer logger.end();
    const body = try a.alloc(u8, 11000);
    @memset(body, 'x');
    body[42] = '|';
    body[43] = '\n';
    body[44] = '\\';
    try std.testing.expectEqual(.recorded, logger.port().capture(.request, .{ .provider_body = body }, &.{}));
    const request_end = sink.rows.items.len;
    try std.testing.expectEqual(.recorded, logger.port().capture(.response, .{ .provider_body = "malformed {" }, &.{}));
    var restored: archive.Archive = .{ .allocator = a };
    try restored.ingest(sink.rows.items);
    try sink.events.appendSlice(a, format.event_heading);
    const events: @import("application/workflow_event_capture.zig").Capture = .{ .barrier = sink.barrier(), .shortcode = try @import("domain/telemetry.zig").WorkflowShortcode.parse("SPEC") };
    try std.testing.expect(events.validation(.{ .bytes = "check-evidence" }, .invalid, "SOURCE_SELECTIONS", .{ .request = .{ .value = 7 }, .attempt = .{ .value = 1 } }) == null);
    try restored.ingestEvents(sink.events.items);
    const calls = try restored.calls();
    try std.testing.expectEqual(@as(usize, 1), calls.len);
    try std.testing.expectEqualStrings(body, calls[0].request.?);
    try std.testing.expect(calls[0].request_complete);
    try std.testing.expectEqualStrings(description.schema, calls[0].description.?.schema);
    try std.testing.expectEqualStrings("invoke-model", calls[0].action);
    try std.testing.expectEqualStrings("generation-invoke", calls[0].node);
    try std.testing.expectEqualStrings("malformed {", calls[0].response.?);
    try std.testing.expectEqual(@as(usize, 1), calls[0].events.len);
    try std.testing.expectEqualStrings("check-evidence", calls[0].events[0].node.?);
    try std.testing.expectEqualStrings("SOURCE_SELECTIONS", calls[0].events[0].diagnostic.?);
    const obsolete = try std.mem.replaceOwned(u8, a, sink.rows.items, "model-request-debug/v9", "model-request-debug/v3");
    try std.testing.expect(!std.mem.eql(u8, obsolete, sink.rows.items));
    var unsupported: archive.Archive = .{ .allocator = a };
    try unsupported.ingest(obsolete);
    try std.testing.expectError(error.UnsupportedDebugDescriptionVersion, unsupported.calls());
    const malformed = try std.mem.replaceOwned(u8, a, sink.rows.items, "\"original_sources\":[]", "\"original_sources\":{}");
    try std.testing.expect(!std.mem.eql(u8, malformed, sink.rows.items));
    var invalid_current: archive.Archive = .{ .allocator = a };
    try invalid_current.ingest(malformed);
    try std.testing.expectError(error.InvalidDebugArchive, invalid_current.calls());
    var partial: archive.Archive = .{ .allocator = a };
    const last_line = std.mem.lastIndexOfScalar(u8, sink.rows.items[0 .. request_end - 1], '\n').? + 1;
    try partial.ingest(sink.rows.items[0..last_line]);
    try std.testing.expect(!(try partial.calls())[0].request_complete);
    var duplicate: archive.Archive = .{ .allocator = a };
    try duplicate.ingest(sink.rows.items);
    try std.testing.expectError(error.InvalidDebugArchive, duplicate.ingest(sink.rows.items));
}

test "debugger reconstructs entire reasoning responses including output-limit and unfinished answers" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const secret = "TEST_REASONING_CREDENTIAL";
    const reasoning = try a.alloc(u8, 170000);
    @memset(reasoning, 'r');
    for ([_]struct { finish: []const u8, tail: []const u8 }{
        .{ .finish = "end_turn", .tail = "</reasoning>{\"answer\":\"complete tail\"}" },
        .{ .finish = "max_tokens", .tail = "</reasoning>" },
        .{ .finish = "max_tokens", .tail = "unfinished reasoning" },
    }) |case| {
        var sink: LogSink = .{ .a = a };
        try sink.rows.appendSlice(a, format.prompt_heading);
        var logger: capture.Capture = .{ .allocator = a, .logs = sink.barrier() };
        defer logger.deinit();
        logger.begin(.{ .workflow = try @import("domain/telemetry.zig").WorkflowShortcode.parse("SPEC"), .workflow_id = .{ .bytes = "spec" }, .node = .{ .bytes = "generation-invoke" }, .action = .{ .bytes = "invoke-model" }, .operation = .{ .bytes = "generation-prepare" }, .model_slot = .{ .bytes = "generation" }, .origin = .{ .request = .{ .value = 7 }, .attempt = .{ .value = 1 } }, .description = description });
        defer logger.end();
        try std.testing.expectEqual(.recorded, logger.port().capture(.request, .{ .provider_body = "{}" }, &.{secret}));
        const request_sequence = sink.sequence;
        const content = try std.mem.concat(a, u8, &.{ "<reasoning>", reasoning, "\n|\\🐈", secret, case.tail });
        const body = try std.json.Stringify.valueAlloc(a, .{
            .output = .{ .message = .{ .role = "assistant", .content = .{.{ .text = content }} } },
            .stopReason = case.finish,
            .usage = .{ .inputTokens = @as(u64, 10), .outputTokens = @as(u64, 16384), .totalTokens = @as(u64, 16394) },
        }, .{});
        try std.testing.expectEqual(.recorded, logger.port().capture(.response, .{ .provider_body = body }, &.{secret}));
        // Complete capture has no fragment ceiling; this body spans many fragments.
        try std.testing.expect(sink.sequence - request_sequence > 32);
        var restored: archive.Archive = .{ .allocator = a };
        try restored.ingest(sink.rows.items);
        const calls = try restored.calls();
        try std.testing.expectEqual(@as(usize, 1), calls.len);
        const expected = try std.mem.replaceOwned(u8, a, body, secret, "[REDACTED_CREDENTIAL]");
        try std.testing.expectEqualStrings(expected, calls[0].response.?);
        try std.testing.expectEqualStrings("provider_body", calls[0].response_provenance.?);
        try std.testing.expect(sink.response_redacted);
        try std.testing.expect(!sink.response_truncated);
        // Call.redacted describes request redaction, which controls replay.
        try std.testing.expect(!calls[0].redacted);
        try std.testing.expect(std.mem.indexOf(u8, sink.rows.items, secret) == null);
        try std.testing.expect(logger.failure == null);
    }
}

test "replay API rejects unknown fields modes and cross origin or missing authorization" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    _ = try debug.ReplayInput.decode(a, "{\"call\":0,\"mode\":\"exact\",\"edit\":null}");
    for ([_][]const u8{ "{\"call\":0,\"mode\":\"workflow\",\"edit\":null}", "{\"call\":0,\"mode\":\"modified\",\"edit\":null}", "{\"call\":0,\"mode\":\"exact\",\"edit\":null,\"path\":\"evil\"}" }) |bytes| try std.testing.expectError(error.InvalidJsonDocument, debug.ReplayInput.decode(a, bytes));
    const auth = @import("adapters/system/request_debugger_server.zig").authorized;
    try std.testing.expect(auth("secret", "secret", "http://127.0.0.1:1", "http://127.0.0.1:1", true));
    try std.testing.expect(!auth("secret", "secret", "http://127.0.0.1:1", "https://evil.example", true));
    try std.testing.expect(!auth("secret", null, "http://127.0.0.1:1", null, false));
    try std.testing.expect(!auth("secret", "secret", "http://127.0.0.1:1", null, true));
}

test "replay records reopen with immutable original lineage and storage rejects symlinks" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    var store: @import("adapters/filesystem/request_debugger_store.zig").Store = .{ .io = io, .feature = directory.dir };
    const record: debug.RequestRecord = .{ .id = "a" ** 32, .run = "debugger-session", .sequence = 1, .parent_run = "debugger", .parent_call = "b" ** 32, .original_run = "run-one", .original_call = "request-7-inference-1", .node = "generation-invoke", .mode = .exact, .description = description, .body = "captured request", .source_snapshot = sourceFixture() };
    try store.port().request(a, record);
    try std.testing.expectError(error.ReplayStorageFailure, store.port().request(a, record));
    var restored = try store.load(a);
    try std.testing.expectEqual(@as(usize, 1), restored.len);
    try std.testing.expect(restored[0].response == null);
    try std.testing.expectEqualDeep(record.source_snapshot, restored[0].source_snapshot);
    try store.port().response(a, .{ .id = record.id, .outcome = .received, .status = 429, .body = "provider error", .diagnostic = "rate limited" });
    try std.testing.expectError(error.ReplayStorageFailure, store.port().response(a, .{ .id = record.id, .outcome = .cancelled }));
    restored = try store.load(a);
    try std.testing.expectEqualStrings(record.original_run, restored[0].original_run.?);
    try std.testing.expectEqualStrings(record.original_call, restored[0].original);
    try std.testing.expectEqualStrings(record.parent_call, restored[0].parent.?);
    try std.testing.expectEqualStrings(record.node, restored[0].node);
    try std.testing.expectEqualStrings(record.body, restored[0].request.?);
    try std.testing.expectEqual(@as(?u16, 429), restored[0].response_status);
    try std.testing.expectEqualStrings("rate limited", restored[0].response_diagnostic.?);
    var linked = std.testing.tmpDir(.{ .iterate = true });
    defer linked.cleanup();
    try linked.dir.createDir(io, "elsewhere", .default_dir);
    try linked.dir.symLink(io, "elsewhere", "logs", .{ .is_directory = true });
    var linked_store: @import("adapters/filesystem/request_debugger_store.zig").Store = .{ .io = io, .feature = linked.dir };
    try std.testing.expectError(error.ReplayStorageFailure, linked_store.port().request(a, record));
}

test "replay retains redacted partial errors and native schema modifications without retry" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture: Fixture = undefined;
    try fixture.init(a);
    defer fixture.environment.deinit();
    var parent = try fixture.parent(a);
    fixture.wire.result = .{ .failed = .{ .cause = .transport_failed, .retry_class = .policy_eligible, .delivery = .accepted_or_unknown, .body = .{ .bytes = "partial test-secret-never-log", .complete = false } } };
    const partial = try fixture.replay().replay(a, replayIdentity("a" ** 32, 1), parent, .{ .call = 0, .mode = .exact });
    try std.testing.expectEqual(.partial, partial.response.outcome);
    try std.testing.expect(partial.response.redacted);
    try std.testing.expect(std.mem.indexOf(u8, partial.response.body.?, "test-secret-never-log") == null);
    try std.testing.expectEqual(@as(usize, 1), fixture.wire.calls);
    parent.description.?.response_mode = .native_schema;
    parent.request = try fixture.provider.provider().prepare(a, parent.description.?);
    const replacement = "{\"type\":\"object\",\"properties\":{\"updated\":{\"type\":\"boolean\"}},\"required\":[\"updated\"],\"additionalProperties\":false}";
    const modified = try fixture.replay().replay(a, replayIdentity("b" ** 32, 2), parent, .{ .call = 0, .mode = .modified, .edit = .{ .content = description.content, .schema = replacement } });
    try std.testing.expect(std.mem.indexOf(u8, modified.request.body, "updated") != null);
    try std.testing.expect(std.mem.indexOf(u8, modified.request.body, "outputConfig") != null);
    try std.testing.expectEqual(@as(usize, 2), fixture.wire.calls);
}

test "native JSON diagnostic probes retain controls and inspect normalized and valid answers without retry" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture: Fixture = undefined;
    try fixture.init(a);
    defer fixture.environment.deinit();
    fixture.wire.expected_json = true;
    var parent = try fixture.parent(a);
    parent.description.?.response_mode = .native_schema;
    parent.request = try fixture.provider.provider().prepare(a, parent.description.?);
    var previous_content: ?[]const @import("domain/llm_provider_operation.zig").ModelVisibleContent = null;
    const Probe = struct { edit: []const u8, answer: []const u8, first_key: []const u8, union_root: bool = false, constant_value: bool = false };
    const tagged_answer = "{\"kind\":\"present\",\"value\":\"orchard\"}";
    const plain_answer = "{\"value\":\"orchard\"}";
    const probes = [_]Probe{
        .{ .edit = @embedFile("test_fixtures/bedrock-json-object.edit.json"), .answer = tagged_answer, .first_key = "kind" },
        .{ .edit = @embedFile("test_fixtures/bedrock-json-union.edit.json"), .answer = tagged_answer, .first_key = "kind", .union_root = true },
        .{ .edit = @embedFile("test_fixtures/bedrock-json-string.edit.json"), .answer = plain_answer, .first_key = "value" },
        .{ .edit = @embedFile("test_fixtures/bedrock-json-constant.edit.json"), .answer = plain_answer, .first_key = "value", .constant_value = true },
    };
    for (probes, 0..) |probe, index| {
        const edit = try @import("domain/strict_json.zig").decode(debug.Edit, a, probe.edit, .{ .maximum_depth = 64 });
        if (index % 2 == 0) previous_content = null;
        if (previous_content) |content| try std.testing.expectEqualDeep(content, edit.content);
        previous_content = edit.content;
        const malformed = try std.fmt.allocPrint(a, "{{\"{{ {s}", .{probe.answer[1..]});
        const repeated = try std.fmt.allocPrint(a, "{{\"{s}{s}", .{ probe.first_key, probe.answer });
        const string_value = try std.fmt.allocPrint(a, "{{\"{s}\":\"{s}", .{ probe.first_key, probe.answer });
        const different_value = try std.mem.replaceOwned(u8, a, probe.answer, "orchard", "peach");
        const answers = [_][]const u8{ malformed, repeated, string_value, probe.answer, different_value };
        for (answers, 0..) |answer, attempt| {
            fixture.wire.inference_body = try debugResponse(a, answer);
            const before = fixture.wire.calls;
            const sequence = index * answers.len + attempt + 1;
            const id = try std.fmt.allocPrint(a, "{x:0>32}", .{sequence});
            const result = try fixture.replay().replay(a, replayIdentity(id, sequence), parent, .{ .call = 0, .mode = .modified, .edit = edit });
            try std.testing.expectEqual(before + 1, fixture.wire.calls);
            try std.testing.expectEqualStrings(parent.id, result.request.parent_call);
            try std.testing.expectEqualStrings(description.model, result.request.description.model);
            try std.testing.expectEqualDeep(description.controls, result.request.description.controls);
            try std.testing.expectEqualDeep(description.provider_config, result.request.description.provider_config);
            try std.testing.expectEqualStrings(description.reasoning_effort.?, result.request.description.reasoning_effort.?);
            try std.testing.expectEqual(.native_schema, result.request.description.response_mode);
            const wire = try std.json.parseFromSlice(std.json.Value, a, result.request.body, .{});
            const native_bytes = wire.value.object.get("outputConfig").?.object.get("textFormat").?.object.get("structure").?.object.get("jsonSchema").?.object.get("schema").?.string;
            const native = try std.json.parseFromSlice(std.json.Value, a, native_bytes, .{});
            try std.testing.expectEqual(probe.union_root, native.value.object.contains("anyOf"));
            if (!probe.union_root) {
                const fields = native.value.object.get("properties").?.object;
                const value_schema = fields.get("value").?.object;
                try std.testing.expectEqual(probe.constant_value, value_schema.contains("const"));
                if (index >= 2) {
                    try std.testing.expectEqual(@as(usize, 1), fields.count());
                    if (probe.constant_value) {
                        try std.testing.expectEqualStrings("orchard", value_schema.get("const").?.string);
                    } else {
                        try std.testing.expectEqualStrings("string", value_schema.get("type").?.string);
                    }
                }
            }
            try std.testing.expectEqual(.valid, result.validation.extraction);
            try std.testing.expectEqual(.valid, result.validation.json);
            try std.testing.expectEqual(@as(@TypeOf(result.validation.normalization), switch (attempt) {
                0 => .removed_leading_brace_quote,
                1, 2 => .removed_repeated_field_prefix,
                else => .none,
            }), result.validation.normalization);
            try std.testing.expectEqual(@as(@TypeOf(result.validation.schema), if (attempt == answers.len - 1 and probe.constant_value) .invalid else .valid), result.validation.schema);
            try std.testing.expectEqualStrings(answer, result.validation.model_text.?);
            try std.testing.expectEqual(@as(?u64, 10), result.validation.input_tokens);
            try std.testing.expectEqual(@as(?u64, 2), result.validation.output_tokens);
        }
    }
    try std.testing.expectEqual(@as(usize, probes.len * 5), fixture.requests);
    try std.testing.expectEqual(fixture.requests, fixture.responses);
}

test "captured production request reconstructs exactly in both schema modes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture: Fixture = undefined;
    try fixture.init(a);
    defer fixture.environment.deinit();
    var production: @import("provider_authorization_test_fixture.zig").Fixture = undefined;
    try production.init(std.testing.allocator);
    defer production.deinit();
    production.registry_entry.provider.bytes = description.provider;
    production.registry_entry.model.bytes = description.model;
    production.registry_entry.config = description.provider_config;
    production.registry_entry.capabilities.structured_response = .bedrock_json_schema;
    production.registry_entry.bedrock_request_profile = .openai_oss;
    production.request.response_schema = try fixture.compiler.compiler().compile(production.schema_arena.allocator(), schema);
    for ([_]@import("domain/model_controls.zig").ResponseGuidanceMode{ .prompt_only, .native_schema }) |mode| {
        production.request.controls = production.provider_binding.controls;
        production.request.binding_id = production.provider_binding.bindingId();
        production.request.response_guidance_mode = mode;
        production.registry_entry.json = mode == .native_schema;
        try std.testing.expect(production.request.matchesBinding(production.provider_binding));
        const captured = try @import("adapters/provider/bedrock_request.zig").encode(a, &production.request, .inference, production.registry_entry.bedrock_request_profile, production.registry_entry.config.aws_bedrock.max_output_tokens);
        const projection = debug.Description.from(&production.request, &production.provider_binding, .inference);
        const serialized = try std.json.Stringify.valueAlloc(a, projection, .{});
        const restored = try debug.Description.decode(a, serialized);
        try std.testing.expectEqualDeep(production.request.controls, restored.controls);
        try std.testing.expectEqualStrings(captured, try fixture.provider.provider().prepare(a, restored));
    }
}

test "events join the exact operation kind as well as request and attempt" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sink: LogSink = .{ .a = a };
    try sink.rows.appendSlice(a, format.prompt_heading);
    try sink.events.appendSlice(a, format.event_heading);
    const shortcode = try @import("domain/telemetry.zig").WorkflowShortcode.parse("SPEC");
    const events: @import("application/workflow_event_capture.zig").Capture = .{ .barrier = sink.barrier(), .shortcode = shortcode };
    var logger: capture.Capture = .{ .allocator = a, .logs = sink.barrier() };
    defer logger.deinit();
    for ([_]@import("domain/llm_provider_operation.zig").ProviderOperationKind{ .input_token_count, .inference }) |kind| {
        const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 7 }, .attempt = .{ .value = 1 }, .kind = kind };
        logger.begin(.{ .workflow = shortcode, .workflow_id = .{ .bytes = "spec" }, .node = .{ .bytes = "generation-invoke" }, .action = .{ .bytes = "invoke-model" }, .operation = .{ .bytes = "generation-prepare" }, .model_slot = .{ .bytes = "generation" }, .origin = origin });
        try std.testing.expectEqual(.recorded, logger.port().capture(.request, .{ .provider_body = "{}" }, &.{}));
        logger.end();
        try std.testing.expect(events.validation(.{ .bytes = @tagName(kind) }, .ok, null, origin) == null);
    }
    var restored: archive.Archive = .{ .allocator = a };
    try restored.ingest(sink.rows.items);
    try restored.ingestEvents(sink.events.items);
    const calls = try restored.calls();
    try std.testing.expectEqual(@as(usize, 2), calls.len);
    for (calls, [_][]const u8{ "input_token_count", "inference" }) |call, node| {
        try std.testing.expectEqual(@as(usize, 1), call.events.len);
        try std.testing.expectEqualStrings(node, call.events[0].node.?);
    }
}

fn replayIdentity(id: []const u8, sequence: u64) debug.ReplayIdentity {
    return .{ .id = id, .run = .{ .bytes = "debugger-session" }, .sequence = sequence };
}

test "debugger readback preserves explicit assembled repair lineage and subsequent retry" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sink: LogSink = .{ .a = a };
    try sink.rows.appendSlice(a, format.prompt_heading);
    var logger: capture.Capture = .{ .allocator = a, .logs = sink.barrier() };
    defer logger.deinit();
    var metadata: capture.Metadata = .{
        .workflow = try @import("domain/telemetry.zig").WorkflowShortcode.parse("SPEC"),
        .workflow_id = .{ .bytes = "unrelated-workflow" },
        .node = .{ .bytes = "assembled-repair-invoke" },
        .action = .{ .bytes = "invoke-model" },
        .operation = .{ .bytes = "assembled-repair-prepare" },
        .model_slot = .{ .bytes = "repair" },
        .origin = .{ .request = .{ .value = 50 }, .attempt = .{ .value = 1 } },
        .kind = .repair,
        .source = .assembled_candidate,
    };
    logger.begin(metadata);
    try std.testing.expectEqual(.recorded, logger.port().capture(.request, .{ .provider_body = "assembled repair" }, &.{}));
    logger.end();
    metadata.origin.attempt.value = 2;
    logger.begin(metadata);
    try std.testing.expectEqual(.recorded, logger.port().capture(.request, .{ .provider_body = "protocol correction" }, &.{}));
    logger.end();
    var restored: archive.Archive = .{ .allocator = a };
    try restored.ingest(sink.rows.items);
    const calls = try restored.calls();
    try std.testing.expectEqual(@as(usize, 2), calls.len);
    try std.testing.expectEqualStrings("repair", calls[0].kind);
    try std.testing.expect(calls[0].parent == null);
    try std.testing.expectEqualStrings(calls[0].id, calls[0].original);
    try std.testing.expectEqualStrings("retry", calls[1].kind);
    try std.testing.expectEqualStrings(calls[0].id, calls[1].parent.?);
    try std.testing.expectEqualStrings(calls[0].id, calls[1].original);
}

test "debugger orders split captures across bindings by recorded sequence including retries repairs and count calls" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    var sink: LogSink = .{ .a = a, .sequence = 1 };
    try sink.rows.appendSlice(a, format.prompt_heading);
    var logger: capture.Capture = .{ .allocator = a, .logs = sink.barrier() };
    defer logger.deinit();
    const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 10 }, .attempt = .{ .value = 1 } };
    var metadata: capture.Metadata = .{ .workflow = try @import("domain/telemetry.zig").WorkflowShortcode.parse("SPEC"), .workflow_id = .{ .bytes = "spec" }, .node = .{ .bytes = "generation-invoke" }, .action = .{ .bytes = "invoke-model" }, .operation = .{ .bytes = "generation-prepare" }, .model_slot = .{ .bytes = "generation" }, .origin = origin };
    const body = try a.alloc(u8, 11000);
    @memset(body, 'x');
    logger.begin(metadata);
    try std.testing.expectEqual(.recorded, logger.port().capture(.request, .{ .provider_body = body }, &.{}));
    logger.end();
    sink.sequence = 9;
    metadata.origin.request.value = 2;
    logger.begin(metadata);
    try std.testing.expectEqual(.recorded, logger.port().capture(.request, .{ .provider_body = "second" }, &.{}));
    logger.end();
    metadata.origin = origin;
    metadata.origin.attempt.value = 2;
    logger.begin(metadata);
    try std.testing.expectEqual(.recorded, logger.port().capture(.request, .{ .provider_body = "retry" }, &.{}));
    logger.end();
    metadata.origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 }, .kind = .input_token_count };
    logger.begin(metadata);
    try std.testing.expectEqual(.recorded, logger.port().capture(.request, .{ .provider_body = "count" }, &.{}));
    logger.end();
    metadata.origin = .{ .request = .{ .value = 99 }, .attempt = .{ .value = 1 } };
    metadata.kind = .repair;
    metadata.source = .{ .response = origin };
    logger.begin(metadata);
    try std.testing.expectEqual(.recorded, logger.port().capture(.request, .{ .provider_body = "repair" }, &.{}));
    logger.end();

    // Split the first request body across bindings whose filenames sort backwards.
    const split = format.prompt_heading.len + std.mem.indexOfScalar(u8, sink.rows.items[format.prompt_heading.len..], '\n').? + 1;
    const first = sink.rows.items[0..split];
    const rest = try std.mem.concat(a, u8, &.{ format.prompt_heading, sink.rows.items[split..] });
    try directory.dir.createDirPath(io, "logs/prompts/run-one/LOGBIND-10");
    try directory.dir.createDirPath(io, "logs/prompts/run-one/LOGBIND-2");
    try directory.dir.writeFile(io, .{ .sub_path = "logs/prompts/run-one/LOGBIND-10/0001.log", .data = rest });
    try directory.dir.writeFile(io, .{ .sub_path = "logs/prompts/run-one/LOGBIND-2/0001.log", .data = first });
    var store: @import("adapters/filesystem/request_debugger_store.zig").Store = .{ .io = io, .feature = directory.dir };
    const calls = try store.load(a);
    try std.testing.expectEqual(@as(usize, 5), calls.len);
    for (calls, [_][]const u8{ "request-10-inference-1", "request-2-inference-1", "request-10-inference-2", "request-2-input_token_count-1", "request-99-inference-1" }, [_]u64{ 2, 10, 11, 12, 13 }, 1..) |call, id, sequence, number| {
        try std.testing.expectEqualStrings(id, call.id);
        try std.testing.expectEqual(sequence, call.sequence);
        try std.testing.expectEqual(@as(u64, @intCast(number)), call.execution_order);
        try std.testing.expect(call.request_complete);
    }
    try std.testing.expectEqualStrings(body, calls[0].request.?);
    try std.testing.expectEqualStrings("retry", calls[2].kind);
    try std.testing.expectEqualStrings(calls[0].id, calls[2].parent.?);
    try std.testing.expectEqualStrings("repair", calls[4].kind);
    try std.testing.expectEqualStrings(calls[0].id, calls[4].parent.?);

    // The same call ID in another run gets its own sequence and numbering.
    const second_start = std.mem.indexOf(u8, rest, "|10|2026-09-20").?;
    const row_start = std.mem.lastIndexOfScalar(u8, rest[0..second_start], '\n').? + 1;
    const row_end = second_start + std.mem.indexOfScalar(u8, rest[second_start..], '\n').? + 1;
    const other_run = try std.mem.replaceOwned(u8, a, rest[row_start..row_end], "run-one", "run-two");
    try directory.dir.createDirPath(io, "logs/prompts/run-two/LOGBIND-1");
    try directory.dir.writeFile(io, .{ .sub_path = "logs/prompts/run-two/LOGBIND-1/0001.log", .data = try std.mem.concat(a, u8, &.{ format.prompt_heading, other_run }) });
    const grouped = try store.load(a);
    try std.testing.expectEqual(@as(usize, 6), grouped.len);
    try std.testing.expectEqualStrings("run-two", grouped[5].run);
    try std.testing.expectEqualStrings(calls[1].id, grouped[5].id);
    try std.testing.expectEqual(@as(u64, 1), grouped[5].execution_order);

    // Regular files without a segment name are left alone at every level.
    for ([_][]const u8{ "logs/prompts/.DS_Store", "logs/prompts/run-one/Thumbs.db", "logs/prompts/run-one/LOGBIND-2/0001.log.bak" }) |stray| {
        try directory.dir.writeFile(io, .{ .sub_path = stray, .data = "stray" });
    }
    try std.testing.expectEqual(grouped.len, (try store.load(a)).len);
    // A heading-only segment loads cleanly inside a binding, so placement alone
    // rejects it below.
    try directory.dir.createDirPath(io, "logs/prompts/run-one/LOGBIND-3");
    try directory.dir.writeFile(io, .{ .sub_path = "logs/prompts/run-one/LOGBIND-3/0001.log", .data = format.prompt_heading });
    try std.testing.expectEqual(grouped.len, (try store.load(a)).len);
    try directory.dir.deleteTree(io, "logs/prompts/run-one/LOGBIND-3");
    // Any other entry a level does not hold rejects the archive.
    const Misplaced = enum { collection_link, run_link, binding_link, nested_directory, collection_segment, run_segment };
    for (std.enums.values(Misplaced)) |misplaced| {
        const path = switch (misplaced) {
            .collection_link => "logs/prompts/link",
            .run_link => "logs/prompts/run-one/link",
            .binding_link => "logs/prompts/run-one/LOGBIND-2/link",
            .nested_directory => "logs/prompts/run-one/LOGBIND-2/nested",
            .collection_segment => "logs/prompts/0001.log",
            .run_segment => "logs/prompts/run-one/0001.log",
        };
        switch (misplaced) {
            .collection_link, .run_link, .binding_link => try directory.dir.symLink(io, "elsewhere", path, .{}),
            .nested_directory => try directory.dir.createDirPath(io, path),
            .collection_segment, .run_segment => try directory.dir.writeFile(io, .{ .sub_path = path, .data = format.prompt_heading }),
        }
        try std.testing.expectError(error.InvalidDebugArchive, store.load(a));
        if (misplaced == .nested_directory) try directory.dir.deleteDir(io, path) else try directory.dir.deleteFile(io, path);
    }
    try std.testing.expectEqual(grouped.len, (try store.load(a)).len);

    // Sequence overlap across bindings must not manufacture an execution order.
    try directory.dir.writeFile(io, .{ .sub_path = "logs/prompts/run-one/LOGBIND-10/0001.log", .data = first });
    try std.testing.expectError(error.InvalidDebugArchive, store.load(a));
    for ([_][]const u8{ "0", "-1", "+2", "bad", "18446744073709551616" }) |invalid| {
        const malformed = try std.mem.replaceOwned(u8, a, first, "|2|2026-09-20", try std.fmt.allocPrint(a, "|{s}|2026-09-20", .{invalid}));
        try std.testing.expectError(error.InvalidDebugArchive, archive.segmentOrder(a, malformed, false));
        var rejected: archive.Archive = .{ .allocator = a };
        try std.testing.expectError(error.InvalidDebugArchive, rejected.ingest(malformed));
    }
}

test "replay dispatch order survives shuffled filenames reopening and separate sessions" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    var store: @import("adapters/filesystem/request_debugger_store.zig").Store = .{ .io = io, .feature = directory.dir };
    var record: debug.RequestRecord = .{ .id = "a" ** 32, .run = "debugger-session-one", .sequence = 10, .parent_run = "run-one", .parent_call = "request-7-inference-1", .original_run = "run-one", .original_call = "request-7-inference-1", .node = "generation-invoke", .mode = .exact, .description = description, .body = "captured request", .source_snapshot = sourceFixture() };
    try store.port().request(a, record);
    record.id = "f" ** 32;
    record.sequence = 2;
    try store.port().request(a, record);
    record.id = "c" ** 32;
    record.run = "debugger-session-two";
    record.sequence = 1;
    try store.port().request(a, record);
    for (0..2) |_| {
        const restored = try store.load(a);
        try std.testing.expectEqual(@as(usize, 3), restored.len);
        for (restored, [_][]const u8{ "f" ** 32, "a" ** 32, "c" ** 32 }, [_]u64{ 2, 10, 1 }) |call, id, sequence| {
            try std.testing.expectEqualStrings(id, call.id);
            try std.testing.expectEqual(sequence, call.sequence);
            try std.testing.expectEqual(sequence, call.execution_order);
            try std.testing.expectEqualStrings(record.original_call, call.original);
        }
    }
    record.id = "d" ** 32;
    record.sequence = 0;
    try std.testing.expectError(error.InvalidReplay, store.port().request(a, record));
    const invalid_bytes = try std.json.Stringify.valueAlloc(a, record, .{});
    try directory.dir.writeFile(io, .{ .sub_path = "logs/debugger/" ++ "d" ** 32 ++ ".request.json", .data = invalid_bytes });
    try std.testing.expectError(error.InvalidDebugArchive, store.load(a));
    record.sequence = 1;
    const duplicate_bytes = try std.json.Stringify.valueAlloc(a, record, .{});
    try directory.dir.writeFile(io, .{ .sub_path = "logs/debugger/" ++ "d" ** 32 ++ ".request.json", .data = duplicate_bytes });
    try std.testing.expectError(error.InvalidDebugArchive, store.load(a));
    const legacy_bytes = try std.mem.replaceOwned(u8, a, duplicate_bytes, "request-replay/v6", "request-replay/v3");
    try std.testing.expectError(error.InvalidJsonDocument, @import("domain/strict_json.zig").decode(debug.RequestRecord, a, legacy_bytes, .{ .maximum_depth = 64 }));
}

fn sourceFixture() @import("domain/request_source_snapshot.zig").Snapshot {
    return .{
        .workflow = "spec",
        .document = .{ .path = "workflow.yaml", .content = "# captured YAML\n", .redacted = false },
        .caller = .{ .step = "generation-invoke", .chain = &.{.{ .subgraph = null, .id = "generation-invoke", .kind = .operation, .target = "invoke-model", .declaration = "{\"use\":\"invoke-model\"}" }} },
        .preparation = .{ .step = "generation-prepare", .chain = &.{.{ .subgraph = null, .id = "generation-prepare", .kind = .operation, .target = "prepare-model-request", .declaration = "{\"use\":\"prepare-model-request\"}" }} },
        .resources = &.{
            .{ .role = .prompt, .alias = "prompt", .kind = .prompt, .document = .{ .path = "prompts/task.md", .content = "Captured task", .redacted = false } },
            .{ .role = .result, .alias = "result", .kind = .result_schema, .document = .{ .path = "schemas/result.json", .content = schema, .redacted = false } },
        },
        .selection = .{ .definition = null, .part = null, .paths = &.{} },
    };
}

test "source snapshots reject unknown fields invalid paths broken chains and foreign attribution" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Snapshot = @import("domain/request_source_snapshot.zig").Snapshot;
    const base = sourceFixture();
    const encoded = try std.json.Stringify.valueAlloc(a, base, .{});
    try std.testing.expectEqualDeep(base, try Snapshot.decode(a, encoded));
    for ([_][2][]const u8{
        .{ "request-source/v1", "request-source/v2" },
        .{ "workflow.yaml", "../workflow.yaml" },
        .{ "workflow.yaml", "/workflow.yaml" },
        .{ "\"role\":\"prompt\"", "\"role\":\"command\"" },
        .{ "\"subgraph\":null", "\"subgraph\":\"unrelated\"" },
        .{ "\"workflow\":\"spec\"", "\"workflow\":\"spec\",\"unknown\":true" },
    }) |change| {
        const invalid = try std.mem.replaceOwned(u8, a, encoded, change[0], change[1]);
        try std.testing.expectError(error.InvalidJsonDocument, Snapshot.decode(a, invalid));
    }
    var invalid = base;
    invalid.resources = base.resources[0..1];
    try std.testing.expectError(error.InvalidJsonDocument, invalid.validate());
    invalid = base;
    invalid.resources = &.{ base.resources[0], base.resources[0], base.resources[1] };
    try std.testing.expectError(error.InvalidJsonDocument, invalid.validate());
    invalid = base;
    invalid.selection = .{ .definition = null, .part = "unbound", .paths = &.{&.{"answer"}} };
    try std.testing.expectError(error.InvalidJsonDocument, invalid.validate());
    try std.testing.expect(!base.matches("other", "generation-invoke", "generation-prepare"));
    try std.testing.expect(!base.matches("spec", "foreign", "generation-prepare"));
    try std.testing.expect(!base.matches("spec", "generation-invoke", "foreign"));
}

test "source snapshots retain static JSON guidance with its prompt resource kind" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Snapshot = @import("domain/request_source_snapshot.zig").Snapshot;
    var snapshot = sourceFixture();
    const context: @import("domain/request_source_snapshot.zig").Resource = .{
        .role = .context,
        .alias = "field-context",
        .kind = .prompt,
        .document = .{ .path = "prompts/fields.json", .content = "{\"answer\":\"One source-grounded fact.\"}", .redacted = false },
    };
    snapshot.resources = &.{ snapshot.resources[0], context, snapshot.resources[1] };
    const bytes = try std.json.Stringify.valueAlloc(a, snapshot, .{});
    try std.testing.expectEqualDeep(snapshot, try Snapshot.decode(a, bytes));
    const wrong_kind = try std.mem.replaceOwned(u8, a, bytes, "\"alias\":\"field-context\",\"kind\":\"prompt\"", "\"alias\":\"field-context\",\"kind\":\"data\"");
    try std.testing.expectError(error.InvalidJsonDocument, Snapshot.decode(a, wrong_kind));
}

// Exercise capture, fragmentation, graph release, inspection and replay through
// the same shared owners for whole, named, composed and narrowed request shapes.
test "selected request schemas survive capture and graph release without whole-schema fallback" {
    for (0..8) |shape| for ([_]@import("domain/model_controls.zig").ResponseGuidanceMode{ .prompt_only, .native_schema }) |mode| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture: Fixture = undefined;
        try fixture.init(a);
        defer fixture.environment.deinit();
        var sink: LogSink = .{ .a = a };
        try sink.rows.appendSlice(a, format.prompt_heading);
        var logger: capture.Capture = .{ .allocator = a, .logs = sink.barrier() };
        defer logger.deinit();
        var response_text: []const u8 = undefined;
        {
            var production: @import("provider_authorization_test_fixture.zig").Fixture = undefined;
            try production.init(std.testing.allocator);
            defer production.deinit();
            const source = production.schema_arena.allocator();
            production.registry_entry.provider.bytes = description.provider;
            production.registry_entry.model.bytes = description.model;
            production.registry_entry.config = description.provider_config;
            production.registry_entry.capabilities.structured_response = .bedrock_json_schema;
            production.registry_entry.bedrock_request_profile = .openai_oss;
            const selected = try debuggerSelectedShape(source, fixture.compiler.compiler(), shape);
            defer if (selected.restriction) |restriction| restriction.release();
            production.request.response_schema = selected.schema;
            production.request.field_policies = selected.fields;
            // The generic selected-shape fixture intentionally has no source
            // occurrences. Absence of native metadata is a different state.
            production.request.exact_scope = .{ .reference_state = .{ .bytes = "TEST-empty-reference" }, .occurrences = &.{} };
            response_text = try a.dupe(u8, selected.response);
            production.request.response_guidance_mode = mode;
            production.registry_entry.json = mode == .native_schema;
            try std.testing.expect(production.request.matchesBinding(production.provider_binding));
            // Force request-description fragmentation, including its schema.
            production.request.content = &.{ .{ .guidance = try source.dupe(u8, "bounded captured context " ** 500) }, .{ .user = "Generate the selected data." } };
            const projection = debug.Description.from(&production.request, &production.provider_binding, .inference);
            try std.testing.expectEqualStrings(selected.schema.modelBytes(), projection.schema);
            logger.begin(.{ .workflow = try @import("domain/telemetry.zig").WorkflowShortcode.parse("SPEC"), .workflow_id = .{ .bytes = projection.workflow_id }, .node = .{ .bytes = "generation-invoke" }, .action = .{ .bytes = "invoke-model" }, .operation = .{ .bytes = projection.request_step }, .model_slot = .{ .bytes = projection.model_slot }, .origin = .{ .request = .{ .value = 7 }, .attempt = .{ .value = 1 } }, .description = projection });
            defer logger.end();
            const body = try @import("adapters/provider/bedrock_request.zig").encode(source, &production.request, .inference, production.registry_entry.bedrock_request_profile, production.registry_entry.config.aws_bedrock.max_output_tokens);
            try std.testing.expectEqual(.recorded, logger.port().capture(.request, .{ .provider_body = body }, &.{}));
            const response = try debugResponse(source, selected.response);
            try std.testing.expectEqual(.recorded, logger.port().capture(.response, .{ .provider_body = response }, &.{}));
        }
        var restored: archive.Archive = .{ .allocator = a };
        try restored.ingest(sink.rows.items);
        const calls = try restored.calls();
        try std.testing.expectEqual(@as(usize, 1), calls.len);
        const parent = calls[0];
        try std.testing.expect(parent.parent == null);
        const selected = parent.description.?;
        if (shape == 2 or shape == 6) try std.testing.expect(selected.field_policies.len != 0);
        if (shape == 7) try expectReplayedMembers(a, &fixture, selected);
        const inspected = try fixture.provider.provider().inspect(a, selected, parent.response.?);
        if (inspected.schema != .valid) std.debug.print("selected shape {d}: {s}\n", .{ shape, try std.json.Stringify.valueAlloc(a, inspected, .{}) });
        try std.testing.expectEqual(.valid, inspected.schema);
        try std.testing.expectEqualStrings(parent.request.?, try fixture.provider.provider().prepare(a, selected));
        const invalid = try fixture.provider.provider().inspect(a, selected, try debugResponse(a, "{\"foreign\":true}"));
        try std.testing.expectEqual(.invalid, invalid.schema);
        const missing = try fixture.provider.provider().inspect(a, selected, try debugResponse(a, "{}"));
        try std.testing.expectEqual(.invalid, missing.schema);
        fixture.wire.inference_body = try debugResponse(a, response_text);
        const replayed = try fixture.replay().replay(a, replayIdentity("a" ** 32, 1), parent, .{ .call = 0, .mode = .exact });
        try std.testing.expectEqualStrings(parent.request.?, replayed.request.body);
        try std.testing.expectEqualStrings(parent.id, replayed.request.parent_call);
        _ = try fixture.replay().replay(a, replayIdentity("b" ** 32, 2), parent, .{ .call = 0, .mode = .modified, .edit = .{ .content = &.{ .{ .guidance = "Recheck the selected response." }, .{ .user = "Generate the selected data." } }, .schema = selected.schema } });
        try std.testing.expectEqual(@as(usize, 2), fixture.wire.calls);
        const obsolete = try std.mem.replaceOwned(u8, a, try std.json.Stringify.valueAlloc(a, selected, .{}), "model-request-debug/v9", "model-request-debug/v2");
        try std.testing.expectError(error.InvalidJsonDocument, debug.Description.decode(a, obsolete));
    };
}

fn debugResponse(a: std.mem.Allocator, content: []const u8) ![]const u8 {
    return std.json.Stringify.valueAlloc(a, .{ .output = .{ .message = .{ .role = "assistant", .content = .{.{ .text = content }} } }, .stopReason = "end_turn", .usage = .{ .inputTokens = 10, .outputTokens = 2, .totalTokens = 12 } }, .{});
}

test "replay serializes only the trusted model request profile and rejects legacy response bodies" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture: Fixture = undefined;
    try fixture.init(a);
    defer fixture.environment.deinit();
    var selected = description;
    selected.reasoning_effort = null;
    selected.controls.temperature = null;
    selected.response_mode = .native_schema;
    fixture.request_profile = .openai_luna;
    const body = try fixture.provider.provider().prepare(a, selected);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, body, .{});
    const fields = parsed.value.object.get("additionalModelRequestFields").?.object;
    try std.testing.expect(fields.get("text").?.object.get("format").?.object.get("strict").?.bool);
    try std.testing.expectEqual(@as(usize, 1), fields.count());
    try std.testing.expect(!fields.contains("reasoning_effort"));
    selected.reasoning_effort = "medium";
    try std.testing.expectError(error.InvalidReplay, fixture.provider.provider().prepare(a, selected));
    try std.testing.expectEqual(@as(usize, 0), fixture.wire.calls);
    const legacy = "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"{}\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}";
    try std.testing.expectEqual(.invalid, (try fixture.provider.provider().inspect(a, selected, legacy)).extraction);
}

const DebuggerSelectedShape = struct {
    schema: *const @import("domain/model_result_schema.zig").Schema,
    response: []const u8,
    fields: []const @import("domain/model_text_field.zig").Binding = &.{},
    restriction: ?*@import("domain/model_result_schema.zig").Restricted = null,
};

fn debuggerSelectedShape(a: std.mem.Allocator, compiler: @import("ports/model_result_schema_compiler.zig").Compiler, shape: usize) !DebuggerSelectedShape {
    if (shape == 0) return .{ .schema = try compiler.compile(a, schema), .response = "{\"answer\":\"kept\"}" };
    if (shape == 1) {
        const canonical = try compiler.compile(a,
            \\{"$defs":{"repair":{"type":"object","properties":{"enabled":{"type":"boolean"}},"required":["enabled"],"additionalProperties":false}},"type":"object","properties":{"whole":{"$ref":"#/$defs/repair"}},"required":["whole"],"additionalProperties":false}
        );
        return .{ .schema = canonical.select(.{ .bytes = "repair" }).?, .response = "{\"enabled\":true}" };
    }
    if (shape == 7) {
        const canonical = try compiler.compile(a, member_schema);
        const restriction = try @import("domain/model_result_schema.zig").restrict(a, canonical, &.{}, &.{.{ .target = .{ .path = member_path }, .allowed = &.{ 2, 4 }, .collection = .exact_members }});
        return .{ .schema = restriction.selected(), .response = "{\"findings\":[{\"ordinal\":4,\"note\":\"b\"},{\"ordinal\":2,\"note\":\"a\"}]}", .restriction = restriction };
    }
    if (shape == 5) {
        const canonical = try compiler.compile(a,
            \\{"oneOf":[{"type":"object","properties":{"kind":{"const":"keep"},"value":{"type":"string","maxLength":16}},"required":["kind","value"],"additionalProperties":false},{"type":"object","properties":{"kind":{"const":"drop"}},"required":["kind"],"additionalProperties":false}]}
        );
        const narrowed = try @import("domain/model_result_schema.zig").project(a, canonical, canonical.root().one_of[0]);
        // Compiled selected shapes may have a constant root discriminator; the
        // external complete-schema profile must still reject that root.
        try std.testing.expectError(error.InvalidModelResultSchema, compiler.compile(a, narrowed.modelBytes()));
        return .{ .schema = narrowed, .response = "{\"kind\":\"keep\",\"value\":\"original\"}" };
    }
    const raw = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/extraction.schema.json", a, .limited(1_048_576));
    const config = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/extraction.composition.json", a, .limited(1_048_576));
    const canonical = try compiler.compile(a, raw);
    const plan = try compiler.compileComposition(a, config, canonical);
    if (shape == 6) return debuggerExtractionShape(a, try plan.selectSchema(0, &.{}),
        \\{"kind":"claims","claims":[{"content":{"kind":"business","segments":{"fragments":["The application must start successfully.","When started, the application must display `Hello, World!`.","Should also output date and time in UTC."]}},"citations":[{"first":5,"last":7}]},{"content":{"kind":"technical","nodes":{"fragments":["The application displays the string `Hello, World!`.","The application outputs the current date and time in UTC."]}},"citations":[{"first":6,"last":7}]}]}
    );
    const content = "{\"kind\":\"no_feature_claim\",\"reason\":{\"nodes\":\"No feature behavior.\"}}";
    const prior = try std.json.parseFromSlice(std.json.Value, a, content, .{});
    if (shape == 2) return debuggerExtractionShape(a, try plan.selectSchema(0, &.{}), content);
    if (shape == 3) return debuggerExtractionShape(a, try plan.selectSchema(1, &.{.{ .part = 0, .value = prior.value }}), "{\"token_classifications\":[]}");
    const claim_prior = try std.json.parseFromSlice(std.json.Value, a, "{\"kind\":\"claims\",\"claims\":[]}", .{});
    return debuggerExtractionShape(a, try plan.selectSchema(1, &.{.{ .part = 0, .value = claim_prior.value }}), "{\"token_classifications\":[]}");
}

const member_schema = "{\"type\":\"object\",\"properties\":{\"findings\":{\"type\":\"array\",\"minItems\":1,\"maxItems\":8,\"items\":{\"type\":\"object\",\"properties\":{\"ordinal\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":8},\"note\":{\"type\":\"string\",\"maxLength\":16}},\"required\":[\"ordinal\",\"note\"],\"additionalProperties\":false}}},\"required\":[\"findings\"],\"additionalProperties\":false}";
const member_path: []const @import("domain/model_result_schema.zig").ChoiceStep = &.{ .{ .property = "findings" }, .{ .items = {} }, .{ .property = "ordinal" } };

/// A captured assignment request replays admission's native membership, which
/// the recorded provider schema bytes cannot express.
fn expectReplayedMembers(a: std.mem.Allocator, fixture: *Fixture, selected: debug.Description) !void {
    try std.testing.expectEqual(@as(usize, 1), selected.members.len);
    try std.testing.expectEqualSlices(i64, &.{ 2, 4 }, selected.members[0].allowed);
    const repeated = try debugResponse(a, "{\"findings\":[{\"ordinal\":2,\"note\":\"a\"},{\"ordinal\":2,\"note\":\"b\"}]}");
    const checked = try fixture.provider.provider().inspect(a, selected, repeated);
    try std.testing.expectEqual(.invalid, checked.schema);
    try std.testing.expectEqualStrings("duplicate_member", checked.reason.?);
    try std.testing.expectEqualStrings("/findings/1", checked.path.?);
    // Without the record the same bytes pass, so the record is what replays admission.
    var unrestricted = selected;
    unrestricted.members = &.{};
    try std.testing.expectEqual(.valid, (try fixture.provider.provider().inspect(a, unrestricted, repeated)).schema);
    // A record that does not fit the captured schema cannot be read or replayed.
    var foreign = selected;
    foreign.members = &.{.{ .path = member_path, .allowed = &.{ 2, 4, 6 } }};
    try std.testing.expectError(error.InvalidReplay, fixture.provider.provider().prepare(a, foreign));
    try std.testing.expectEqualStrings("Captured schema and native membership disagree", (try fixture.provider.provider().inspect(a, foreign, repeated)).reason.?);
    try std.testing.expectError(error.InvalidJsonDocument, debug.Description.decode(a, try std.json.Stringify.valueAlloc(a, foreign, .{})));
    try std.testing.expectEqualDeep(selected.members, (try debug.Description.decode(a, try std.json.Stringify.valueAlloc(a, selected, .{}))).members);
}

fn debuggerExtractionShape(a: std.mem.Allocator, selected: *const @import("domain/model_result_schema.zig").Schema, response: []const u8) !DebuggerSelectedShape {
    const fields = try @import("domain/model_candidate_json.zig").fieldBindings(@import("domain/reference_extraction_parser.zig").Response, a, .{ .reference_phase = .extraction });
    const restriction = try @import("domain/model_result_schema.zig").restrictFieldPolicies(a, selected, &.{}, &.{}, fields);
    return .{ .schema = restriction.selected(), .response = response, .fields = fields, .restriction = restriction };
}

test "selected diagnostic schema parsing retains closed syntax and bounded root rules" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture: Fixture = undefined;
    try fixture.init(a);
    defer fixture.environment.deinit();
    for ([_][]const u8{
        "{",
        "{\"type\":\"string\",\"maxLength\":16}",
        "{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":true}",
        "{\"type\":\"object\",\"properties\":{},\"required\":[\"missing\"],\"additionalProperties\":false}",
        "{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":false,\"unknown\":true}",
        "{\"$ref\":\"https://example.invalid/schema\"}",
    }) |invalid| {
        var selected = description;
        selected.schema = invalid;
        try std.testing.expectError(error.InvalidModelResultSchema, fixture.compiler.compiler().compileSelected(a, invalid));
        try std.testing.expectError(error.InvalidReplay, fixture.provider.provider().prepare(a, selected));
        const inspected = try fixture.provider.provider().inspect(a, selected, try debugResponse(a, "{}"));
        try std.testing.expectEqual(.unavailable, inspected.schema);
    }
    try std.testing.expectEqual(@as(usize, 0), fixture.wire.calls);
}

test "selected schema reconstruction does not reapply the source file size limit to expansion" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var adapter_instance: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const compiler = adapter_instance.compiler();
    var bytes: std.Io.Writer.Allocating = .init(a);
    try bytes.writer.writeAll("{\"$defs\":{\"label\":{\"enum\":[\"");
    try bytes.writer.writeAll("x" ** 40000);
    try bytes.writer.writeAll("\"]}},\"type\":\"object\",\"properties\":{");
    for (0..32) |i| {
        if (i != 0) try bytes.writer.writeByte(',');
        try bytes.writer.print("\"field{d}\":{{\"$ref\":\"#/$defs/label\"}}", .{i});
    }
    try bytes.writer.writeAll("},\"required\":[],\"additionalProperties\":false}");
    const canonical = try compiler.compile(a, bytes.written());
    try std.testing.expect(canonical.modelBytes().len > @import("domain/model_result_schema.zig").max_bytes);
    const rebuilt = try compiler.compileSelected(a, canonical.modelBytes());
    try std.testing.expectEqualStrings(canonical.modelBytes(), rebuilt.modelBytes());
    try std.testing.expectError(error.InvalidModelResultSchema, compiler.compile(a, canonical.modelBytes()));
}

test "debugger exposes provider reasoning separately including stopped and missing final answers" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture: Fixture = undefined;
    try fixture.init(a);
    defer fixture.environment.deinit();
    const supplied = "<script>alert('x')</script> & \"quoted\"\n🐈";
    for ([_][]const u8{ "end_turn", "max_tokens" }) |stop| {
        const bytes = try std.json.Stringify.valueAlloc(a, .{
            .output = .{ .message = .{ .role = "assistant", .content = .{
                .{ .reasoningContent = .{ .reasoningText = .{ .text = supplied, .signature = "opaque\"signature" } } },
                .{ .reasoningContent = .{ .redactedContent = "YQ==" } },
                .{ .reasoningContent = .{ .reasoningText = .{ .text = "second" } } },
                .{ .text = "{\"answer\":\"final\"}" },
            } } },
            .stopReason = stop,
            .usage = .{ .inputTokens = 10, .outputTokens = 2, .totalTokens = 12 },
        }, .{});
        const inspected = try fixture.provider.provider().inspect(a, description, bytes);
        try std.testing.expectEqual(@as(usize, 3), inspected.reasoning.len);
        try std.testing.expectEqualStrings(supplied, inspected.reasoning[0].text.text);
        try std.testing.expectEqualStrings("opaque\"signature", inspected.reasoning[0].text.signature.?);
        try std.testing.expectEqualStrings("YQ==", inspected.reasoning[1].redacted.base64);
        try std.testing.expectEqualStrings("second", inspected.reasoning[2].text.text);
        try std.testing.expectEqual(@as(?u64, 10), inspected.input_tokens);
        const exposed = try std.json.Stringify.valueAlloc(a, inspected, .{});
        var reparsed = try std.json.parseFromSlice(std.json.Value, a, exposed, .{});
        defer reparsed.deinit();
        const block = reparsed.value.object.get("reasoning").?.array.items[0].object.get("text").?.object;
        try std.testing.expectEqualStrings(supplied, block.get("text").?.string);
        if (std.mem.eql(u8, stop, "end_turn")) {
            try std.testing.expectEqual(.valid, inspected.schema);
            try std.testing.expectEqualStrings("{\"answer\":\"final\"}", inspected.model_text.?);
            try std.testing.expect(std.mem.indexOf(u8, inspected.model_text.?, supplied) == null);
        } else {
            try std.testing.expectEqual(.invalid, inspected.extraction);
            try std.testing.expectEqualStrings("output_limit", inspected.reason.?);
            try std.testing.expect(inspected.model_text == null);
            try std.testing.expectEqual(.unavailable, inspected.schema);
        }
    }
    const only_reasoning = "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"reasoningContent\":{\"reasoningText\":{\"text\":\"{\\\"answer\\\":\\\"reasoning cannot become an answer\\\"}\"}}}]}},\"stopReason\":\"end_turn\",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12}}";
    const missing = try fixture.provider.provider().inspect(a, description, only_reasoning);
    try std.testing.expectEqual(@as(usize, 1), missing.reasoning.len);
    try std.testing.expectEqual(.invalid, missing.extraction);
    try std.testing.expectEqualStrings("missing_final_text", missing.reason.?);
    try std.testing.expect(missing.model_text == null);
    try std.testing.expectEqual(.unavailable, missing.schema);
    const no_reasoning = try fixture.provider.provider().inspect(a, description, try debugResponse(a, "{\"answer\":\"plain\"}"));
    try std.testing.expectEqual(@as(usize, 0), no_reasoning.reasoning.len);
    // Embedded rendering uses text nodes for the exact provider text/signature,
    // including markup-shaped diagnostic strings; no HTML injection sink exists.
    const ui = @embedFile("debugger/app.js");
    try std.testing.expect(std.mem.indexOf(u8, ui, "p.append(reasoningView(v.reasoning))") != null);
    try std.testing.expect(std.mem.indexOf(u8, ui, "e.textContent = String(text)") != null);
    try std.testing.expect(std.mem.indexOf(u8, ui, "innerHTML") == null);
    // Every engine normalization is displayed separately from the raw response.
    inline for (comptime std.meta.tags(@import("domain/model_envelope.zig").Normalization)) |rule| {
        if (rule != .none) try std.testing.expect(std.mem.indexOf(u8, ui, @tagName(rule) ++ ":") != null);
    }
}
