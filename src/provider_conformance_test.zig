const std = @import("std");
const operation = @import("domain/llm_provider_operation.zig");
const fixture_module = @import("provider_authorization_test_fixture.zig");
const authorization = @import("adapters/provider/api_key_authorization.zig");
const key = @import("adapters/provider/provider_api_key.zig");
const shared_provider = @import("adapters/provider/model_provider.zig");
const transport = @import("adapters/provider/model_http_transport.zig");
const fake = @import("adapters/provider/fake_llm_provider.zig");
const contracts = @import("composition/provider_model_contracts.zig");
const test_contracts = @import("model_contract_test_fixture.zig");
const response = @import("adapters/provider/bedrock_response.zig");
const strict = @import("domain/strict_json.zig");
const capture_port = @import("ports/model_exchange_capture.zig");
const prompt_log = @import("domain/sanitized_prompt_log.zig");

test {
    _ = @import("model_http_test.zig");
    _ = @import("anthropic_provider_test.zig");
    _ = @import("domain/llm_provider_contracts.zig");
    _ = @import("domain/provider_failure.zig");
    _ = @import("adapters/provider/model_text_request.zig");
    _ = @import("adapters/provider/anthropic_request.zig");
    _ = @import("adapters/provider/api_key_authorization.zig");
}

const Backend = enum { fake, bedrock };
const Wire = @import("model_transport_test_fixture.zig").Wire;

const CaptureSpy = struct {
    allocator: std.mem.Allocator,
    expected_secret: []const u8,
    calls: std.ArrayList(Call) = .empty,
    block_direction: ?prompt_log.PromptDirection = null,
    allocation_failed: bool = false,

    const Call = struct {
        direction: prompt_log.PromptDirection,
        body: []u8,
        kind: std.meta.Tag(capture_port.Body),
        credential_matches: bool,
    };

    fn port(self: *CaptureSpy) capture_port.Port {
        return .{ .context = @ptrCast(self), .capture_fn = capture };
    }

    fn deinit(self: *CaptureSpy) void {
        for (self.calls.items) |call| self.allocator.free(call.body);
        self.calls.deinit(self.allocator);
    }

    fn capture(context: *capture_port.Context, direction: prompt_log.PromptDirection, body: capture_port.Body, credentials: []const []const u8) capture_port.Outcome {
        const self: *CaptureSpy = @ptrCast(@alignCast(context));
        const owned = (switch (body) {
            .provider_body, .partial_provider_body => |bytes| self.allocator.dupe(u8, bytes),
            .transport_outcome => |outcome| std.json.Stringify.valueAlloc(self.allocator, outcome, .{}),
        }) catch {
            self.allocation_failed = true;
            return .blocked;
        };
        self.calls.append(self.allocator, .{
            .direction = direction,
            .body = owned,
            .kind = std.meta.activeTag(body),
            .credential_matches = credentials.len == 1 and std.mem.eql(u8, credentials[0], self.expected_secret),
        }) catch {
            self.allocator.free(owned);
            self.allocation_failed = true;
            return .blocked;
        };
        return if (self.block_direction == direction) .blocked else .recorded;
    }
};

const CaptureObservedWire = struct {
    inner: *Wire,
    capture: *CaptureSpy,
    request_matches_prior_capture: bool = false,
    fail_allocation: bool = false,

    fn port(self: *CaptureObservedWire) transport.Port {
        return .{ .context = @ptrCast(self), .exchange_fn = exchange };
    }

    fn exchange(context: *transport.Context, allocator: std.mem.Allocator, request: transport.Request) transport.Error!transport.Response {
        const self: *CaptureObservedWire = @ptrCast(@alignCast(context));
        self.request_matches_prior_capture = self.capture.calls.items.len == 1 and
            self.capture.calls.items[0].direction == .request and
            std.mem.eql(u8, self.capture.calls.items[0].body, request.body);
        if (self.fail_allocation) return error.OutOfMemory;
        return self.inner.port().exchange(allocator, request);
    }
};

const Fixture = struct {
    base: fixture_module.Fixture,
    auth: authorization.Adapter,
    wire: Wire,
    real: shared_provider.Provider,
    fake_provider: fake.FakeLLMProvider,
    backend: Backend,

    fn init(self: *Fixture, allocator: std.mem.Allocator, backend: Backend) !void {
        try self.base.init(allocator);
        errdefer self.base.deinit();
        const model: @import("domain/llm_provider_identity.zig").ModelId = .{ .bytes = test_contracts.bedrock_model_ids[0] };
        const config: @import("domain/llm_provider_contracts.zig").ValidatedProviderConfig = .{ .aws_bedrock = .{ .region = std.enums.values(@import("domain/llm_provider_contracts.zig").BedrockRegion)[0], .family = .converse, .max_output_tokens = .{ .tokens = 16000 }, .request_timeout = .{ .milliseconds = 180000 } } };
        const contract = contracts.registry.resolve(.{ .bytes = "aws-bedrock" }, model, config).?.*;
        self.base.registry_entry.provider = contract.provider;
        self.base.registry_entry.model = model;
        // The synthetic test capability contract, not a compiled family's (ADR 0029).
        self.base.registry_entry.capabilities = test_contracts.capabilities;
        self.base.registry_entry.facts = contract.facts;
        self.base.registry_entry.config = config;
        self.base.registry_entry.supported_reasoning_efforts = &.{};
        self.base.provider_binding.reasoning_effort = null;
        self.base.provider_binding.controls = test_contracts.capabilities.inferenceControls();
        self.base.request.controls = self.base.provider_binding.controls;
        self.base.request.binding_id = self.base.provider_binding.bindingId();
        self.auth = .{ .allocator = allocator };
        var canary: [48]u8 = undefined;
        std.testing.io.random(&canary);
        for (&canary) |*byte| byte.* = 'A' + byte.* % 26;
        defer std.crypto.secureZero(u8, &canary);
        self.auth.materials.set(.aws_bedrock, .{ .ready = (try key.Snapshot.capture(allocator, &canary)).? });
        self.backend = backend;
        self.wire = .{};
        self.real = .{ .allocator = allocator, .authorization_leases = self.base.leasePort(), .transport = self.wire.port() };
        self.fake_provider = .{ .allocator = allocator, .authorization_leases = self.base.leasePort(), .invocation_plan = .{ .complete = .{ .content = "{}", .input_tokens = 10, .output_tokens = 2, .provider_latency_ms = 1 } } };
    }
    /// Binds one compiled Bedrock family contract to a catalogue model and Region
    /// that name nothing real: a family contract covers any of them (ADR 0029).
    fn bindBedrockContract(self: *Fixture, contract: @import("domain/llm_provider_contracts.zig").ProviderModelContract, effort: ?[]const u8) void {
        self.base.registry_entry.provider = contract.provider;
        self.base.registry_entry.model = .{ .bytes = test_contracts.bedrock_model_ids[0] };
        self.base.registry_entry.capabilities = contract.capabilities;
        self.base.registry_entry.facts = contract.facts;
        self.base.registry_entry.config = .{ .aws_bedrock = .{ .region = std.enums.values(@import("domain/llm_provider_contracts.zig").BedrockRegion)[0], .family = contract.facts.bedrockFamily().?, .max_output_tokens = .{ .tokens = 16000 }, .request_timeout = .{ .milliseconds = 180000 } } };
        self.base.registry_entry.supported_reasoning_efforts = contract.supported_reasoning_efforts;
        self.base.provider_binding.reasoning_effort = effort;
        self.base.provider_binding.controls = contract.capabilities.inferenceControls();
        self.base.request.controls = self.base.provider_binding.controls;
        self.base.request.binding_id = self.base.provider_binding.bindingId();
    }

    fn deinit(self: *Fixture) void {
        self.base.deinit();
        self.auth.deinit();
    }
    fn port(self: *Fixture) @import("ports/llm_provider_interface.zig").LLMProviderInterface {
        return switch (self.backend) {
            .fake => self.fake_provider.interface(),
            .bedrock => self.real.port(),
        };
    }
    fn start(self: *Fixture) !fixture_module.Authorized {
        try self.base.assignInference();
        var preparation = self.base.preparationRunner();
        if (self.backend == .bedrock) preparation.prepare_action.authorization = self.auth.port();
        const prepared = try preparation.prepare(self.base.facts(.inference));
        return .{ .reference = prepared.prepared, .invoked = try self.base.invoke(.inference) };
    }
    fn call(self: *Fixture, authorized: fixture_module.Authorized) !operation.ProviderInvocationObservation {
        return self.port().invoke(&self.base.provider_binding, &self.base.request, authorized.reference, authorized.invoked);
    }
    fn effects(self: *const Fixture) usize {
        return switch (self.backend) {
            .fake => self.fake_provider.effect_count,
            .bedrock => self.wire.calls,
        };
    }
};

test "Bedrock sends the selected catalogue entry's maximum, not a fixed value" {
    for ([_]u32{ 8192, 16000 }) |maximum| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator, .bedrock);
        defer fixture.deinit();
        fixture.base.registry_entry.config = .{ .aws_bedrock = .{ .region = fixture.base.registry_entry.config.aws_bedrock.region, .family = .converse, .max_output_tokens = .{ .tokens = maximum }, .request_timeout = .{ .milliseconds = 180000 } } };
        fixture.wire.expected_max_tokens = maximum;
        const authorized = try fixture.start();
        var observed = try fixture.call(authorized);
        defer observed.deinit();
        try std.testing.expectEqual(@as(usize, 1), fixture.wire.calls);
    }
}

test "shared fake and Bedrock inference conformance: identity usage owned content and single use" {
    inline for (std.meta.tags(Backend)) |backend| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator, backend);
        defer fixture.deinit();
        const authorized = try fixture.start();
        var observed = try fixture.call(authorized);
        defer observed.deinit();
        try std.testing.expect(observed.completed.operation_id.eql(authorized.invoked.id));
        const result = observed.completed.raw_result.complete;
        try std.testing.expect(result.request_id == fixture.base.request.model_request_id);
        try std.testing.expect(result.binding_id.eql(fixture.base.provider_binding.bindingId()));
        try std.testing.expectEqual(@as(u64, 12), result.usage.total_tokens);
        try std.testing.expectEqualStrings("{}", result.content.bytes);
        var reused = try fixture.call(authorized);
        defer reused.deinit();
        try std.testing.expectEqual(.authorization_denied, reused.failed.cause);
        try std.testing.expectEqual(.not_sent, reused.failed.delivery);
        try std.testing.expectEqual(@as(usize, 1), fixture.effects());
    }
}

test "Bedrock captures exact serialized requests and raw responses before response admission" {
    const reasoning = try std.testing.allocator.alloc(u8, 170000);
    defer std.testing.allocator.free(reasoning);
    @memset(reasoning, 'r');
    const reasoning_complete = try std.json.Stringify.valueAlloc(std.testing.allocator, .{
        .output = .{ .message = .{ .role = "assistant", .content = .{
            .{ .reasoningContent = .{ .reasoningText = .{ .text = reasoning } } },
            .{ .text = "{}" },
        } } },
        .stopReason = "end_turn",
        .usage = .{ .inputTokens = 10, .outputTokens = 16384, .totalTokens = 16394 },
    }, .{});
    defer std.testing.allocator.free(reasoning_complete);
    const reasoning_stopped = try std.mem.replaceOwned(u8, std.testing.allocator, reasoning_complete, "\"end_turn\"", "\"max_tokens\"");
    defer std.testing.allocator.free(reasoning_stopped);
    const reasoning_unfinished = try std.mem.replaceOwned(u8, std.testing.allocator, reasoning_complete, ",{\"text\":\"{}\"}", "");
    defer std.testing.allocator.free(reasoning_unfinished);
    const Expected = enum { complete, malformed, stopped, rejected, missing_final, http_error };
    const cases = [_]struct { body: []const u8, status: u16 = 200, exception: ?[]const u8 = null, expected: Expected }{
        .{ .body = @import("model_transport_test_fixture.zig").complete, .expected = .complete },
        .{ .body = reasoning_complete, .expected = .complete },
        .{ .body = reasoning_stopped, .expected = .stopped },
        .{ .body = reasoning_unfinished, .expected = .missing_final },
        .{ .body = "\xffnot-json", .expected = .malformed },
        .{ .body = "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"\"}]}},\"stopReason\":\"max_tokens\",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12}}", .expected = .stopped },
        .{ .body = "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"\"}]}},\"stopReason\":\"unknown\",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12}}", .expected = .rejected },
        .{ .body = "{\"message\":\"unparsed provider error detail\"}", .status = 429, .exception = "ThrottlingException", .expected = .http_error },
    };
    for (cases) |case| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator, .bedrock);
        defer fixture.deinit();
        var capture: CaptureSpy = .{ .allocator = std.testing.allocator, .expected_secret = fixture.auth.materials.get(.aws_bedrock).ready.bytes };
        defer capture.deinit();
        var wire: CaptureObservedWire = .{ .inner = &fixture.wire, .capture = &capture };
        fixture.real.capture = capture.port();
        fixture.real.transport = wire.port();
        fixture.wire.result = .{ .received = .{ .status = case.status, .exception = case.exception, .body = case.body } };
        const authorized = try fixture.start();
        var observed = try fixture.call(authorized);
        defer observed.deinit();
        try std.testing.expect(wire.request_matches_prior_capture);
        try std.testing.expect(!capture.allocation_failed);
        try std.testing.expectEqual(@as(usize, 2), capture.calls.items.len);
        try std.testing.expectEqual(.response, capture.calls.items[1].direction);
        try std.testing.expectEqual(.provider_body, capture.calls.items[1].kind);
        try std.testing.expectEqualSlices(u8, case.body, capture.calls.items[1].body);
        for (capture.calls.items) |call| try std.testing.expect(call.credential_matches);
        switch (case.expected) {
            .complete => try std.testing.expectEqualStrings("{}", observed.completed.raw_result.complete.content.bytes),
            .malformed => try std.testing.expectEqual(.response_invalid, observed.failed.cause),
            .stopped => try std.testing.expectEqual(.output_limit, observed.completed.raw_result.stopped.reason),
            .rejected => try std.testing.expectEqual(.invalid_content, observed.completed.raw_result.rejected.reason),
            .missing_final => try std.testing.expectEqual(.missing_final_text, observed.completed.raw_result.rejected.reason),
            .http_error => try std.testing.expectEqual(.throttled, observed.failed.cause),
        }
    }
}

test "Bedrock request capture failure prevents transport" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    var capture: CaptureSpy = .{ .allocator = std.testing.allocator, .expected_secret = fixture.auth.materials.get(.aws_bedrock).ready.bytes, .block_direction = .request };
    defer capture.deinit();
    fixture.real.capture = capture.port();
    const authorized = try fixture.start();
    try std.testing.expectError(error.ModelLoggingBlocked, fixture.call(authorized));
    try std.testing.expectEqual(@as(usize, 0), fixture.effects());
    try std.testing.expectEqual(@as(usize, 1), capture.calls.items.len);
    try std.testing.expect(capture.calls.items[0].credential_matches);
    var reused = try fixture.call(authorized);
    defer reused.deinit();
    try std.testing.expectEqual(.authorization_denied, reused.failed.cause);
    try std.testing.expectEqual(@as(usize, 2), capture.calls.items.len);
    try std.testing.expectEqual(.transport_outcome, capture.calls.items[1].kind);
    try std.testing.expect(std.mem.indexOf(u8, capture.calls.items[1].body, "rejected_before_send") != null);
    try std.testing.expectEqual(@as(usize, 0), fixture.effects());
}

test "Bedrock response capture failure preserves completed stopped and rejected usage" {
    const bodies = [_][]const u8{
        @import("model_transport_test_fixture.zig").complete,
        "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"\"}]}},\"stopReason\":\"max_tokens\",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12}}",
        "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"\"}]}},\"stopReason\":\"unknown\",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12}}",
    };
    for (bodies) |body| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator, .bedrock);
        defer fixture.deinit();
        var capture: CaptureSpy = .{ .allocator = std.testing.allocator, .expected_secret = fixture.auth.materials.get(.aws_bedrock).ready.bytes, .block_direction = .response };
        defer capture.deinit();
        fixture.real.capture = capture.port();
        fixture.wire.inference_body = body;
        var observed = try fixture.call(try fixture.start());
        defer observed.deinit();
        const usage = switch (observed.completed.raw_result) {
            .complete => |result| result.usage,
            .stopped => |result| result.usage,
            .rejected => |result| result.usage,
        };
        try std.testing.expectEqual(@as(u64, 10), usage.input_tokens);
        try std.testing.expectEqual(@as(u64, 2), usage.output_tokens);
        try std.testing.expectEqual(@as(u64, 12), usage.total_tokens);
        try std.testing.expectEqual(@as(usize, 1), fixture.effects());
        try std.testing.expectEqual(@as(usize, 2), capture.calls.items.len);
    }
}

test "transport observation survives failure to capture its diagnostic" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    var capture: CaptureSpy = .{ .allocator = std.testing.allocator, .expected_secret = fixture.auth.materials.get(.aws_bedrock).ready.bytes, .block_direction = .response };
    defer capture.deinit();
    fixture.real.capture = capture.port();
    fixture.wire.result = .{ .failed = .{ .cause = .service_unavailable, .retry_class = .policy_eligible, .delivery = .not_sent } };
    var observed = try fixture.call(try fixture.start());
    defer observed.deinit();
    try std.testing.expectEqual(.service_unavailable, observed.failed.cause);
    try std.testing.expectEqual(.not_sent, observed.failed.delivery);
    try std.testing.expectEqual(.transport_outcome, capture.calls.items[1].kind);
}

test "Bedrock captures concrete HTTP failure bodies before metadata" {
    const http = @import("model_http_test_fixture.zig");
    for ([_]http.Fault{ .none, .eof, .reset, .deadline, .cancelled }) |fault| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator, .bedrock);
        defer fixture.deinit();
        var capture: CaptureSpy = .{ .allocator = std.testing.allocator, .expected_secret = fixture.auth.materials.get(.aws_bedrock).ready.bytes };
        defer capture.deinit();
        fixture.real.capture = capture.port();
        const body = try std.fmt.allocPrint(std.testing.allocator, "echo {s} " ++ "retained body " ** 500, .{fixture.auth.materials.get(.aws_bedrock).ready.bytes});
        defer std.testing.allocator.free(body);
        const wire = try std.fmt.allocPrint(std.testing.allocator, "HTTP/1.1 {s}\r\nContent-Length: {d}\r\n\r\n{s}", .{ if (fault == .none) "307 Temporary Redirect" else "200 OK", body.len, body });
        defer std.testing.allocator.free(wire);
        var connection: http.Fixture = undefined;
        connection.init(wire);
        defer connection.deinit();
        var host: [64]u8 = undefined;
        connection.expected_host = try std.fmt.bufPrint(&host, "bedrock-runtime.{s}.amazonaws.com", .{@tagName(fixture.base.registry_entry.config.aws_bedrock.region)});
        connection.fault = fault;
        connection.body_prefix_bytes = body.len - 3;
        connection.maximum_read = 257;
        var adapter = connection.adapter();
        fixture.real.transport = adapter.port();
        const authorized = try fixture.start();
        connection.now_ms.store(authorized.invoked.deadline_monotonic_ms - 100, .release);
        if (fault == .cancelled) {
            try std.testing.expectError(error.Cancelled, fixture.call(authorized));
        } else {
            const observed = observed: {
                var value = try fixture.call(authorized);
                defer value.deinit();
                break :observed value.failed;
            };
            try std.testing.expectEqual(@as(operation.ProviderFailureCause, if (fault == .none) .response_invalid else if (fault == .deadline) .timeout else .transport_failed), observed.cause);
            try std.testing.expectEqual(@as(operation.ProviderDeliveryDisposition, if (fault == .none) .response_received else .accepted_or_unknown), observed.delivery);
        }
        try std.testing.expectEqual(@as(usize, 3), capture.calls.items.len);
        try std.testing.expectEqual(.request, capture.calls.items[0].direction);
        try std.testing.expectEqual(.response, capture.calls.items[1].direction);
        try std.testing.expectEqual(@as(std.meta.Tag(capture_port.Body), if (fault == .none) .provider_body else .partial_provider_body), capture.calls.items[1].kind);
        try std.testing.expectEqualStrings(if (fault == .none) body else body[0 .. body.len - 3], capture.calls.items[1].body);
        try std.testing.expectEqual(.transport_outcome, capture.calls.items[2].kind);
        try std.testing.expect(std.mem.indexOf(u8, capture.calls.items[2].body, "retained body") == null);
        try std.testing.expect(std.mem.indexOf(u8, capture.calls.items[2].body, if (fault == .cancelled) "cancelled" else "transport_failed") != null);
        for (capture.calls.items) |call_record| try std.testing.expect(call_record.credential_matches);
        try std.testing.expect(!capture.allocation_failed);
        try connection.expectJoined();
    }
}

test "Bedrock captures explicit no-body outcomes on failed cancelled and allocation-failed transport" {
    for ([_][]const u8{ "transport_failed", "cancelled", "allocation_failed" }, 0..) |outcome, scenario| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator, .bedrock);
        defer fixture.deinit();
        var capture: CaptureSpy = .{ .allocator = std.testing.allocator, .expected_secret = fixture.auth.materials.get(.aws_bedrock).ready.bytes };
        defer capture.deinit();
        var wire: CaptureObservedWire = .{ .inner = &fixture.wire, .capture = &capture };
        fixture.real.capture = capture.port();
        fixture.real.transport = wire.port();
        const authorized = try fixture.start();
        switch (scenario) {
            0 => {
                fixture.wire.result = .{ .failed = .{ .cause = .service_unavailable, .retry_class = .policy_eligible, .delivery = .not_sent } };
                var observed = try fixture.call(authorized);
                defer observed.deinit();
                try std.testing.expectEqual(.service_unavailable, observed.failed.cause);
            },
            1 => {
                fixture.wire.cancelled = true;
                try std.testing.expectError(error.Cancelled, fixture.call(authorized));
            },
            2 => {
                wire.fail_allocation = true;
                try std.testing.expectError(error.OutOfMemory, fixture.call(authorized));
            },
            else => unreachable,
        }
        try std.testing.expect(wire.request_matches_prior_capture);
        try std.testing.expectEqual(@as(usize, 2), capture.calls.items.len);
        try std.testing.expectEqual(.response, capture.calls.items[1].direction);
        for (capture.calls.items) |call| try std.testing.expect(call.credential_matches);
        var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, capture.calls.items[1].body, .{});
        try std.testing.expectEqual(.transport_outcome, capture.calls.items[1].kind);
        defer parsed.deinit();
        try std.testing.expectEqualStrings(outcome, parsed.value.object.get("outcome").?.string);
        try std.testing.expect(!parsed.value.object.contains("response_body"));
    }
}

test "shared fake and Bedrock reject foreign request binding operation and deadlines before effects" {
    inline for (std.meta.tags(Backend)) |backend| {
        for (0..5) |scenario| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator, backend);
            defer fixture.deinit();
            const authorized = try fixture.start();
            var request_copy = fixture.base.request.model_request_id.*;
            var operation_copy = authorized.invoked.*;
            switch (scenario) {
                0 => fixture.base.request.model_request_id = &request_copy,
                1 => fixture.base.provider_binding.slot_id = .{ .bytes = "foreign" },
                2 => fixture.base.clock.now_ms = authorized.invoked.deadline_monotonic_ms,
                3 => operation_copy.id.model_attempt_ordinal.value += 1,
                4 => fixture.base.request.model_visible_input_id = .{ .bytes = "other-input" },
                else => unreachable,
            }
            var observed = try fixture.call(.{ .reference = authorized.reference, .invoked = &operation_copy });
            defer observed.deinit();
            try std.testing.expect(observed == .failed);
            try std.testing.expectEqual(.never, observed.failed.retry_class);
            try std.testing.expectEqual(.not_sent, observed.failed.delivery);
            try std.testing.expectEqual(@as(usize, 0), fixture.effects());
        }
    }
}

test "shared fake and Bedrock preserve provider failure cancellation and stopped usage" {
    inline for (std.meta.tags(Backend)) |backend| {
        for (0..3) |scenario| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator, backend);
            defer fixture.deinit();
            const authorized = try fixture.start();
            switch (scenario) {
                0 => {
                    fixture.fake_provider.invocation_plan = .{ .failed = .{ .cause = .throttled, .retry_class = .policy_eligible, .delivery = .response_received } };
                    fixture.wire.result = .{ .received = .{ .status = 429, .exception = "ThrottlingException", .body = "{\"message\":\"not public\"}" } };
                    var observed = try fixture.call(authorized);
                    defer observed.deinit();
                    try std.testing.expectEqual(.throttled, observed.failed.cause);
                    try std.testing.expectEqual(.policy_eligible, observed.failed.retry_class);
                    try std.testing.expectEqual(.response_received, observed.failed.delivery);
                },
                1 => {
                    fixture.fake_provider.invocation_plan = .cancelled;
                    fixture.wire.cancelled = true;
                    try std.testing.expectError(error.Cancelled, fixture.call(authorized));
                },
                2 => {
                    fixture.fake_provider.invocation_plan = .{ .stopped = .{ .reason = .output_limit, .input_tokens = 10, .output_tokens = 2 } };
                    fixture.wire.result = .{ .received = .{ .status = 200, .body = "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"\"}]}},\"stopReason\":\"max_tokens\",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12}}" } };
                    var observed = try fixture.call(authorized);
                    defer observed.deinit();
                    try std.testing.expectEqual(.output_limit, observed.completed.raw_result.stopped.reason);
                    try std.testing.expectEqual(@as(u64, 12), observed.completed.raw_result.stopped.usage.total_tokens);
                },
                else => unreachable,
            }
            try std.testing.expectEqual(@as(usize, 1), fixture.effects());
            var repeated = try fixture.call(authorized);
            defer repeated.deinit();
            try std.testing.expectEqual(.authorization_denied, repeated.failed.cause);
        }
    }
}

test "production Bedrock contracts are one per family and admit every compiled Region and closed config" {
    try contracts.registry.validate();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const domain = @import("domain/llm_provider_contracts.zig");
    const config = @import("domain/llm_provider_config_schema.zig");
    for (contracts.registry.entries) |contract| {
        if (contract.facts != .aws_bedrock) continue;
        // A family contract names no model.
        try std.testing.expect(contract.model == null);
    }
    for (std.enums.values(domain.BedrockFamily)) |family| {
        var covering: usize = 0;
        for (contracts.registry.entries) |contract| if (contract.facts.bedrockFamily() == family) {
            covering += 1;
        };
        try std.testing.expectEqual(@as(usize, 1), covering);
        for (std.enums.values(domain.BedrockRegion)) |region| {
            // The catalogue records the model's documented maximum output: required,
            // positive and exact, with no default, lookup or clamp.
            const accepted = try std.json.parseFromSlice(std.json.Value, a, try std.fmt.allocPrint(a, "{{\"region\":\"{s}\",\"family\":\"{s}\",\"maxOutputTokens\":16000,\"requestTimeoutMs\":180000}}", .{ @tagName(region), @tagName(family) }), .{});
            const decoded = config.decode(.aws_bedrock, accepted.value).?;
            try std.testing.expectEqualDeep(domain.ValidatedProviderConfig{ .aws_bedrock = .{ .region = region, .family = family, .max_output_tokens = .{ .tokens = 16000 }, .request_timeout = .{ .milliseconds = 180000 } } }, decoded);
            for (test_contracts.bedrock_model_ids) |model| {
                try std.testing.expectEqual(family, contracts.registry.resolve(.{ .bytes = "aws-bedrock" }, .{ .bytes = model }, decoded).?.facts.bedrockFamily().?);
            }
        }
    }
    // Each rejection changes one thing about a valid entry.
    const region = @tagName(std.enums.values(domain.BedrockRegion)[0]);
    const family = @tagName(std.enums.values(domain.BedrockFamily)[0]);
    for ([_]struct { region: []const u8, family: []const u8, rest: []const u8 }{
        .{ .region = "null", .family = family, .rest = ",\"maxOutputTokens\":16000,\"requestTimeoutMs\":180000" },
        .{ .region = "\"unknown\"", .family = family, .rest = ",\"maxOutputTokens\":16000,\"requestTimeoutMs\":180000" },
        .{ .region = region, .family = "null", .rest = ",\"maxOutputTokens\":16000,\"requestTimeoutMs\":180000" },
        .{ .region = region, .family = "\"unknown\"", .rest = ",\"maxOutputTokens\":16000,\"requestTimeoutMs\":180000" },
        .{ .region = region, .family = family, .rest = "" },
        .{ .region = region, .family = family, .rest = ",\"requestTimeoutMs\":180000" },
        .{ .region = region, .family = family, .rest = ",\"maxOutputTokens\":0,\"requestTimeoutMs\":180000" },
        .{ .region = region, .family = family, .rest = ",\"maxOutputTokens\":-1,\"requestTimeoutMs\":180000" },
        .{ .region = region, .family = family, .rest = ",\"maxOutputTokens\":5000000000,\"requestTimeoutMs\":180000" },
        .{ .region = region, .family = family, .rest = ",\"maxOutputTokens\":\"16000\",\"requestTimeoutMs\":180000" },
        .{ .region = region, .family = family, .rest = ",\"maxOutputTokens\":16000.5,\"requestTimeoutMs\":180000" },
        // The deadline is required beside the maximum, with the same closed rules.
        .{ .region = region, .family = family, .rest = ",\"maxOutputTokens\":16000" },
        .{ .region = region, .family = family, .rest = ",\"maxOutputTokens\":16000,\"requestTimeoutMs\":0" },
        .{ .region = region, .family = family, .rest = ",\"maxOutputTokens\":16000,\"requestTimeoutMs\":-1" },
        .{ .region = region, .family = family, .rest = ",\"maxOutputTokens\":16000,\"requestTimeoutMs\":4294967296" },
        .{ .region = region, .family = family, .rest = ",\"maxOutputTokens\":16000,\"requestTimeoutMs\":\"180000\"" },
        .{ .region = region, .family = family, .rest = ",\"maxOutputTokens\":16000,\"requestTimeoutMs\":180000.5" },
        .{ .region = region, .family = family, .rest = ",\"maxOutputTokens\":16000,\"requestTimeoutMs\":1.8e5" },
        .{ .region = region, .family = family, .rest = ",\"maxOutputTokens\":16000,\"requestTimeoutMs\":180000,\"apiKey\":null" },
        .{ .region = region, .family = family, .rest = ",\"maxOutputTokens\":16000,\"requestTimeoutMs\":180000,\"endpoint\":null" },
        .{ .region = region, .family = family, .rest = ",\"maxOutputTokens\":16000,\"requestTimeoutMs\":180000,\"temperature\":0.1" },
    }) |case| {
        const quote = struct {
            fn value(arena_allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
                return if (std.mem.eql(u8, raw, "null") or raw[0] == '"') raw else std.fmt.allocPrint(arena_allocator, "\"{s}\"", .{raw});
            }
        };
        const bytes = try std.fmt.allocPrint(a, "{{\"region\":{s},\"family\":{s}{s}}}", .{ try quote.value(a, case.region), try quote.value(a, case.family), case.rest });
        const parsed = try std.json.parseFromSlice(std.json.Value, a, bytes, .{});
        try std.testing.expect(config.decode(.aws_bedrock, parsed.value) == null);
    }
    for ([_][]const u8{ "{}", try std.fmt.allocPrint(a, "{{\"region\":\"{s}\",\"maxOutputTokens\":16000,\"requestTimeoutMs\":180000}}", .{region}) }) |bytes| {
        const parsed = try std.json.parseFromSlice(std.json.Value, a, bytes, .{});
        try std.testing.expect(config.decode(.aws_bedrock, parsed.value) == null);
    }
}

test "a model maximum output is one positive integer admitted only through its parse rule" {
    const Maximum = @import("domain/llm_provider_contracts.zig").ModelMaximumOutput;
    for ([_]i64{ 1, 4096, 16384, std.math.maxInt(u32) }) |tokens| try std.testing.expectEqual(@as(u32, @intCast(tokens)), Maximum.parse(tokens).?.tokens);
    for ([_]i64{ 0, -1, std.math.maxInt(u32) + 1, std.math.minInt(i64) }) |tokens| try std.testing.expect(Maximum.parse(tokens) == null);
    // Every decoder sees the same integer-written wire form.
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Holder = struct { maximum: Maximum };
    const closed = @import("domain/strict_json.zig");
    const accepted = try closed.decode(Holder, a, "{\"maximum\":16384}", .{ .maximum_depth = 4 });
    try std.testing.expectEqual(@as(u32, 16384), accepted.maximum.tokens);
    try std.testing.expectEqualStrings("{\"maximum\":16384}", try std.json.Stringify.valueAlloc(a, accepted, .{}));
    for ([_][]const u8{
        "{\"maximum\":0}",
        "{\"maximum\":-1}",
        "{\"maximum\":5000000000}",
        "{\"maximum\":\"16384\"}",
        "{\"maximum\":16384.5}",
        "{\"maximum\":16384.0}",
        "{\"maximum\":1.6384e4}",
        "{\"maximum\":16384e0}",
        "{\"maximum\":-0}",
        "{\"maximum\":null}",
        "{\"maximum\":true}",
        "{\"maximum\":{\"tokens\":16384}}",
        "{}",
    }) |bytes| try std.testing.expectError(error.InvalidJsonDocument, closed.decode(Holder, a, bytes, .{ .maximum_depth = 4 }));
    // The written-form rule is the type's own, not the strict decoder's.
    for ([_][]const u8{ "{\"maximum\":\"16384\"}", "{\"maximum\":16384.0}", "{\"maximum\":1.6384e4}" }) |bytes|
        try std.testing.expect(std.meta.isError(std.json.parseFromSliceLeaky(Holder, a, bytes, .{})));
    try std.testing.expectEqual(@as(u32, 16384), (try std.json.parseFromSliceLeaky(Holder, a, "{\"maximum\":16384}", .{})).maximum.tokens);
}

test "Bedrock endpoint encoding is HTTPS fixed-region with no target reinterpretation" {
    const http = @import("adapters/provider/model_http_exchange.zig");
    // Transport routing depends only on the compiled Region, never on the model ID.
    for (test_contracts.bedrock_model_ids) |raw_model| {
        const model: @import("domain/llm_provider_identity.zig").ModelId = .{ .bytes = raw_model };
        for (std.enums.values(@import("domain/llm_provider_contracts.zig").BedrockRegion)) |region| {
            const value = try @import("adapters/provider/bedrock_endpoint.zig").url(std.testing.allocator, .{ .region = region, .model = model });
            defer std.testing.allocator.free(value);
            const expected = try std.fmt.allocPrint(std.testing.allocator, "https://bedrock-runtime.{s}.amazonaws.com/model/{f}/converse", .{
                @tagName(region),
                std.fmt.alt(std.Uri.Component{ .raw = model.bytes }, .formatEscaped),
            });
            defer std.testing.allocator.free(expected);
            try std.testing.expectEqualStrings(expected, value);
        }
    }
    // Force native HTTP implementation compilation without a network request.
    _ = &http.Adapter.port;
}

test "Bedrock allocation failures release request response and single-use authorization owners" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(allocationCase, .{});
}
fn allocationCase(allocator: std.mem.Allocator) !void {
    var fixture: Fixture = undefined;
    try fixture.init(allocator, .bedrock);
    defer fixture.deinit();
    const authorized = try fixture.start();
    var observed = try fixture.call(authorized);
    defer observed.deinit();
}

test "Bedrock projects the exact input once with only the model maximum and no identity echoes" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    fixture.base.request.response_schema = try parser.compiler().compile(fixture.base.schema_arena.allocator(),
        \\{ "$defs": {"flag": {"type":"boolean"}}, "type":"object", "properties":{"ok":{"$ref":"#/$defs/flag"}}, "required":["ok"], "additionalProperties":false }
    );
    const encoding = @import("adapters/provider/bedrock_request.zig");
    const infer = try encoding.encode(std.testing.allocator, &fixture.base.request, .converse, .{ .tokens = 16000 });
    defer std.testing.allocator.free(infer);
    var first = try strict.parse(std.testing.allocator, infer, .{ .maximum_depth = 32 }, false, null);
    defer first.deinit();
    try std.testing.expectEqual(@as(usize, 3), first.value.object.get("system").?.array.items.len);
    const framing = @import("domain/model_controls.zig").response_format_guidance;
    try std.testing.expectEqualStrings(framing, first.value.object.get("system").?.array.items[1].object.get("text").?.string);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, infer, framing));
    try std.testing.expectEqualStrings(fixture.base.request.response_schema.modelBytes(), first.value.object.get("system").?.array.items[2].object.get("text").?.string);
    try std.testing.expect(std.mem.indexOf(u8, infer, "$ref") == null);
    try std.testing.expect(std.mem.indexOf(u8, infer, "$defs") == null);
    for ([_][]const u8{ "max_completion_tokens", "model_request_id", "binding_id", "deadline", "Authorization", "outputConfig" }) |name| {
        try std.testing.expect(std.mem.indexOf(u8, infer, name) == null);
    }
}

test "Bedrock serializes exactly the configured model maximum and no smaller allowance" {
    const encoding = @import("adapters/provider/bedrock_request.zig");
    const controls = @import("domain/model_controls.zig");
    for (std.enums.values(controls.ResponseGuidanceMode)) |mode| {
        for (contracts.registry.entries[0..1]) |contract| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator, .bedrock);
            defer fixture.deinit();
            fixture.base.registry_entry.capabilities = contract.capabilities;
            fixture.base.registry_entry.json = mode == .native_schema;
            fixture.base.provider_binding.controls = contract.capabilities.inferenceControls();
            fixture.base.request.binding_id = fixture.base.provider_binding.bindingId();
            fixture.base.request.controls = fixture.base.provider_binding.controls;
            fixture.base.request.response_guidance_mode = mode;
            try std.testing.expect(fixture.base.request.matchesBinding(fixture.base.provider_binding));

            // Inference sends the model's documented maximum exactly as configured;
            // Bedrock would otherwise apply a smaller default (ADR 0011).
            const encoded = try encoding.encode(std.testing.allocator, &fixture.base.request, .converse, .{ .tokens = 16000 });
            defer std.testing.allocator.free(encoded);
            var parsed = try strict.parse(std.testing.allocator, encoded, .{ .maximum_depth = 32 }, false, null);
            defer parsed.deinit();
            const inference_config = parsed.value.object.get("inferenceConfig").?.object;
            try std.testing.expectEqualStrings("16000", inference_config.get("maxTokens").?.number_string);
            try std.testing.expectEqual(@as(usize, if (fixture.base.request.controls.temperature != null) 2 else 1), inference_config.count());
            for ([_][]const u8{ "max_output_tokens", "max_tokens" }) |field| try std.testing.expect(std.mem.indexOf(u8, encoded, field) == null);
        }
    }
}

test "shared fake and Bedrock retain actual usage when the provider stops at its own output maximum" {
    inline for (std.meta.tags(Backend)) |backend| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator, backend);
        defer fixture.deinit();
        // Any compiled family: the provider's own stop is family-independent.
        fixture.bindBedrockContract(for (contracts.registry.entries) |contract| {
            if (contract.facts == .aws_bedrock) break contract;
        } else unreachable, null);
        const authorized = try fixture.start();
        fixture.fake_provider.invocation_plan = .{ .stopped = .{ .reason = .output_limit, .input_tokens = 10, .output_tokens = 2 } };
        fixture.wire.result = .{ .received = .{ .status = 200, .body = "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"\"}]}},\"stopReason\":\"max_tokens\",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12}}" } };
        var observed = try fixture.call(authorized);
        defer observed.deinit();
        const stopped = observed.completed.raw_result.stopped;
        try std.testing.expectEqual(.output_limit, stopped.reason);
        try std.testing.expectEqual(@as(u64, 10), stopped.usage.input_tokens);
        try std.testing.expectEqual(@as(u64, 2), stopped.usage.output_tokens);
        try std.testing.expectEqual(@as(u64, 12), stopped.usage.total_tokens);
        try std.testing.expectEqual(@as(usize, 1), fixture.effects());
        var repeated = try fixture.call(authorized);
        defer repeated.deinit();
        try std.testing.expectEqual(.authorization_denied, repeated.failed.cause);
        try std.testing.expectEqual(@as(usize, 1), fixture.effects());
    }
}

test "Bedrock native projection retains complete guidance and registered mode without fallback" {
    // Every compiled family carries the same native projection.
    for (contracts.registry.entries) |contract| {
        if (contract.facts != .aws_bedrock) continue;
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator, .bedrock);
        defer fixture.deinit();
        fixture.bindBedrockContract(contract, null);
        fixture.base.registry_entry.json = true;
        fixture.base.request.response_guidance_mode = .native_schema;
        var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const accepted = [_][]const u8{
            "{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":false}",
            "{\"type\":\"object\",\"properties\":{\"ok\":{\"type\":\"boolean\"},\"value\":{\"enum\":[\"a\",\"b\"]}},\"required\":[\"ok\"],\"additionalProperties\":false}",
            "{\"$defs\":{\"flag\":{\"type\":\"boolean\"}}, \"type\":\"object\", \"properties\":{\"ok\":{\"$ref\":\"#/$defs/flag\"}}, \"required\":[\"ok\"], \"additionalProperties\":false}",
        };
        for (accepted) |bytes| {
            fixture.base.request.response_schema = try parser.compiler().compile(fixture.base.schema_arena.allocator(), bytes);
            try std.testing.expect(fixture.base.request.matchesBinding(fixture.base.provider_binding));
            const body = try @import("adapters/provider/bedrock_request.zig").encode(std.testing.allocator, &fixture.base.request, contract.facts.bedrockFamily().?, .{ .tokens = 16000 });
            defer std.testing.allocator.free(body);
            var parsed = try strict.parse(std.testing.allocator, body, .{ .maximum_depth = 32 }, false, null);
            defer parsed.deinit();
            const format = parsed.value.object.get("outputConfig").?.object.get("textFormat").?;
            try std.testing.expectEqualStrings("json_schema", format.object.get("type").?.string);
            const schema = format.object.get("structure").?.object.get("jsonSchema").?.object.get("schema").?.string;
            try std.testing.expectEqualStrings(fixture.base.request.response_schema.modelBytes(), schema);
            try std.testing.expectEqualDeep(fixture.base.request.response_schema.root().*, (try parser.compiler().compile(fixture.base.schema_arena.allocator(), schema)).root().*);
            try std.testing.expectEqual(@as(usize, 3), parsed.value.object.get("system").?.array.items.len);
            const framing = @import("domain/model_controls.zig").response_format_guidance;
            try std.testing.expectEqualStrings(framing, parsed.value.object.get("system").?.array.items[1].object.get("text").?.string);
            try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, body, framing));
        }
        for ([_][]const u8{ "{\"type\":\"string\",\"maxLength\":100}", "{\"type\":\"integer\",\"minimum\":0,\"maximum\":4}", "{\"type\":\"array\",\"maxItems\":2,\"items\":{\"type\":\"boolean\"}}" }) |property| {
            const bytes = try std.fmt.allocPrint(fixture.base.schema_arena.allocator(), "{{\"type\":\"object\",\"properties\":{{\"value\":{s}}},\"required\":[\"value\"],\"additionalProperties\":false}}", .{property});
            fixture.base.request.response_schema = try parser.compiler().compile(fixture.base.schema_arena.allocator(), bytes);
            try std.testing.expect(fixture.base.request.matchesBinding(fixture.base.provider_binding));
            const native = try @import("adapters/provider/bedrock_request.zig").encode(std.testing.allocator, &fixture.base.request, contract.facts.bedrockFamily().?, .{ .tokens = 16000 });
            defer std.testing.allocator.free(native);
            var wire = try strict.parse(std.testing.allocator, native, .{ .maximum_depth = 32 }, false, null);
            defer wire.deinit();
            try std.testing.expectEqualStrings(fixture.base.request.response_schema.modelBytes(), wire.value.object.get("system").?.array.items[2].object.get("text").?.string);
            const projection = wire.value.object.get("outputConfig").?.object.get("textFormat").?.object.get("structure").?.object.get("jsonSchema").?.object.get("schema").?.string;
            for ([_][]const u8{ "maxLength", "minimum", "maximum", "maxItems" }) |unsupported| try std.testing.expect(std.mem.indexOf(u8, projection, unsupported) == null);
            fixture.base.request.response_guidance_mode = .prompt_only;
            fixture.base.registry_entry.json = false;
            try std.testing.expect(fixture.base.request.matchesBinding(fixture.base.provider_binding));
            fixture.base.request.response_guidance_mode = .native_schema;
            fixture.base.registry_entry.json = true;
        }
    }
}

test "Converse native schema rejects malformed projected data instead of weakening response mode" {
    const encoding = @import("adapters/provider/bedrock_request.zig");
    for ([_][]const u8{ "{broken", "null", "[]", "{\"type\":\"object\",\"type\":\"object\"}", "{} {}" }) |structure| {
        for (std.enums.values(encoding.Family)) |family| {
            try std.testing.expectError(error.InvalidRequest, encoding.encodeText(std.testing.allocator, .{
                .content = &.{.{ .user = "input" }},
                .schema = .{ .native = .{ .guidance = "{}", .structure = structure } },
                .schema_name = "test",
                .temperature = null,
                .reasoning_effort = null,
                .family = family,
                .max_output_tokens = .{ .tokens = 16000 },
            }));
        }
    }
}

test "Bedrock reasoning controls follow the exact registered policy" {
    const encoding = @import("adapters/provider/bedrock_request.zig");
    for (contracts.registry.entries) |contract| {
        // Bedrock wire tests cover the Bedrock family; Anthropic has its own codec tests.
        if (contract.facts != .aws_bedrock) continue;
        for ([_]?[]const u8{ null, "low", "medium", "high", "xhigh", "max" }) |effort| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator, .bedrock);
            defer fixture.deinit();
            fixture.bindBedrockContract(contract, effort);
            const supported = if (effort) |value| supported: {
                for (contract.supported_reasoning_efforts) |registered| if (std.mem.eql(u8, value, registered)) break :supported true;
                break :supported false;
            } else true;
            const authorized = try fixture.start();
            var observed = try fixture.call(authorized);
            defer observed.deinit();
            if (!supported) {
                try std.testing.expectEqual(.request_rejected, observed.failed.cause);
                try std.testing.expectEqual(.not_sent, observed.failed.delivery);
                try std.testing.expectEqual(@as(usize, 0), fixture.effects());
                continue;
            }
            try std.testing.expect(observed == .completed);
            try std.testing.expectEqual(@as(usize, 1), fixture.effects());
            const bytes = try encoding.encode(std.testing.allocator, &fixture.base.request, contract.facts.bedrockFamily().?, .{ .tokens = 16000 });
            defer std.testing.allocator.free(bytes);
            var parsed = try strict.parse(std.testing.allocator, bytes, .{ .maximum_depth = 32 }, false, null);
            defer parsed.deinit();
            const additional = parsed.value.object.get("additionalModelRequestFields");
            switch (contract.facts.bedrockFamily().?) {
                .converse => try std.testing.expect(additional == null),
                .@"gpt-oss" => if (effort) |value| {
                    try std.testing.expectEqualStrings(value, additional.?.object.get("reasoning_effort").?.string);
                    try std.testing.expectEqual(@as(usize, 1), additional.?.object.count());
                } else try std.testing.expect(additional == null),
                .luna => try std.testing.expect(additional == null),
                .claude => if (effort) |value| {
                    // Effort travels only in Claude's own object; no GPT-OSS field or thinking override.
                    const output_config = additional.?.object.get("output_config").?.object;
                    try std.testing.expectEqualStrings(value, output_config.get("effort").?.string);
                    try std.testing.expectEqual(@as(usize, 1), output_config.count());
                    try std.testing.expectEqual(@as(usize, 1), additional.?.object.count());
                } else try std.testing.expect(additional == null),
            }
        }
    }
    for ([_][]const u8{ "", "LOW", "none", "minimal", "low\n", "unknown" }) |invalid|
        try std.testing.expectError(error.InvalidRequest, @import("adapters/provider/model_text_request.zig").reasoningEffort(invalid));
    for ([_]@import("adapters/provider/model_text_request.zig").ReasoningEffort{ .xhigh, .max }) |effort| {
        try std.testing.expectError(error.InvalidRequest, encoding.encodeText(std.testing.allocator, .{
            .content = &.{.{ .user = "input" }},
            .schema = .{ .prompt_only = "{}" },
            .schema_name = "test",
            .temperature = null,
            .reasoning_effort = effort,
            .family = .@"gpt-oss",
            .max_output_tokens = .{ .tokens = 16000 },
        }));
    }
    try std.testing.expectError(error.InvalidRequest, encoding.encodeText(std.testing.allocator, .{
        .content = &.{.{ .user = "input" }},
        .schema = .{ .prompt_only = "{}" },
        .schema_name = "test",
        .temperature = null,
        .reasoning_effort = .low,
        .family = .converse,
        .max_output_tokens = .{ .tokens = 16000 },
    }));
    // Claude rejects non-default sampling, with or without an effort selection.
    for ([_]?@import("adapters/provider/model_text_request.zig").ReasoningEffort{ null, .low, .max }) |effort| {
        try std.testing.expectError(error.InvalidRequest, encoding.encodeText(std.testing.allocator, .{
            .content = &.{.{ .user = "input" }},
            .schema = .{ .prompt_only = "{}" },
            .schema_name = "test",
            .temperature = .fixed,
            .reasoning_effort = effort,
            .family = .claude,
            .max_output_tokens = .{ .tokens = 16000 },
        }));
    }
}

test "Converse response rejects malformed UTF8 unknown fields duplicate values and inconsistent usage" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    const original = @import("model_transport_test_fixture.zig").complete;
    const changes = [_][2][]const u8{
        .{ "\"text\":\"{}\"", "\"text\":\"\xff\"" },
        .{ "\"text\":\"{}\"", "\"text\":\"{}\",\"text\":\"{}\"" },
        .{ "\"totalTokens\":12", "\"totalTokens\":11" },
        .{ "\"inputTokens\":10", "\"inputTokens\":\"10\"" },
        .{ "\"inputTokens\":10", "\"inputTokens\":18446744073709551615" },
        .{ "\"totalTokens\":12", "\"totalTokens\":12,\"secret\":true" },
        .{ "\"stopReason\":", "\"model_request_id\":\"invented\",\"stopReason\":" },
    };
    for (changes) |change| {
        const bytes = try std.mem.replaceOwned(u8, std.testing.allocator, original, change[0], change[1]);
        defer std.testing.allocator.free(bytes);
        try std.testing.expect(!std.mem.eql(u8, original, bytes));
        var observed = try response.inference(std.testing.allocator, .{ .received = .{ .status = 200, .body = bytes } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
        defer observed.deinit();
        try std.testing.expectEqual(.response_invalid, observed.failed.cause);
        try std.testing.expectEqual(.response_received, observed.failed.delivery);
    }
}

test "Converse accepts empty server tool usage across registered profiles and unrelated contents" {
    for (contracts.registry.entries) |contract| {
        // Bedrock wire tests cover the Bedrock family; Anthropic has its own codec tests.
        if (contract.facts != .aws_bedrock) continue;
        for ([_][]const u8{ "{\"answer\":\"orchard\"}", "{\"loan\":{\"days\":14},\"allowed\":false}" }) |content| {
            for ([_]bool{ false, true }) |has_server_tool_usage| {
                var fixture: Fixture = undefined;
                try fixture.init(std.testing.allocator, .bedrock);
                defer fixture.deinit();
                fixture.bindBedrockContract(contract, null);
                fixture.base.registry_entry.json = contract.capabilities.structured_response == .native_json_schema;
                fixture.base.request.response_guidance_mode = fixture.base.registry_entry.responseMode();
                fixture.wire.expected_json = fixture.base.registry_entry.json;
                const text = try std.json.Stringify.valueAlloc(std.testing.allocator, content, .{});
                defer std.testing.allocator.free(text);
                const bytes = try std.fmt.allocPrint(
                    std.testing.allocator,
                    "{{\"output\":{{\"message\":{{\"role\":\"assistant\",\"content\":[{{\"text\":{s}}}]}}}},\"stopReason\":\"end_turn\",\"usage\":{{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12{s}}}}}",
                    .{ text, if (has_server_tool_usage) ",\"serverToolUsage\":{}" else "" },
                );
                defer std.testing.allocator.free(bytes);
                fixture.wire.result = .{ .received = .{ .status = 200, .body = bytes } };
                const authorized = try fixture.start();
                var observed = try fixture.call(authorized);
                defer observed.deinit();
                try std.testing.expectEqual(@as(usize, 1), fixture.effects());
                const complete = observed.completed.raw_result.complete;
                try std.testing.expectEqualStrings(content, complete.content.bytes);
                try std.testing.expectEqualDeep(operation.ProviderUsage{ .input_tokens = 10, .output_tokens = 2, .total_tokens = 12 }, complete.usage);
            }
        }
    }
}

test "Converse retained native response preserves exact answer reasoning and actual usage" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    // Native response and selected schema are retained verbatim from the
    // 2026-10-15T20-29-20Z GPT-OSS-20B compatibility exchange. This offline
    // regression proves codec behavior, not live model quality or E2E success.
    const bytes = @embedFile("test_fixtures/bedrock_converse_usage/response.json");
    var parsed = try strict.parse(std.testing.allocator, bytes, .{ .maximum_depth = std.math.maxInt(usize) }, false, null);
    defer parsed.deinit();
    const content = parsed.value.object.get("output").?.object.get("message").?.object.get("content").?.array.items;
    const expected_text = content[1].object.get("text").?.string;
    const expected_reasoning = content[0].object.get("reasoningContent").?.object.get("reasoningText").?.object.get("text").?.string;
    try std.testing.expect(std.mem.startsWith(u8, expected_text, "{\"{ \"kind\":"));
    var observed = try response.inference(std.testing.allocator, .{ .received = .{ .status = 200, .body = bytes } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
    defer observed.deinit();
    const complete = observed.completed.raw_result.complete;
    try std.testing.expectEqualStrings(expected_text, complete.content.bytes);
    try std.testing.expectEqualDeep(operation.ProviderUsage{ .input_tokens = 2106, .output_tokens = 148, .total_tokens = 2254 }, complete.usage);
    try std.testing.expectEqual(@as(?u32, 923), complete.provider_latency_ms);
    const reasoning = complete.reasoning.?.blocks;
    try std.testing.expectEqual(@as(usize, 1), reasoning.len);
    try std.testing.expectEqualStrings(expected_reasoning, reasoning[0].text.text);
    try std.testing.expectEqual(@as(?[]const u8, null), reasoning[0].text.signature);
}

test "Converse invalid server tool usage retains owned precise envelope diagnostics" {
    const a = std.testing.allocator;
    const cases = [_]struct { metadata: []const u8, path: []const u8, reason: @FieldType(@import("adapters/provider/provider_response_support.zig").DecodeDiagnostic, "reason") }{
        .{ .metadata = "\"serverToolUsage\":null", .path = "/usage/serverToolUsage", .reason = .expected_object },
        .{ .metadata = "\"serverToolUsage\":false", .path = "/usage/serverToolUsage", .reason = .expected_object },
        .{ .metadata = "\"serverToolUsage\":1", .path = "/usage/serverToolUsage", .reason = .expected_object },
        .{ .metadata = "\"serverToolUsage\":\"empty\"", .path = "/usage/serverToolUsage", .reason = .expected_object },
        .{ .metadata = "\"serverToolUsage\":[]", .path = "/usage/serverToolUsage", .reason = .expected_object },
        .{ .metadata = "\"serverToolUsage\":{\"unsupported\":true}", .path = "/usage/serverToolUsage/unsupported", .reason = .unknown_field },
        .{ .metadata = "\"serverToolUsage\":{},\"unregistered/~\":true", .path = "/usage/unregistered~1~0", .reason = .unknown_field },
    };
    for (cases) |case| {
        var diagnostic: ?@import("adapters/provider/provider_response_support.zig").DecodeDiagnostic = null;
        defer if (diagnostic) |*value| value.deinit(a);
        {
            const bytes = try std.fmt.allocPrint(a, "{{\"stopReason\":\"end_turn\",\"usage\":{{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12,{s}}}}}", .{case.metadata});
            defer a.free(bytes);
            var parsed = try strict.parse(a, bytes, .{ .maximum_depth = std.math.maxInt(usize) }, false, null);
            defer parsed.deinit();
            try std.testing.expectError(error.InvalidResponse, response.decodeConverse(a, parsed.value, &diagnostic));
        }
        // Diagnostic storage must outlive the parsed wire value and source.
        try std.testing.expectEqual(case.reason, diagnostic.?.reason);
        try std.testing.expectEqualStrings(case.path, diagnostic.?.path);
    }
}

fn converseDiagnosticAllocationScenario(a: std.mem.Allocator, expected: @FieldType(@import("adapters/provider/provider_response_support.zig").DecodeDiagnostic, "reason")) !void {
    const bytes: []const u8 = switch (expected) {
        .unknown_field => "{\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12,\"serverToolUsage\":{\"unregistered/~\":true}}}",
        .expected_object => "{\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12,\"serverToolUsage\":null}}",
        .invalid_response => "{\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":11,\"serverToolUsage\":{}}}",
    };
    var diagnostic: ?@import("adapters/provider/provider_response_support.zig").DecodeDiagnostic = null;
    defer if (diagnostic) |value| value.deinit(a);
    {
        var parsed = try strict.parse(a, bytes, .{ .maximum_depth = std.math.maxInt(usize) }, false, null);
        defer parsed.deinit();
        if (response.decodeConverse(a, parsed.value, &diagnostic)) |value| {
            var admitted = value;
            defer admitted.deinit(a);
            return error.UnexpectedConverseAdmission;
        } else |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidResponse => {},
        }
    }
    try std.testing.expectEqual(expected, diagnostic.?.reason);
    try std.testing.expectEqualStrings(switch (expected) {
        .unknown_field => "/usage/serverToolUsage/unregistered~1~0",
        .expected_object => "/usage/serverToolUsage",
        .invalid_response => "",
    }, diagnostic.?.path);
}

test "Converse envelope diagnostic allocation failures preserve cleanup and exact rejection" {
    for (std.meta.tags(@FieldType(@import("adapters/provider/provider_response_support.zig").DecodeDiagnostic, "reason"))) |reason| {
        try converseDiagnosticAllocationScenario(std.testing.allocator, reason);
        try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(converseDiagnosticAllocationScenario, .{reason});
    }
}

test "Converse separates typed reasoning and joins text exactly without interpreting provider text" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    const cases = [_]struct { blocks: []const u8, expected: ?[]const u8 }{
        .{ .blocks = "[{\"text\":\"{}\"}]", .expected = "{}" },
        .{ .blocks = "[{\"reasoningContent\":{\"reasoningText\":{\"text\":\"metadata\",\"signature\":\"opaque\"}}},{\"text\":\"{\"},{\"text\":\"}\"}]", .expected = "{}" },
        .{ .blocks = "[{\"text\":\" a\"},{\"reasoningContent\":{\"redactedContent\":\"YQ==\"}},{\"text\":\"b \\n\"}]", .expected = " ab \n" },
        .{ .blocks = "[{\"reasoningContent\":{\"reasoningText\":{\"text\":\"{}\"}}}]", .expected = null },
        .{ .blocks = "[]", .expected = null },
        .{ .blocks = "[{\"text\":\" \\t\\n\"}]", .expected = null },
        .{ .blocks = "[{\"text\":\"<reasoning>literal</reasoning>{}\"}]", .expected = "<reasoning>literal</reasoning>{}" },
        .{ .blocks = "[{\"text\":\"{broken\"}]", .expected = "{broken" },
    };
    for (cases) |case| {
        const bytes = try std.fmt.allocPrint(std.testing.allocator, "{{\"output\":{{\"message\":{{\"role\":\"assistant\",\"content\":{s}}}}},\"stopReason\":\"end_turn\",\"usage\":{{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12}}}}", .{case.blocks});
        defer std.testing.allocator.free(bytes);
        var observed = try response.inference(std.testing.allocator, .{ .received = .{ .status = 200, .body = bytes } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
        defer observed.deinit();
        if (case.expected) |expected| {
            try std.testing.expectEqualStrings(expected, observed.completed.raw_result.complete.content.bytes);
            try std.testing.expectEqual(@as(u64, 12), observed.completed.raw_result.complete.usage.total_tokens);
        } else {
            const rejected = observed.completed.raw_result.rejected;
            try std.testing.expectEqual(.missing_final_text, rejected.reason);
            try std.testing.expectEqual(@as(u64, 12), rejected.usage.total_tokens);
            try std.testing.expect(rejected.request_id == fixture.base.model_request_id);
            try std.testing.expect(rejected.binding_id.eql(fixture.base.provider_binding.bindingId()));
        }
    }
}

test "Converse content failures preserve valid usage and reject ambiguous content variants" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    const original = @import("model_transport_test_fixture.zig").complete;
    const cases = [_]struct { old: []const u8, new: []const u8, reason: operation.ProviderContentDiagnostic = .invalid_content }{
        .{ .old = "\"role\":\"assistant\"", .new = "\"role\":\"user\"" },
        .{ .old = "\"text\":\"{}\"", .new = "\"text\":{}" },
        .{ .old = "\"text\":\"{}\"", .new = "\"text\":null" },
        .{ .old = "\"text\":\"{}\"", .new = "\"text\":\"{}\",\"reasoningContent\":{\"reasoningText\":{\"text\":\"metadata\"}}" },
        .{ .old = "\"text\":\"{}\"", .new = "\"reasoningContent\":{\"reasoningText\":{\"text\":\"metadata\",\"unknown\":true}}" },
        .{ .old = "\"text\":\"{}\"", .new = "\"reasoningContent\":{\"redactedContent\":\"!bad\"}" },
        .{ .old = "\"text\":\"{}\"", .new = "\"toolUse\":{\"toolUseId\":\"id\",\"name\":\"action\",\"input\":{}}" },
        .{ .old = "\"end_turn\"", .new = "\"unknown\"" },
        .{ .old = "\"role\":\"assistant\"", .new = "\"role\":\"assistant\",\"unexpected\":true" },
        .{ .old = "\"content\":[{\"text\":\"{}\"}]", .new = "\"content\":null" },
        .{ .old = ",\"content\":[{\"text\":\"{}\"}]", .new = "", .reason = .missing_final_text },
    };
    for (cases) |case| {
        const bytes = try std.mem.replaceOwned(u8, std.testing.allocator, original, case.old, case.new);
        defer std.testing.allocator.free(bytes);
        try std.testing.expect(!std.mem.eql(u8, original, bytes));
        var observed = try response.inference(std.testing.allocator, .{ .received = .{ .status = 200, .body = bytes } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
        defer observed.deinit();
        try std.testing.expectEqual(case.reason, observed.completed.raw_result.rejected.reason);
        try std.testing.expectEqual(@as(u64, 12), observed.completed.raw_result.rejected.usage.total_tokens);
    }
}

test "Converse retains all documented stops without admitting partial candidates" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    const cases = [_]struct { wire: []const u8, expected: operation.ProviderNonCandidateStopReason }{
        .{ .wire = "max_tokens", .expected = .output_limit },
        .{ .wire = "tool_use", .expected = .unsupported_tool_request },
        .{ .wire = "malformed_tool_use", .expected = .unsupported_tool_request },
        .{ .wire = "content_filtered", .expected = .content_filtered },
        .{ .wire = "guardrail_intervened", .expected = .content_filtered },
        .{ .wire = "malformed_model_output", .expected = .malformed_output },
        .{ .wire = "stop_sequence", .expected = .malformed_output },
        .{ .wire = "model_context_window_exceeded", .expected = .context_limit },
    };
    for (cases) |case| {
        const bytes = try std.json.Stringify.valueAlloc(std.testing.allocator, .{
            .stopReason = case.wire,
            .usage = .{ .inputTokens = 10, .outputTokens = 2, .totalTokens = 12 },
        }, .{});
        defer std.testing.allocator.free(bytes);
        var observed = try response.inference(std.testing.allocator, .{ .received = .{ .status = 200, .body = bytes } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
        defer observed.deinit();
        try std.testing.expectEqual(case.expected, observed.completed.raw_result.stopped.reason);
        try std.testing.expectEqual(@as(u64, 12), observed.completed.raw_result.stopped.usage.total_tokens);
    }
}

test "Converse accounts cached input tokens and validates cache details without undercounting" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    const bytes = "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"{}\"}]}},\"stopReason\":\"end_turn\",\"usage\":{\"inputTokens\":10,\"cacheReadInputTokens\":20,\"cacheWriteInputTokens\":30,\"cacheDetails\":[{\"ttl\":\"1h\",\"inputTokens\":15},{\"ttl\":\"5m\",\"inputTokens\":15}],\"outputTokens\":2,\"totalTokens\":62,\"serverToolUsage\":{}},\"metrics\":{\"latencyMs\":42},\"serviceTier\":{\"type\":\"default\"},\"performanceConfig\":{\"latency\":\"standard\"}}";
    var observed = try response.inference(std.testing.allocator, .{ .received = .{ .status = 200, .body = bytes } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
    defer observed.deinit();
    const complete = observed.completed.raw_result.complete;
    try std.testing.expectEqual(@as(u64, 60), complete.usage.input_tokens);
    try std.testing.expectEqual(@as(u64, 62), complete.usage.total_tokens);
    try std.testing.expectEqual(@as(?u32, 42), complete.provider_latency_ms);
    for ([_][2][]const u8{
        .{ "\"totalTokens\":62", "\"totalTokens\":12" },
        .{ "\"cacheReadInputTokens\":20", "\"cacheReadInputTokens\":18446744073709551615" },
        .{ "\"cacheWriteInputTokens\":30", "\"cacheWriteInputTokens\":18446744073709551615" },
        .{ "\"cacheWriteInputTokens\":30", "\"cacheWriteInputTokens\":-1" },
        .{ "\"ttl\":\"1h\"", "\"ttl\":\"5m\"" },
        .{ "\"inputTokens\":15", "\"inputTokens\":14" },
        .{ "\"cacheDetails\":[", "\"unknown\":true,\"cacheDetails\":[" },
        .{ "\"serverToolUsage\":{}", "\"serverToolUsage\":null" },
        .{ "\"serverToolUsage\":{}", "\"serverToolUsage\":[]" },
        .{ "\"serverToolUsage\":{}", "\"serverToolUsage\":{\"unknown\":0}" },
        .{ "\"latencyMs\":42", "\"latencyMs\":4294967296" },
    }) |change| {
        const invalid = try std.mem.replaceOwned(u8, std.testing.allocator, bytes, change[0], change[1]);
        defer std.testing.allocator.free(invalid);
        var rejected = try response.inference(std.testing.allocator, .{ .received = .{ .status = 200, .body = invalid } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
        defer rejected.deinit();
        try std.testing.expectEqual(.response_invalid, rejected.failed.cause);
    }
}

test "Bedrock failure mapping requires matching status and discriminator and never exposes error text" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    const Mapping = struct { status: u16, exception: []const u8, cause: operation.ProviderFailureCause };
    const cases = [_]Mapping{
        .{ .status = 403, .exception = "AccessDeniedException", .cause = .authorization_denied },
        .{ .status = 400, .exception = "ValidationException", .cause = .request_rejected },
        .{ .status = 404, .exception = "ResourceNotFoundException", .cause = .model_unavailable },
        .{ .status = 429, .exception = "ModelNotReadyException", .cause = .service_unavailable },
        .{ .status = 408, .exception = "ModelTimeoutException", .cause = .timeout },
        .{ .status = 500, .exception = "InternalServerException", .cause = .service_unavailable },
        .{ .status = 503, .exception = "ServiceUnavailableException", .cause = .service_unavailable },
        .{ .status = 403, .exception = "ExpiredTokenException", .cause = .authentication_failed },
        .{ .status = 400, .exception = "AccessDeniedException", .cause = .response_invalid },
        .{ .status = 503, .exception = "Unregistered", .cause = .response_invalid },
        .{ .status = 302, .exception = "AccessDeniedException", .cause = .response_invalid },
    };
    const secret_body = try std.json.Stringify.valueAlloc(std.testing.allocator, .{ .message = fixture.auth.materials.get(.aws_bedrock).ready.bytes }, .{});
    defer std.testing.allocator.free(secret_body);
    for (cases) |case| {
        var observed = try response.inference(std.testing.allocator, .{ .received = .{ .status = case.status, .exception = case.exception, .body = secret_body } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
        defer observed.deinit();
        try std.testing.expectEqual(case.cause, observed.failed.cause);
        // The closed failure contains no raw provider bytes or metadata field.
        try std.testing.expect(observed.failed.operation_id.eql(fixture.base.id(.inference)));
    }
}

test "Bedrock HTTP headers grow beyond the standard client buffer without consuming body bytes" {
    const bytes = try std.fmt.allocPrint(std.testing.allocator, "HTTP/1.1 200 OK\r\nX-Data: {s}\r\nContent-Length: 2\r\n\r\n{{}}", .{"x" ** 20000});
    defer std.testing.allocator.free(bytes);
    var reader: std.Io.Reader = .fixed(bytes);
    const head = try @import("adapters/provider/model_http_head.zig").receive(std.testing.allocator, &reader);
    defer std.testing.allocator.free(head);
    const parsed = try std.http.Client.Response.Head.parse(head);
    try std.testing.expectEqual(.ok, parsed.status);
    try std.testing.expectEqualStrings("{}", reader.buffered());
}

test "native Bedrock inference cannot connect from tests with credentials" {
    const http_fixture = @import("model_http_test_fixture.zig");
    var connection: http_fixture.Fixture = undefined;
    connection.init("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}");
    defer connection.deinit();
    var adapter: @import("adapters/provider/model_http_exchange.zig").Adapter = .{
        .io = connection.io(),
        .clock = connection.adapter().clock,
        .runtime = .{},
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const observed = try adapter.port().exchange(arena.allocator(), connection.request());
    try std.testing.expectEqual(.transport_failed, observed.failed.cause);
    try std.testing.expectEqual(.not_sent, observed.failed.delivery);
    try std.testing.expectEqual(@as(usize, 0), connection.connects);
    try std.testing.expectEqual(@as(usize, 0), connection.wire.items.len);
}

test "Bedrock HTTP rejects expired deadlines and cancellation before network setup" {
    var clock: fixture_module.TestClock = .{ .now_ms = 1000 };
    var adapter: @import("adapters/provider/model_http_exchange.zig").Adapter = .{ .io = std.testing.io, .clock = clock.port(), .runtime = .{} };
    const request: transport.Request = .{ .target = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .model = .{ .bytes = test_contracts.bedrock_model_ids[0] } } }, .body = "{}", .api_key = "", .deadline_monotonic_ms = 1000 };
    const observed = try adapter.port().exchange(std.testing.allocator, request);
    try std.testing.expectEqual(.timeout, observed.failed.cause);
    try std.testing.expectEqual(.not_sent, observed.failed.delivery);
    adapter.runtime = .{ .status_fn = struct {
        fn status(_: ?*anyopaque) @import("domain/pipeline.zig").RuntimeStatus {
            return .cancelled;
        }
    }.status };
    try std.testing.expectError(error.Cancelled, adapter.port().exchange(std.testing.allocator, request));
}

test "each provider family reads only its exact key and owns an immutable snapshot" {
    const source = @import("adapters/system/provider_api_key_source.zig");
    for (std.enums.values(key.Family)) |family| try exactKeySource(source, family);
}

fn exactKeySource(comptime source: type, family: key.Family) !void {
    const own = source.variable(family);
    const foreign = source.variable(if (family == .aws_bedrock) .anthropic else .aws_bedrock);
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var missing = source.read(std.testing.allocator, &environment, family);
    defer missing.deinit();
    try std.testing.expect(missing == .unavailable);
    var canary: [48]u8 = undefined;
    std.testing.io.random(&canary);
    for (&canary) |*byte| byte.* = 'A' + byte.* % 26;
    defer std.crypto.secureZero(u8, &canary);
    // Another family's key, test variables and credential-chain names never stand in.
    for ([_][]const u8{ foreign, "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "BEDROCK_API_KEY", "ANTHROPIC_AUTH_TOKEN", "AWS_REGION", "AWS_ENDPOINT_URL", "HTTPS_PROXY", "AWS_CA_BUNDLE", "TEST_AWS_BEARER_TOKEN_BEDROCK", "TEST_ANTHROPIC_API_KEY", "TEST_OPENAI_API_KEY", "TEST_EVALUATION_PROVIDER", "TEST_EVALUATION_MODEL", "TEST_EVALUATION_REGION" }) |name| try environment.put(name, &canary);
    var ignored = source.read(std.testing.allocator, &environment, family);
    defer ignored.deinit();
    try std.testing.expect(ignored == .unavailable);
    try environment.put(own, &canary);
    var material = source.read(std.testing.allocator, &environment, family);
    defer material.deinit();
    try std.testing.expect(material == .ready);
    try std.testing.expect(std.mem.eql(u8, material.ready.bytes, &canary));
    try environment.put(own, "");
    try std.testing.expect(std.mem.eql(u8, material.ready.bytes, &canary));
    for ([_][]const u8{ "", " ", "\r\n", "\xff" }) |invalid| {
        try environment.put(own, invalid);
        var rejected = source.read(std.testing.allocator, &environment, family);
        defer rejected.deinit();
        try std.testing.expect(rejected == .unavailable);
    }
}

test "Bedrock model error nested status and conflicting discriminators fail closed" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    const cases = [_]struct { body: []const u8, cause: operation.ProviderFailureCause }{
        .{ .body = "{\"originalStatusCode\":429}", .cause = .service_unavailable },
        .{ .body = "{\"originalStatusCode\":422}", .cause = .request_rejected },
        .{ .body = "{\"originalStatusCode\":401}", .cause = .authentication_failed },
        .{ .body = "{\"originalStatusCode\":403}", .cause = .authorization_denied },
        .{ .body = "{\"originalStatusCode\":404}", .cause = .model_unavailable },
        .{ .body = "{}", .cause = .response_invalid },
        .{ .body = "{\"originalStatusCode\":200}", .cause = .response_invalid },
        .{ .body = "{\"originalStatusCode\":429,\"__type\":\"ThrottlingException\"}", .cause = .response_invalid },
    };
    for (cases) |case| {
        var observed = try response.inference(std.testing.allocator, .{ .received = .{ .status = 424, .exception = "ModelErrorException", .body = case.body } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
        defer observed.deinit();
        try std.testing.expectEqual(case.cause, observed.failed.cause);
    }
}

test "Bedrock uses AWS restJson1 error discriminators without guessing from prose" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    for ([_][]const u8{ "{\"code\":\"ThrottlingException\"}", "{\"__type\":\"com.amazonaws.bedrock#ThrottlingException:detail\"}", "{\"__type\":\"ThrottlingException\",\"code\":\"ThrottlingException\"}" }) |body| {
        var observed = try response.inference(std.testing.allocator, .{ .received = .{ .status = 429, .body = body } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
        defer observed.deinit();
        try std.testing.expectEqual(.throttled, observed.failed.cause);
    }
    var conflict = try response.inference(std.testing.allocator, .{ .received = .{ .status = 429, .exception = "ThrottlingException", .body = "{\"code\":\"AccessDeniedException\"}" } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
    defer conflict.deinit();
    try std.testing.expectEqual(.response_invalid, conflict.failed.cause);
}

test "Bedrock capitalized messages preserve closed error classification" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    for ([_]struct { status: u16, exception: []const u8, cause: operation.ProviderFailureCause }{
        .{ .status = 403, .exception = "com.amazonaws.bedrock#AccessDeniedException:detail", .cause = .authorization_denied },
        .{ .status = 429, .exception = "ThrottlingException", .cause = .throttled },
    }) |case| {
        for ([_][]const u8{ "{\"Message\":\"private detail\"}", "{\"message\":\"private detail\"}" }) |body| {
            const wire: transport.Response = .{ .received = .{ .status = case.status, .exception = case.exception, .body = body } };
            var inferred = try response.inference(std.testing.allocator, wire, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
            defer inferred.deinit();
            const failure = inferred.failed;
            try std.testing.expectEqual(case.cause, failure.cause);
            try std.testing.expectEqual(.response_received, failure.delivery);
            try std.testing.expectEqual(@as(operation.ProviderRetryClass, if (case.status == 403) .never else .policy_eligible), failure.retry_class);
        }
    }
    for ([_][]const u8{ "{\"Message\":1}", "{\"Message\":null}", "{\"message\":\"same\",\"Message\":\"same\"}", "{\"message\":\"a\",\"Message\":\"b\"}", "{\"Message\":\"a\",\"unknown\":true}", "{\"Message\":\"a\",\"code\":\"ThrottlingException\"}" }) |body| {
        const wire: transport.Response = .{ .received = .{ .status = 403, .exception = "AccessDeniedException", .body = body } };
        var inferred = try response.inference(std.testing.allocator, wire, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
        defer inferred.deinit();
        try std.testing.expectEqual(.response_invalid, inferred.failed.cause);
    }
}

test "Bedrock inference serializes 0.1 for every registered model and omits unsupported temperature" {
    const encoding = @import("adapters/provider/bedrock_request.zig");
    for (contracts.registry.entries) |contract| {
        // Bedrock wire tests cover the Bedrock family; Anthropic has its own codec tests.
        if (contract.facts != .aws_bedrock) continue;
        for ([_]bool{ true, false }) |temperature_supported| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator, .bedrock);
            defer fixture.deinit();
            fixture.bindBedrockContract(contract, null);
            // The unsupported variant is a synthetic registered capability contract.
            fixture.base.registry_entry.capabilities.temperature = temperature_supported;
            fixture.base.provider_binding.controls = fixture.base.registry_entry.capabilities.inferenceControls();
            fixture.base.request.binding_id = fixture.base.provider_binding.bindingId();
            fixture.base.request.controls = fixture.base.provider_binding.controls;
            try std.testing.expect(fixture.base.request.matchesBinding(fixture.base.provider_binding));
            const bytes = try encoding.encode(std.testing.allocator, &fixture.base.request, .converse, .{ .tokens = 16000 });
            defer std.testing.allocator.free(bytes);
            var parsed = try strict.parse(std.testing.allocator, bytes, .{ .maximum_depth = 32 }, false, null);
            defer parsed.deinit();
            const inference_config = parsed.value.object.get("inferenceConfig").?.object;
            try std.testing.expectEqualStrings("16000", inference_config.get("maxTokens").?.number_string);
            if (temperature_supported) {
                try std.testing.expectEqualStrings("0.1", inference_config.get("temperature").?.number_string);
            } else try std.testing.expect(!inference_config.contains("temperature"));
            var altered = fixture.base.request;
            altered.controls = .forTemperatureSupport(!temperature_supported);
            var altered_binding = fixture.base.provider_binding;
            altered_binding.controls = altered.controls;
            try std.testing.expect(!altered.matchesBinding(fixture.base.provider_binding));
            try std.testing.expect(!altered.matchesBinding(altered_binding));
        }
    }
}

const diagnostic_reasoning_blocks = "[{\"reasoningContent\":{\"reasoningText\":{\"text\":\"first <script> & \\n\",\"signature\":\"opaque\\\"signature\"}}},{\"text\":\"{\"},{\"reasoningContent\":{\"redactedContent\":\"YQ==\"}},{\"reasoningContent\":{\"reasoningText\":{\"text\":\"last\"}}},{\"text\":\"}\"}]";

fn reasoningResponse(a: std.mem.Allocator, blocks: []const u8, stop: []const u8) ![]const u8 {
    return std.fmt.allocPrint(a, "{{\"output\":{{\"message\":{{\"role\":\"assistant\",\"content\":{s}}}}},\"stopReason\":\"{s}\",\"usage\":{{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12}}}}", .{ blocks, stop });
}

fn ownedReasoningScenario(a: std.mem.Allocator) !void {
    var decoded = blk: {
        const bytes = try reasoningResponse(a, diagnostic_reasoning_blocks, "end_turn");
        defer a.free(bytes);
        var parsed = try strict.parse(a, bytes, .{ .maximum_depth = std.math.maxInt(usize) }, false, null);
        defer parsed.deinit();
        break :blk try response.decodeConverse(a, parsed.value, null);
    };
    defer decoded.deinit(a);
    // All views survive the parsed response and its wire buffer.
    try std.testing.expectEqualStrings("{}", decoded.output.text);
    try std.testing.expectEqual(@as(usize, 3), decoded.reasoning.len);
    try std.testing.expectEqualStrings("first <script> & \n", decoded.reasoning[0].text.text);
    try std.testing.expectEqualStrings("opaque\"signature", decoded.reasoning[0].text.signature.?);
    try std.testing.expectEqualStrings("YQ==", decoded.reasoning[1].redacted.base64);
    try std.testing.expectEqualStrings("last", decoded.reasoning[2].text.text);
    try std.testing.expectEqual(@as(?[]const u8, null), decoded.reasoning[2].text.signature);
    const cloned = try @import("domain/provider_reasoning.zig").clone(a, decoded.reasoning);
    defer @import("domain/provider_reasoning.zig").deinit(a, cloned);
    try std.testing.expectEqualDeep(decoded.reasoning, cloned);
}

test "Converse owns ordered reasoning signatures and opaque redaction independently of final text" {
    try ownedReasoningScenario(std.testing.allocator);
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(ownedReasoningScenario, .{});
}

test "Converse preserves reasoning on stopped rejected and missing-answer responses without admitting it" {
    const cases = [_]struct { blocks: []const u8, stop: []const u8, output: std.meta.Tag(@FieldType(@import("adapters/provider/provider_response_assembly.zig").Inference, "output")), reason_count: usize }{
        .{ .blocks = diagnostic_reasoning_blocks, .stop = "max_tokens", .output = .stopped, .reason_count = 3 },
        .{ .blocks = "[{\"reasoningContent\":{\"reasoningText\":{\"text\":\"{}\"}}}]", .stop = "end_turn", .output = .invalid, .reason_count = 1 },
        .{ .blocks = diagnostic_reasoning_blocks, .stop = "unknown", .output = .invalid, .reason_count = 3 },
        .{ .blocks = "[{\"toolUse\":{\"toolUseId\":\"id\",\"name\":\"bad\",\"input\":{}}},{\"reasoningContent\":{\"reasoningText\":{\"text\":\"metadata\"}}}]", .stop = "tool_use", .output = .stopped, .reason_count = 1 },
        .{ .blocks = "[{\"unexpected\":true},{\"reasoningContent\":{\"reasoningText\":{\"text\":\"metadata\"}}},{\"text\":\"{}\"}]", .stop = "end_turn", .output = .invalid, .reason_count = 1 },
        .{ .blocks = "[{\"text\":\"{}\"}]", .stop = "end_turn", .output = .text, .reason_count = 0 },
    };
    for (cases) |case| {
        const bytes = try reasoningResponse(std.testing.allocator, case.blocks, case.stop);
        defer std.testing.allocator.free(bytes);
        var parsed = try strict.parse(std.testing.allocator, bytes, .{ .maximum_depth = std.math.maxInt(usize) }, false, null);
        defer parsed.deinit();
        var decoded = try response.decodeConverse(std.testing.allocator, parsed.value, null);
        defer decoded.deinit(std.testing.allocator);
        try std.testing.expectEqual(case.output, std.meta.activeTag(decoded.output));
        try std.testing.expectEqual(case.reason_count, decoded.reasoning.len);
        try std.testing.expectEqual(@as(u64, 12), decoded.usage.total_tokens);
        if (case.output == .invalid and case.reason_count == 1 and std.mem.eql(u8, case.stop, "end_turn") and std.mem.startsWith(u8, case.blocks, "[{\"reasoningContent\"")) {
            try std.testing.expectEqual(.missing_final_text, decoded.output.invalid);
        }
    }
}

test "Converse rejects malformed reasoning unions signatures and redacted payloads" {
    const invalid = [_][]const u8{
        "{\"reasoningText\":{\"text\":\"x\"},\"redactedContent\":\"YQ==\"}",
        "{\"reasoningText\":{\"signature\":\"opaque\"}}",
        "{\"reasoningText\":{\"text\":\"x\",\"signature\":null}}",
        "{\"reasoningText\":{\"text\":\"x\",\"signature\":12}}",
        "{\"reasoningText\":{\"text\":\"x\",\"unknown\":true}}",
        "{\"redactedContent\":\"Y!==\"}",
        "{\"redactedContent\":true}",
        "{}",
    };
    for (invalid) |value| {
        const blocks = try std.fmt.allocPrint(std.testing.allocator, "[{{\"reasoningContent\":{s}}},{{\"text\":\"{{}}\"}}]", .{value});
        defer std.testing.allocator.free(blocks);
        const bytes = try reasoningResponse(std.testing.allocator, blocks, "end_turn");
        defer std.testing.allocator.free(bytes);
        var parsed = try strict.parse(std.testing.allocator, bytes, .{ .maximum_depth = std.math.maxInt(usize) }, false, null);
        defer parsed.deinit();
        var decoded = try response.decodeConverse(std.testing.allocator, parsed.value, null);
        defer decoded.deinit(std.testing.allocator);
        try std.testing.expectEqual(.invalid_content, decoded.output.invalid);
        try std.testing.expectEqual(@as(usize, 0), decoded.reasoning.len);
        try std.testing.expectEqual(@as(u64, 12), decoded.usage.total_tokens);
    }
}

const ReasoningProductionResult = enum { complete, stopped, missing_answer };

fn productionReasoningScenario(a: std.mem.Allocator, expected: ReasoningProductionResult) !void {
    var fixture: Fixture = undefined;
    try fixture.init(a, .bedrock);
    defer fixture.deinit();
    const authorized = try fixture.start();
    // The existing runner result owner is prepared before provider dispatch.
    const owner = try @import("domain/model_invocation_result.zig").Owner.init(a, fixture.base.requests.ledger().?, authorized.invoked.id);
    defer owner.destroy();
    const observed = blk: {
        const blocks = if (expected == .missing_answer)
            "[{\"reasoningContent\":{\"reasoningText\":{\"text\":\"{}\",\"signature\":\"opaque\"}}}]"
        else
            diagnostic_reasoning_blocks;
        const bytes = try reasoningResponse(a, blocks, if (expected == .stopped) "max_tokens" else "end_turn");
        defer a.free(bytes);
        fixture.wire.result = .{ .received = .{ .status = 200, .body = bytes } };
        break :blk try fixture.call(authorized);
    };
    owner.finish(.{ .observation = observed });
    const retained = owner.view().outcome().?.observation.completed.raw_result;
    const diagnostic = switch (retained) {
        inline .complete, .stopped, .rejected => |value| value.reasoning orelse return error.ExpectedReasoningDiagnostics,
    };
    // Returned diagnostics survive both the parsed tree and the transport body,
    // and remain available through the production provider port/result owner.
    if (expected == .missing_answer) {
        try std.testing.expectEqual(.missing_final_text, retained.rejected.reason);
        try std.testing.expectEqual(@as(usize, 1), diagnostic.blocks.len);
        try std.testing.expectEqualStrings("{}", diagnostic.blocks[0].text.text);
        try std.testing.expectEqualStrings("opaque", diagnostic.blocks[0].text.signature.?);
    } else {
        try std.testing.expectEqual(@as(usize, 3), diagnostic.blocks.len);
        try std.testing.expectEqualStrings("first <script> & \n", diagnostic.blocks[0].text.text);
        try std.testing.expectEqualStrings("opaque\"signature", diagnostic.blocks[0].text.signature.?);
        try std.testing.expectEqualStrings("YQ==", diagnostic.blocks[1].redacted.base64);
        try std.testing.expectEqualStrings("last", diagnostic.blocks[2].text.text);
        if (expected == .complete) {
            try std.testing.expectEqualStrings("{}", retained.complete.content.bytes);
        } else try std.testing.expectEqual(.output_limit, retained.stopped.reason);
    }
    const usage = switch (retained) {
        inline .complete, .stopped, .rejected => |value| value.usage,
    };
    try std.testing.expectEqual(@as(u64, 12), usage.total_tokens);
}

test "production provider observations retain owned reasoning across complete stopped and rejected results" {
    inline for (std.meta.tags(ReasoningProductionResult)) |expected| {
        try productionReasoningScenario(std.testing.allocator, expected);
        try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(productionReasoningScenario, .{expected});
    }
}

test "absent provider reasoning stays absent across all raw result variants" {
    inline for (std.meta.tags(ReasoningProductionResult)) |expected| {
        inline for (std.meta.tags(Backend)) |backend| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator, backend);
            defer fixture.deinit();
            const bytes = try reasoningResponse(std.testing.allocator, if (expected == .missing_answer) "[]" else "[{\"text\":\"{}\"}]", if (expected == .stopped) "max_tokens" else "end_turn");
            defer std.testing.allocator.free(bytes);
            fixture.wire.result = .{ .received = .{ .status = 200, .body = bytes } };
            fixture.fake_provider.invocation_plan = switch (expected) {
                .complete => .{ .complete = .{ .content = "{}", .input_tokens = 10, .output_tokens = 2 } },
                .stopped => .{ .stopped = .{ .reason = .output_limit, .input_tokens = 10, .output_tokens = 2 } },
                .missing_answer => .{ .complete = .{ .content = "", .content_diagnostic = .missing_final_text, .input_tokens = 10, .output_tokens = 2 } },
            };
            var observed = try fixture.call(try fixture.start());
            defer observed.deinit();
            switch (observed.completed.raw_result) {
                inline .complete, .stopped, .rejected => |value| try std.testing.expect(value.reasoning == null),
            }
        }
    }
}

test "Luna native JSON emits its required strict flag and preserves canonical schema" {
    const encoding = @import("adapters/provider/bedrock_request.zig");
    const structure = "{\"type\":\"object\",\"properties\":{\"answer\":{\"type\":\"string\"}},\"required\":[\"answer\"],\"additionalProperties\":false}";
    const request: encoding.TextRequest = .{
        .content = &.{ .{ .guidance = "Generate the answer." }, .{ .user = "input" } },
        .schema = .{ .native = .{ .guidance = structure, .structure = structure } },
        .schema_name = "luna_schema",
        .temperature = null,
        .reasoning_effort = null,
        .family = .luna,
        .max_output_tokens = .{ .tokens = 16000 },
    };
    const body = try encoding.encodeText(std.testing.allocator, request);
    defer std.testing.allocator.free(body);
    var parsed = try strict.parse(std.testing.allocator, body, .{ .maximum_depth = 32 }, false, null);
    defer parsed.deinit();
    const root = parsed.value.object;
    const schema = root.get("outputConfig").?.object.get("textFormat").?.object;
    try std.testing.expectEqualStrings("json_schema", schema.get("type").?.string);
    const format = schema.get("structure").?.object.get("jsonSchema").?.object;
    try std.testing.expectEqualStrings(structure, format.get("schema").?.string);
    try std.testing.expectEqualStrings("luna_schema", format.get("name").?.string);
    const additional = root.get("additionalModelRequestFields").?.object;
    try std.testing.expectEqual(@as(usize, 1), additional.count());
    try std.testing.expect(additional.get("text").?.object.get("format").?.object.get("strict").?.bool);
    try std.testing.expect(!additional.contains("reasoning") and !additional.contains("reasoning_effort") and !additional.contains("thinking"));
    // Luna has no temperature, so its inference config holds only the maximum.
    try std.testing.expectEqual(@as(usize, 1), root.get("inferenceConfig").?.object.count());
    try std.testing.expect(root.get("inferenceConfig").?.object.contains("maxTokens"));
    var unrelated = request;
    unrelated.family = .converse;
    const other = try encoding.encodeText(std.testing.allocator, unrelated);
    defer std.testing.allocator.free(other);
    var other_parsed = try strict.parse(std.testing.allocator, other, .{ .maximum_depth = 32 }, false, null);
    defer other_parsed.deinit();
    try std.testing.expect(!other_parsed.value.object.contains("additionalModelRequestFields"));
    try std.testing.expect(other_parsed.value.object.contains("outputConfig"));
    var prompted = request;
    prompted.schema = .{ .prompt_only = structure };
    const prompt = try encoding.encodeText(std.testing.allocator, prompted);
    defer std.testing.allocator.free(prompt);
    var prompt_parsed = try strict.parse(std.testing.allocator, prompt, .{ .maximum_depth = 32 }, false, null);
    defer prompt_parsed.deinit();
    try std.testing.expect(!prompt_parsed.value.object.contains("additionalModelRequestFields"));
    try std.testing.expect(!prompt_parsed.value.object.contains("outputConfig"));
}

test "Luna request profile rejects unverified reasoning and temperature overrides" {
    const encoding = @import("adapters/provider/bedrock_request.zig");
    const base: encoding.TextRequest = .{
        .content = &.{.{ .user = "input" }},
        .schema = .{ .prompt_only = "{}" },
        .schema_name = "test",
        .temperature = null,
        .reasoning_effort = null,
        .family = .luna,
        .max_output_tokens = .{ .tokens = 16000 },
    };
    inline for (std.meta.tags(@import("adapters/provider/model_text_request.zig").ReasoningEffort)) |effort| {
        var value = base;
        value.reasoning_effort = effort;
        try std.testing.expectError(error.InvalidRequest, encoding.encodeText(std.testing.allocator, value));
    }
    var temperature = base;
    temperature.temperature = .fixed;
    try std.testing.expectError(error.InvalidRequest, encoding.encodeText(std.testing.allocator, temperature));
}
