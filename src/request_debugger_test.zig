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
    .provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2" } },
    .model_slot = "generation",
    .workflow_id = "spec",
    .workflow_version = 1,
    .request_step = "generation-prepare",
    .content = &.{ .{ .guidance = "Generate an answer." }, .{ .user = "{\"claims\":[\"one\",\"two\"]}" } },
    .protocol_prompt = @import("domain/model_controls.zig").response_format_guidance,
    .schema = schema,
    .response_mode = .prompt_only,
    .controls = .{ .temperature = .zero },
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
    fn init(self: *Fixture, a: std.mem.Allocator) !void {
        self.* = .{ .environment = .init(a) };
        try self.environment.put("AWS_BEARER_TOKEN_BEDROCK", "test-secret-never-log");
        self.provider = .{ .authorization = .{ .context = @ptrCast(self), .authorize_fn = authorize }, .environment = &self.environment, .transport = self.wire.port(), .clock = .{ .context = @ptrCast(self), .now_fn = now }, .compiler = self.compiler.compiler() };
    }
    fn authorize(ctx: *port.Context, value: debug.Description) port.Error!void {
        const self: *Fixture = @ptrCast(@alignCast(ctx));
        if (self.denied or !std.mem.eql(u8, value.model, description.model)) return error.ReplayUnauthorized;
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
    const response = try std.json.Stringify.valueAlloc(a, .{ .output = .{ .message = .{ .role = "assistant", .content = .{.{ .text = "{\"answer\":null}" }} } }, .stopReason = "end_turn", .usage = .{ .inputTokens = 10, .outputTokens = 2, .totalTokens = 12 } }, .{});
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

const LogSink = struct {
    a: std.mem.Allocator,
    rows: std.ArrayList(u8) = .empty,
    events: std.ArrayList(u8) = .empty,
    sequence: u64 = 0,
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
    var partial: archive.Archive = .{ .allocator = a };
    const last_line = std.mem.lastIndexOfScalar(u8, sink.rows.items[0 .. request_end - 1], '\n').? + 1;
    try partial.ingest(sink.rows.items[0..last_line]);
    try std.testing.expect(!(try partial.calls())[0].request_complete);
    var duplicate: archive.Archive = .{ .allocator = a };
    try duplicate.ingest(sink.rows.items);
    try std.testing.expectError(error.InvalidDebugArchive, duplicate.ingest(sink.rows.items));
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
    production.request.response_schema = try fixture.compiler.compiler().compile(production.schema_arena.allocator(), schema);
    for ([_]@import("domain/model_controls.zig").ResponseGuidanceMode{ .prompt_only, .native_schema }) |mode| {
        production.request.response_guidance_mode = mode;
        production.provider_binding.response_mode = mode;
        const captured = try @import("adapters/provider/bedrock_request.zig").encode(a, &production.request, .inference);
        const projection = debug.Description.from(&production.request, &production.provider_binding, .inference);
        const serialized = try std.json.Stringify.valueAlloc(a, projection, .{});
        const restored = try debug.Description.decode(a, serialized);
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
    metadata.source = origin;
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
    const legacy_bytes = try std.mem.replaceOwned(u8, a, duplicate_bytes, "request-replay/v3", "request-replay/v2");
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
