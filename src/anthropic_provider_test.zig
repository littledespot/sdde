//! Anthropic Messages codec and shared-adapter tests (ADR 0028). No network:
//! a recording transport stands in for the shared HTTPS exchange.
const std = @import("std");
const operation = @import("domain/llm_provider_operation.zig");
const fixture_module = @import("provider_authorization_test_fixture.zig");
const authorization = @import("adapters/provider/api_key_authorization.zig");
const key = @import("adapters/provider/provider_api_key.zig");
const shared_provider = @import("adapters/provider/model_provider.zig");
const transport = @import("adapters/provider/model_http_transport.zig");
const contracts = @import("composition/provider_model_contracts.zig");
const decoder = @import("adapters/provider/anthropic_response.zig");
const support = @import("adapters/provider/provider_response_support.zig");
const assembly = @import("adapters/provider/provider_response_assembly.zig");

const model = "claude-haiku-5-5";

/// One documented response with every field present; `@@` markers are replaced.
fn message(a: std.mem.Allocator, replacements: []const [2][]const u8) ![]const u8 {
    var body: []const u8 = "{\"id\":\"msg_1\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"claude-haiku-5-5\"," ++
        "\"content\":@@CONTENT,\"stop_reason\":@@STOP,\"stop_sequence\":@@SEQUENCE,\"stop_details\":@@DETAILS," ++
        "\"usage\":@@USAGE,\"container\":null,\"diagnostics\":null}";
    const defaults = [_][2][]const u8{
        .{ "@@CONTENT", "[{\"type\":\"thinking\",\"thinking\":\"\",\"signature\":\"sig\"},{\"type\":\"text\",\"text\":\"{\\\"a\\\":\",\"citations\":null},{\"type\":\"text\",\"text\":\"1}\",\"citations\":null}]" },
        .{ "@@STOP", "\"end_turn\"" },
        .{ "@@SEQUENCE", "null" },
        .{ "@@DETAILS", "null" },
        .{ "@@USAGE", usage_default },
    };
    // Edits of the template itself first, then placeholder values, then edits
    // inside the filled defaults.
    for (replacements) |replacement| if (!std.mem.startsWith(u8, replacement[0], "@@") and std.mem.indexOf(u8, replacement[0], "@@") != null) {
        body = try std.mem.replaceOwned(u8, a, body, replacement[0], replacement[1]);
    };
    for (defaults) |default| {
        var value = default[1];
        for (replacements) |replacement| if (std.mem.eql(u8, replacement[0], default[0])) {
            value = replacement[1];
        };
        body = try std.mem.replaceOwned(u8, a, body, default[0], value);
    }
    for (replacements) |replacement| if (std.mem.indexOf(u8, replacement[0], "@@") == null) {
        body = try std.mem.replaceOwned(u8, a, body, replacement[0], replacement[1]);
    };
    return body;
}

const usage_default = "{\"input_tokens\":10,\"output_tokens\":5,\"cache_creation_input_tokens\":2,\"cache_read_input_tokens\":3," ++
    "\"cache_creation\":{\"ephemeral_1h_input_tokens\":0,\"ephemeral_5m_input_tokens\":2},\"output_tokens_details\":{\"thinking_tokens\":3}," ++
    "\"server_tool_use\":null,\"service_tier\":\"standard\",\"inference_geo\":\"global\",\"speed\":\"standard\"}";

fn decode(a: std.mem.Allocator, body: []const u8) !assembly.Inference {
    var parsed = try support.parse(a, body);
    defer parsed.deinit();
    return decoder.decodeMessages(a, parsed.value, model, null);
}

test "Messages decoding joins text exactly, keeps thinking as reasoning and counts inclusive usage once" {
    const a = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    var decoded = try decode(a, try message(arena.allocator(), &.{}));
    defer decoded.deinit(a);
    try std.testing.expectEqualStrings("{\"a\":1}", decoded.output.text);
    // input 10 + cache read 3 + cache write 2; thinking is already in output.
    try std.testing.expectEqual(@as(u64, 15), decoded.usage.input_tokens);
    try std.testing.expectEqual(@as(u64, 5), decoded.usage.output_tokens);
    try std.testing.expectEqual(@as(u64, 20), decoded.usage.total_tokens);
    try std.testing.expectEqual(@as(?u32, null), decoded.latency_ms);
    try std.testing.expectEqual(@as(usize, 1), decoded.reasoning.len);
    try std.testing.expectEqualStrings("sig", decoded.reasoning[0].text.signature.?);
}

test "Messages decoding accepts every documented null and the redacted thinking block" {
    const a = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const nulls = "{\"input_tokens\":4,\"output_tokens\":1,\"cache_creation_input_tokens\":null,\"cache_read_input_tokens\":null,\"cache_creation\":null,\"output_tokens_details\":null,\"server_tool_use\":{\"web_fetch_requests\":0,\"web_search_requests\":0},\"service_tier\":null,\"inference_geo\":null,\"speed\":null}";
    var decoded = try decode(a, try message(arena.allocator(), &.{
        .{ "@@USAGE", nulls },
        .{ "@@CONTENT", "[{\"type\":\"redacted_thinking\",\"data\":\"opaque\"},{\"type\":\"text\",\"text\":\"{}\",\"citations\":null}]" },
    }));
    defer decoded.deinit(a);
    try std.testing.expectEqualStrings("{}", decoded.output.text);
    try std.testing.expectEqual(@as(u64, 5), decoded.usage.total_tokens);
    try std.testing.expectEqualStrings("opaque", decoded.reasoning[0].redacted.base64);
}

test "Messages stop reasons map to typed non-candidate stops" {
    const a = std.testing.allocator;
    const cases = [_]struct { stop: []const u8, sequence: []const u8 = "null", details: []const u8 = "null", expected: ?operation.ProviderNonCandidateStopReason }{
        .{ .stop = "\"end_turn\"", .expected = null },
        .{ .stop = "\"max_tokens\"", .expected = .output_limit },
        .{ .stop = "\"model_context_window_exceeded\"", .expected = .context_limit },
        .{ .stop = "\"refusal\"", .expected = .content_filtered },
        .{ .stop = "\"refusal\"", .details = "{\"type\":\"refusal\",\"category\":\"cyber\",\"explanation\":null}", .expected = .content_filtered },
        .{ .stop = "\"refusal\"", .details = "{\"type\":\"refusal\",\"category\":null,\"explanation\":\"declined\"}", .expected = .content_filtered },
        .{ .stop = "\"tool_use\"", .expected = .unsupported_tool_request },
        .{ .stop = "\"pause_turn\"", .expected = .unsupported_tool_request },
        .{ .stop = "\"stop_sequence\"", .sequence = "\"END\"", .expected = .malformed_output },
    };
    for (cases) |case| {
        var arena: std.heap.ArenaAllocator = .init(a);
        defer arena.deinit();
        var decoded = try decode(a, try message(arena.allocator(), &.{ .{ "@@STOP", case.stop }, .{ "@@SEQUENCE", case.sequence }, .{ "@@DETAILS", case.details } }));
        defer decoded.deinit(a);
        if (case.expected) |reason| {
            try std.testing.expectEqual(reason, decoded.output.stopped);
        } else try std.testing.expect(decoded.output == .text);
        // Usage is retained on every stop.
        try std.testing.expectEqual(@as(u64, 20), decoded.usage.total_tokens);
    }
}

test "Messages content defects reject the candidate but keep trusted usage" {
    const a = std.testing.allocator;
    const cases = [_]struct { replacements: []const [2][]const u8, expected: operation.ProviderContentDiagnostic }{
        .{ .replacements = &.{.{ "@@CONTENT", "[{\"type\":\"tool_use\",\"id\":\"t\",\"name\":\"n\",\"input\":{}},{\"type\":\"text\",\"text\":\"{}\",\"citations\":null}]" }}, .expected = .invalid_content },
        .{ .replacements = &.{.{ "@@CONTENT", "[{\"type\":\"text\",\"text\":\"{}\",\"citations\":[]}]" }}, .expected = .invalid_content },
        .{ .replacements = &.{.{ "@@CONTENT", "[{\"type\":\"text\",\"text\":\"{}\"}]" }}, .expected = .invalid_content },
        .{ .replacements = &.{.{ "@@CONTENT", "[{\"type\":\"text\",\"text\":\"{}\",\"citations\":null,\"extra\":1}]" }}, .expected = .invalid_content },
        .{ .replacements = &.{.{ "@@CONTENT", "[{\"type\":\"thinking\",\"thinking\":\"\"},{\"type\":\"text\",\"text\":\"{}\",\"citations\":null}]" }}, .expected = .invalid_content },
        .{ .replacements = &.{.{ "@@CONTENT", "[{\"type\":\"Text\",\"text\":\"{}\",\"citations\":null}]" }}, .expected = .invalid_content },
        .{ .replacements = &.{.{ "@@CONTENT", "[{\"type\":\"text\",\"text\":\" \\n\",\"citations\":null}]" }}, .expected = .missing_final_text },
        .{ .replacements = &.{.{ "@@CONTENT", "[{\"type\":\"thinking\",\"thinking\":\"\",\"signature\":\"s\"}]" }}, .expected = .missing_final_text },
        .{ .replacements = &.{.{ "@@CONTENT", "{}" }}, .expected = .invalid_content },
        // Inconsistent stop metadata, unknown stops and exact casing.
        .{ .replacements = &.{.{ "@@DETAILS", "{\"type\":\"refusal\",\"category\":null,\"explanation\":null}" }}, .expected = .invalid_content },
        .{ .replacements = &.{.{ "@@SEQUENCE", "\"END\"" }}, .expected = .invalid_content },
        .{ .replacements = &.{.{ "@@STOP", "\"stop_sequence\"" }}, .expected = .invalid_content },
        .{ .replacements = &.{.{ "@@STOP", "\"End_turn\"" }}, .expected = .invalid_content },
        .{ .replacements = &.{.{ "@@STOP", "null" }}, .expected = .invalid_content },
        .{ .replacements = &.{ .{ "@@STOP", "\"refusal\"" }, .{ "@@DETAILS", "{\"type\":\"refusal\",\"category\":\"unlisted\",\"explanation\":null}" } }, .expected = .invalid_content },
        .{ .replacements = &.{ .{ "@@STOP", "\"refusal\"" }, .{ "@@DETAILS", "{\"type\":\"refusal\",\"category\":null}" } }, .expected = .invalid_content },
    };
    for (cases) |case| {
        var arena: std.heap.ArenaAllocator = .init(a);
        defer arena.deinit();
        var decoded = try decode(a, try message(arena.allocator(), case.replacements));
        defer decoded.deinit(a);
        try std.testing.expectEqual(case.expected, decoded.output.invalid);
        try std.testing.expectEqual(@as(u64, 20), decoded.usage.total_tokens);
    }
}

test "Messages envelope and usage defects reject the whole response with a precise path" {
    const a = std.testing.allocator;
    const cases = [_]struct { replacements: []const [2][]const u8, path: ?[]const u8 = null }{
        .{ .replacements = &.{.{ "\"diagnostics\":null}", "\"diagnostics\":null,\"extra\":1}" }}, .path = "/extra" },
        .{ .replacements = &.{.{ ",\"diagnostics\":null}", "}" }} },
        .{ .replacements = &.{.{ ",\"stop_details\":@@DETAILS", "" }} },
        .{ .replacements = &.{.{ "\"type\":\"message\"", "\"type\":\"Message\"" }} },
        .{ .replacements = &.{.{ "\"role\":\"assistant\"", "\"role\":\"user\"" }} },
        .{ .replacements = &.{.{ "\"model\":\"claude-haiku-5-5\"", "\"model\":\"claude-opus-5-5\"" }} },
        .{ .replacements = &.{.{ "\"id\":\"msg_1\"", "\"id\":\"\"" }} },
        .{ .replacements = &.{.{ "\"container\":null", "\"container\":{}" }} },
        .{ .replacements = &.{.{ "\"diagnostics\":null", "\"diagnostics\":{}" }} },
        .{ .replacements = &.{.{ "\"speed\":\"standard\"}", "\"speed\":\"standard\",\"unlisted\":0}" }}, .path = "/usage/unlisted" },
        .{ .replacements = &.{.{ ",\"speed\":\"standard\"", "" }} },
        .{ .replacements = &.{.{ "\"input_tokens\":10", "\"input_tokens\":-1" }} },
        .{ .replacements = &.{.{ "\"input_tokens\":10", "\"input_tokens\":1.5" }} },
        .{ .replacements = &.{.{ "\"input_tokens\":10", "\"input_tokens\":\"10\"" }} },
        .{ .replacements = &.{.{ "\"input_tokens\":10", "\"input_tokens\":null" }} },
        .{ .replacements = &.{.{ "\"output_tokens\":5", "\"output_tokens\":18446744073709551616" }} },
        .{ .replacements = &.{.{ "\"ephemeral_5m_input_tokens\":2", "\"ephemeral_5m_input_tokens\":1" }} },
        .{ .replacements = &.{.{ "\"cache_creation\":{\"ephemeral_1h_input_tokens\":0,\"ephemeral_5m_input_tokens\":2}", "\"cache_creation\":{}" }} },
        .{ .replacements = &.{.{ "\"thinking_tokens\":3", "\"thinking_tokens\":6" }} },
        .{ .replacements = &.{.{ "\"output_tokens_details\":{\"thinking_tokens\":3}", "\"output_tokens_details\":{}" }} },
        .{ .replacements = &.{.{ "\"server_tool_use\":null", "\"server_tool_use\":{\"web_fetch_requests\":1,\"web_search_requests\":0}" }} },
        .{ .replacements = &.{.{ "\"service_tier\":\"standard\"", "\"service_tier\":\"flex\"" }} },
        .{ .replacements = &.{.{ "\"speed\":\"standard\"", "\"speed\":\"turbo\"" }} },
        .{ .replacements = &.{.{ "\"inference_geo\":\"global\"", "\"inference_geo\":1" }} },
    };
    for (cases) |case| {
        var arena: std.heap.ArenaAllocator = .init(a);
        defer arena.deinit();
        var parsed = try support.parse(a, try message(arena.allocator(), case.replacements));
        defer parsed.deinit();
        var diagnostic: ?support.DecodeDiagnostic = null;
        defer if (diagnostic) |value| value.deinit(a);
        try std.testing.expectError(error.InvalidResponse, decoder.decodeMessages(a, parsed.value, model, &diagnostic));
        try std.testing.expect(diagnostic != null);
        if (case.path) |path| {
            try std.testing.expectEqualStrings(path, diagnostic.?.path);
            try std.testing.expectEqual(.unknown_field, diagnostic.?.reason);
        }
    }
}

test "Messages errors classify only by matching status and error type" {
    const a = std.testing.allocator;
    const Case = struct { status: u16, body: []const u8, cause: operation.ProviderFailureCause, retry: operation.ProviderRetryClass };
    const cases = [_]Case{
        .{ .status = 400, .body = "{\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"m\"},\"request_id\":\"req_1\"}", .cause = .request_rejected, .retry = .never },
        .{ .status = 401, .body = "{\"type\":\"error\",\"error\":{\"type\":\"authentication_error\",\"message\":\"m\"}}", .cause = .authentication_failed, .retry = .never },
        .{ .status = 402, .body = "{\"type\":\"error\",\"error\":{\"type\":\"billing_error\",\"message\":\"m\"}}", .cause = .authorization_denied, .retry = .never },
        .{ .status = 403, .body = "{\"type\":\"error\",\"error\":{\"type\":\"permission_error\",\"message\":\"m\"}}", .cause = .authorization_denied, .retry = .never },
        .{ .status = 404, .body = "{\"type\":\"error\",\"error\":{\"type\":\"not_found_error\",\"message\":\"m\"}}", .cause = .model_unavailable, .retry = .never },
        .{ .status = 413, .body = "{\"type\":\"error\",\"error\":{\"type\":\"request_too_large\",\"message\":\"m\"}}", .cause = .request_rejected, .retry = .never },
        .{ .status = 429, .body = "{\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\",\"message\":\"m\"}}", .cause = .throttled, .retry = .policy_eligible },
        .{ .status = 429, .body = "{\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\",\"message\":\"m\",\"details\":{\"error_code\":\"enforced_spend_limit_reached\"}},\"request_id\":\"req_2\"}", .cause = .authorization_denied, .retry = .never },
        .{ .status = 500, .body = "{\"type\":\"error\",\"error\":{\"type\":\"api_error\",\"message\":\"m\"}}", .cause = .service_unavailable, .retry = .policy_eligible },
        .{ .status = 504, .body = "{\"type\":\"error\",\"error\":{\"type\":\"timeout_error\",\"message\":\"m\"}}", .cause = .timeout, .retry = .policy_eligible },
        .{ .status = 529, .body = "{\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"m\"}}", .cause = .service_unavailable, .retry = .policy_eligible },
        // Mismatched pairs, unknown types, foreign details and malformed bodies.
        .{ .status = 400, .body = "{\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\",\"message\":\"m\"}}", .cause = .response_invalid, .retry = .never },
        .{ .status = 409, .body = "{\"type\":\"error\",\"error\":{\"type\":\"conflict_error\",\"message\":\"m\"}}", .cause = .response_invalid, .retry = .never },
        .{ .status = 400, .body = "{\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"m\",\"details\":{\"error_code\":\"enforced_spend_limit_reached\"}}}", .cause = .response_invalid, .retry = .never },
        .{ .status = 429, .body = "{\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\",\"message\":\"m\",\"details\":{\"error_code\":\"other\"}}}", .cause = .response_invalid, .retry = .never },
        .{ .status = 429, .body = "{\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\",\"message\":\"m\",\"details\":{}}}", .cause = .response_invalid, .retry = .never },
        .{ .status = 400, .body = "{\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\"}}", .cause = .response_invalid, .retry = .never },
        .{ .status = 400, .body = "{\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"m\"},\"extra\":1}", .cause = .response_invalid, .retry = .never },
        .{ .status = 400, .body = "{\"type\":\"failure\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"m\"}}", .cause = .response_invalid, .retry = .never },
        .{ .status = 413, .body = "<html>Request Entity Too Large</html>", .cause = .response_invalid, .retry = .never },
        .{ .status = 400, .body = "{\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"m\"},\"type\":\"error\"}", .cause = .response_invalid, .retry = .never },
    };
    for (cases) |case| {
        const classified = (try decoder.classifyResponse(a, .{ .received = .{ .status = case.status, .body = case.body } })).?;
        try std.testing.expectEqual(case.cause, classified.cause);
        try std.testing.expectEqual(case.retry, classified.retry_class);
        try std.testing.expectEqual(.response_received, classified.delivery);
    }
    try std.testing.expect(try decoder.classifyResponse(a, .{ .received = .{ .status = 200, .body = "{}" } }) == null);
}

/// Records the one exchange and answers with a configured response.
const RecordingWire = struct {
    allocator: std.mem.Allocator,
    calls: usize = 0,
    target: ?std.meta.Tag(transport.Target) = null,
    body: ?[]u8 = null,
    api_key_matches: bool = false,
    expected_key: []const u8 = "",
    result: transport.Response,

    fn port(self: *RecordingWire) transport.Port {
        return .{ .context = @ptrCast(self), .exchange_fn = exchange };
    }

    fn deinit(self: *RecordingWire) void {
        if (self.body) |bytes| self.allocator.free(bytes);
    }

    fn exchange(context: *transport.Context, _: std.mem.Allocator, request: transport.Request) transport.Error!transport.Response {
        const self: *RecordingWire = @ptrCast(@alignCast(context));
        self.calls += 1;
        self.target = std.meta.activeTag(request.target);
        if (self.body) |bytes| self.allocator.free(bytes);
        self.body = try self.allocator.dupe(u8, request.body);
        self.api_key_matches = std.mem.eql(u8, request.api_key, self.expected_key);
        std.debug.assert(std.mem.indexOf(u8, request.body, request.api_key) == null);
        return self.result;
    }
};

const AdapterFixture = struct {
    base: fixture_module.Fixture,
    auth: authorization.Adapter,
    wire: RecordingWire,
    provider: shared_provider.Provider,
    canary: [48]u8,

    fn init(self: *AdapterFixture, allocator: std.mem.Allocator, result: transport.Response) !void {
        try self.base.init(allocator);
        errdefer self.base.deinit();
        const config: @import("domain/llm_provider_contracts.zig").ValidatedProviderConfig = .{ .anthropic = .{ .max_output_tokens = .{ .tokens = 128000 }, .request_timeout = .{ .milliseconds = 180000 } } };
        const contract = contracts.registry.resolve(.{ .bytes = "anthropic" }, .{ .bytes = model }, config).?.*;
        self.base.registry_entry.provider = contract.provider;
        self.base.registry_entry.model = contract.model.?;
        self.base.registry_entry.implementation_id = contract.implementation_id;
        self.base.registry_entry.capabilities = contract.capabilities;
        self.base.registry_entry.facts = contract.facts;
        self.base.registry_entry.config = config;
        self.base.registry_entry.supported_reasoning_efforts = contract.supported_reasoning_efforts;
        self.base.provider_binding.reasoning_effort = "low";
        self.base.provider_binding.controls = contract.capabilities.inferenceControls(@import("test_fixtures/model_temperatures.zig").temperatures);
        self.base.request.controls = self.base.provider_binding.controls;
        self.base.request.binding_id = self.base.provider_binding.bindingId();
        self.auth = .{ .allocator = allocator };
        std.testing.io.random(&self.canary);
        for (&self.canary) |*byte| byte.* = 'A' + byte.* % 26;
        self.auth.materials.set(.anthropic, .{ .ready = (try key.Snapshot.capture(allocator, &self.canary)).? });
        self.wire = .{ .allocator = allocator, .expected_key = &self.canary, .result = result };
        self.provider = .{ .allocator = allocator, .authorization_leases = self.base.leasePort(), .transport = self.wire.port() };
    }

    fn deinit(self: *AdapterFixture) void {
        self.wire.deinit();
        self.auth.deinit();
        self.base.deinit();
        std.crypto.secureZero(u8, &self.canary);
    }

    fn start(self: *AdapterFixture) !fixture_module.Authorized {
        try self.base.assignInference();
        var preparation = self.base.preparationRunner();
        preparation.prepare_action.authorization = self.auth.port();
        const prepared = try preparation.prepare(self.base.facts(.inference));
        return .{ .reference = prepared.prepared, .invoked = try self.base.invoke(.inference) };
    }
};

test "the shared provider adapter sends one Messages request with the Anthropic key and decodes its candidate" {
    const a = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    var fixture: AdapterFixture = undefined;
    try fixture.init(a, .{ .received = .{ .status = 200, .request_id = "req_1", .body = try message(arena.allocator(), &.{}) } });
    defer fixture.deinit();
    const authorized = try fixture.start();
    var observed = try fixture.provider.port().invoke(&fixture.base.provider_binding, &fixture.base.request, authorized.reference, authorized.invoked);
    defer observed.deinit();
    try std.testing.expectEqual(@as(usize, 1), fixture.wire.calls);
    try std.testing.expectEqual(.anthropic, fixture.wire.target.?);
    try std.testing.expect(fixture.wire.api_key_matches);
    var sent = try std.json.parseFromSlice(std.json.Value, a, fixture.wire.body.?, .{});
    defer sent.deinit();
    try std.testing.expectEqualStrings(model, sent.value.object.get("model").?.string);
    try std.testing.expectEqual(@as(i64, 128000), sent.value.object.get("max_tokens").?.integer);
    try std.testing.expectEqualStrings("low", sent.value.object.get("output_config").?.object.get("effort").?.string);
    try std.testing.expect(sent.value.object.get("output_config").?.object.get("format") == null);
    try std.testing.expect(!sent.value.object.contains("temperature"));
    const complete = observed.completed.raw_result.complete;
    try std.testing.expectEqualStrings("{\"a\":1}", complete.content.bytes);
    try std.testing.expectEqual(@as(u64, 20), complete.usage.total_tokens);
}

test "an Anthropic binding never authorizes with another family's key" {
    const a = std.testing.allocator;
    var fixture: AdapterFixture = undefined;
    try fixture.init(a, .{ .received = .{ .status = 200, .body = "{}" } });
    defer fixture.deinit();
    // Only a Bedrock key exists; the Anthropic family stays unavailable.
    fixture.auth.materials.set(.anthropic, .unavailable);
    fixture.auth.materials.set(.aws_bedrock, .{ .ready = (try key.Snapshot.capture(a, &fixture.canary)).? });
    try fixture.base.change(.inference, .{ .assign_inference = fixture.base.assignment() });
    var preparation = fixture.base.preparationRunner();
    preparation.prepare_action.authorization = fixture.auth.port();
    const prepared = try preparation.prepare(fixture.base.facts(.inference));
    try std.testing.expect(prepared == .failed);
    try std.testing.expectEqual(@as(usize, 0), fixture.wire.calls);
}

test "Anthropic failures keep their typed causes" {
    const a = std.testing.allocator;
    var fixture: AdapterFixture = undefined;
    try fixture.init(a, .{ .received = .{ .status = 429, .body = "{\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\",\"message\":\"m\",\"details\":{\"error_code\":\"enforced_spend_limit_reached\"}}}" } });
    defer fixture.deinit();
    const authorized = try fixture.start();
    var observed = try fixture.provider.port().invoke(&fixture.base.provider_binding, &fixture.base.request, authorized.reference, authorized.invoked);
    defer observed.deinit();
    try std.testing.expectEqual(.authorization_denied, observed.failed.cause);
    try std.testing.expectEqual(.never, observed.failed.retry_class);
    try std.testing.expectEqual(@as(usize, 1), fixture.wire.calls);
}

test "a request altered after authorization, here adding temperature, is denied before send" {
    const a = std.testing.allocator;
    var fixture: AdapterFixture = undefined;
    try fixture.init(a, .{ .received = .{ .status = 200, .body = "{}" } });
    defer fixture.deinit();
    const authorized = try fixture.start();
    // The lease binds the exact authorized request, so a changed control never
    // reaches encoding; the encoder's own test rejects temperature as well.
    var request = fixture.base.request;
    request.controls = .{ .temperatures = @import("test_fixtures/model_temperatures.zig").temperatures };
    var observed = try fixture.provider.port().invoke(&fixture.base.provider_binding, &request, authorized.reference, authorized.invoked);
    defer observed.deinit();
    try std.testing.expectEqual(.authorization_denied, observed.failed.cause);
    try std.testing.expectEqual(.not_sent, observed.failed.delivery);
    try std.testing.expectEqual(@as(usize, 0), fixture.wire.calls);
}
