const std = @import("std");
const operation = @import("domain/llm_provider_operation.zig");
const fixture_module = @import("provider_authorization_test_fixture.zig");
const authorization = @import("adapters/provider/bedrock_authorization.zig");
const key = @import("adapters/provider/bedrock_api_key.zig");
const bedrock = @import("adapters/provider/aws_bedrock.zig");
const transport = @import("adapters/provider/bedrock_transport.zig");
const fake = @import("adapters/provider/fake_llm_provider.zig");
const contracts = @import("composition/provider_model_contracts.zig");
const response = @import("adapters/provider/bedrock_response.zig");
const strict = @import("domain/strict_json.zig");
const capture_port = @import("ports/model_exchange_capture.zig");
const prompt_log = @import("domain/sanitized_prompt_log.zig");

test {
    _ = @import("bedrock_http_test.zig");
}

const Backend = enum { fake, bedrock };
const Wire = @import("bedrock_transport_test_fixture.zig").Wire;

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
    real: bedrock.Provider,
    fake_provider: fake.FakeLLMProvider,
    backend: Backend,

    fn init(self: *Fixture, allocator: std.mem.Allocator, backend: Backend) !void {
        try self.base.init(allocator);
        errdefer self.base.deinit();
        const contract = contracts.registry.entries[1];
        self.base.registry_entry.provider = contract.provider;
        self.base.registry_entry.model = contract.model;
        self.base.registry_entry.capabilities = contract.capabilities;
        self.base.registry_entry.config = .{ .aws_bedrock = .{ .region = .@"us-west-2" } };
        self.base.registry_entry.supported_reasoning_efforts = &.{};
        self.base.provider_binding.reasoning_effort = null;
        self.base.request.binding_id = self.base.provider_binding.bindingId();
        self.auth = .{ .allocator = allocator };
        var canary: [48]u8 = undefined;
        std.testing.io.random(&canary);
        for (&canary) |*byte| byte.* = 'A' + byte.* % 26;
        defer std.crypto.secureZero(u8, &canary);
        self.auth.material = .{ .ready = (try key.Snapshot.capture(allocator, &canary)).? };
        self.backend = backend;
        self.wire = .{};
        self.real = .{ .allocator = allocator, .authorization_leases = self.base.leasePort(), .transport = self.wire.port() };
        self.fake_provider = .{ .allocator = allocator, .authorization_leases = self.base.leasePort(), .count_plan = .{ .counted = 10 }, .invocation_plan = .{ .complete = .{ .content = "{}", .input_tokens = 10, .output_tokens = 2, .provider_latency_ms = 1 } } };
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
    fn start(self: *Fixture, kind: operation.ProviderOperationKind) !fixture_module.Authorized {
        try self.base.change(kind, switch (kind) {
            .input_token_count => .{ .assign_count = self.base.assignment() },
            .inference => .{ .assign_inference = self.base.assignment() },
        });
        var preparation = self.base.preparationRunner();
        if (self.backend == .bedrock) preparation.prepare_action.authorization = self.auth.port();
        const prepared = try preparation.prepare(self.base.facts(kind));
        return .{ .reference = prepared.prepared, .invoked = try self.base.invoke(kind) };
    }
    fn call(self: *Fixture, authorized: fixture_module.Authorized) !operation.ProviderInvocationObservation {
        return self.port().invoke(&self.base.provider_binding, &self.base.request, authorized.reference, authorized.invoked);
    }
    fn count(self: *Fixture, authorized: fixture_module.Authorized) !operation.ProviderTokenCountObservation {
        return self.port().countInputTokens(&self.base.provider_binding, &self.base.request, authorized.reference, authorized.invoked);
    }
    fn effects(self: *const Fixture) usize {
        return switch (self.backend) {
            .fake => self.fake_provider.effect_count,
            .bedrock => self.wire.calls,
        };
    }
};

test "shared fake and Bedrock inference conformance: identity usage owned content and single use" {
    inline for (std.meta.tags(Backend)) |backend| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator, backend);
        defer fixture.deinit();
        const authorized = try fixture.start(.inference);
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
    const Expected = enum { complete, malformed, stopped, rejected, http_error };
    const cases = [_]struct { body: []const u8, status: u16 = 200, exception: ?[]const u8 = null, expected: Expected }{
        .{ .body = @import("bedrock_transport_test_fixture.zig").complete, .expected = .complete },
        .{ .body = "\xffnot-json", .expected = .malformed },
        .{ .body = "{\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"\"},\"finish_reason\":\"length\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2,\"total_tokens\":12}}", .expected = .stopped },
        .{ .body = "{\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"\"},\"finish_reason\":\"unknown\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2,\"total_tokens\":12}}", .expected = .rejected },
        .{ .body = "{\"message\":\"unparsed provider error detail\"}", .status = 429, .exception = "ThrottlingException", .expected = .http_error },
    };
    for (cases) |case| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator, .bedrock);
        defer fixture.deinit();
        var capture: CaptureSpy = .{ .allocator = std.testing.allocator, .expected_secret = fixture.auth.material.ready.bytes };
        defer capture.deinit();
        var wire: CaptureObservedWire = .{ .inner = &fixture.wire, .capture = &capture };
        fixture.real.capture = capture.port();
        fixture.real.transport = wire.port();
        fixture.wire.result = .{ .received = .{ .status = case.status, .exception = case.exception, .body = case.body } };
        const authorized = try fixture.start(.inference);
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
            .http_error => try std.testing.expectEqual(.throttled, observed.failed.cause),
        }
    }
}

test "Bedrock captures token-count request and raw response with sanitizer credential authority" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    var capture: CaptureSpy = .{ .allocator = std.testing.allocator, .expected_secret = fixture.auth.material.ready.bytes };
    defer capture.deinit();
    var wire: CaptureObservedWire = .{ .inner = &fixture.wire, .capture = &capture };
    fixture.real.capture = capture.port();
    fixture.real.transport = wire.port();
    const observed = try fixture.count(try fixture.start(.input_token_count));
    const evidence = try operation.ExactInputTokenCountEvidence.fromObservation(observed, fixture.base.request, fixture.base.provider_binding);
    try std.testing.expectEqual(@as(u64, 10), evidence.input_tokens);
    try std.testing.expect(wire.request_matches_prior_capture);
    try std.testing.expect(!capture.allocation_failed);
    try std.testing.expectEqual(@as(usize, 2), capture.calls.items.len);
    try std.testing.expectEqual(.response, capture.calls.items[1].direction);
    try std.testing.expectEqualStrings("{\"inputTokens\":10}", capture.calls.items[1].body);
    for (capture.calls.items) |call| try std.testing.expect(call.credential_matches);
}

test "Bedrock request capture failure prevents transport for inference and token counting" {
    for (std.enums.values(operation.ProviderOperationKind)) |kind| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator, .bedrock);
        defer fixture.deinit();
        var capture: CaptureSpy = .{ .allocator = std.testing.allocator, .expected_secret = fixture.auth.material.ready.bytes, .block_direction = .request };
        defer capture.deinit();
        fixture.real.capture = capture.port();
        const authorized = try fixture.start(kind);
        switch (kind) {
            .inference => try std.testing.expectError(error.ModelLoggingBlocked, fixture.call(authorized)),
            .input_token_count => try std.testing.expectError(error.ModelLoggingBlocked, fixture.count(authorized)),
        }
        try std.testing.expectEqual(@as(usize, 0), fixture.effects());
        try std.testing.expectEqual(@as(usize, 1), capture.calls.items.len);
        try std.testing.expect(capture.calls.items[0].credential_matches);
        switch (kind) {
            .inference => {
                var reused = try fixture.call(authorized);
                defer reused.deinit();
                try std.testing.expectEqual(.authorization_denied, reused.failed.cause);
            },
            .input_token_count => try std.testing.expectEqual(.authorization_denied, (try fixture.count(authorized)).failed.cause),
        }
        try std.testing.expectEqual(@as(usize, 2), capture.calls.items.len);
        try std.testing.expectEqual(.transport_outcome, capture.calls.items[1].kind);
        try std.testing.expect(std.mem.indexOf(u8, capture.calls.items[1].body, "rejected_before_send") != null);
        try std.testing.expectEqual(@as(usize, 0), fixture.effects());
    }
}

test "Bedrock response capture failure preserves completed stopped and rejected usage" {
    const bodies = [_][]const u8{
        @import("bedrock_transport_test_fixture.zig").complete,
        "{\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"\"},\"finish_reason\":\"length\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2,\"total_tokens\":12}}",
        "{\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"\"},\"finish_reason\":\"unknown\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2,\"total_tokens\":12}}",
    };
    for (bodies) |body| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator, .bedrock);
        defer fixture.deinit();
        var capture: CaptureSpy = .{ .allocator = std.testing.allocator, .expected_secret = fixture.auth.material.ready.bytes, .block_direction = .response };
        defer capture.deinit();
        fixture.real.capture = capture.port();
        fixture.wire.inference_body = body;
        var observed = try fixture.call(try fixture.start(.inference));
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

test "Bedrock response capture failure preserves exact input token count" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    var capture: CaptureSpy = .{ .allocator = std.testing.allocator, .expected_secret = fixture.auth.material.ready.bytes, .block_direction = .response };
    defer capture.deinit();
    fixture.real.capture = capture.port();
    const observed = try fixture.count(try fixture.start(.input_token_count));
    const evidence = try operation.ExactInputTokenCountEvidence.fromObservation(observed, fixture.base.request, fixture.base.provider_binding);
    try std.testing.expectEqual(@as(u64, 10), evidence.input_tokens);
    try std.testing.expectEqual(@as(usize, 1), fixture.effects());
    try std.testing.expectEqual(@as(usize, 2), capture.calls.items.len);
}

test "transport observation survives failure to capture its diagnostic" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    var capture: CaptureSpy = .{ .allocator = std.testing.allocator, .expected_secret = fixture.auth.material.ready.bytes, .block_direction = .response };
    defer capture.deinit();
    fixture.real.capture = capture.port();
    fixture.wire.result = .{ .failed = .{ .cause = .service_unavailable, .retry_class = .policy_eligible, .delivery = .not_sent } };
    var observed = try fixture.call(try fixture.start(.inference));
    defer observed.deinit();
    try std.testing.expectEqual(.service_unavailable, observed.failed.cause);
    try std.testing.expectEqual(.not_sent, observed.failed.delivery);
    try std.testing.expectEqual(.transport_outcome, capture.calls.items[1].kind);
}

test "Bedrock captures concrete HTTP failure bodies before metadata for inference and counting" {
    const http = @import("bedrock_http_test_fixture.zig");
    for (std.enums.values(operation.ProviderOperationKind)) |kind| {
        for ([_]http.Fault{ .none, .eof, .reset, .deadline, .cancelled }) |fault| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator, .bedrock);
            defer fixture.deinit();
            var capture: CaptureSpy = .{ .allocator = std.testing.allocator, .expected_secret = fixture.auth.material.ready.bytes };
            defer capture.deinit();
            fixture.real.capture = capture.port();
            const body = try std.fmt.allocPrint(std.testing.allocator, "echo {s} " ++ "retained body " ** 500, .{fixture.auth.material.ready.bytes});
            defer std.testing.allocator.free(body);
            const wire = try std.fmt.allocPrint(std.testing.allocator, "HTTP/1.1 {s}\r\nContent-Length: {d}\r\n\r\n{s}", .{ if (fault == .none) "307 Temporary Redirect" else "200 OK", body.len, body });
            defer std.testing.allocator.free(wire);
            var connection: http.Fixture = undefined;
            connection.init(wire);
            defer connection.deinit();
            connection.expected_host = "bedrock-runtime.us-west-2.amazonaws.com";
            connection.fault = fault;
            connection.body_prefix_bytes = body.len - 3;
            connection.maximum_read = 257;
            var adapter = connection.adapter();
            fixture.real.transport = adapter.port();
            const authorized = try fixture.start(kind);
            connection.now_ms.store(authorized.invoked.deadline_monotonic_ms - 100, .release);
            if (fault == .cancelled) {
                switch (kind) {
                    .inference => try std.testing.expectError(error.Cancelled, fixture.call(authorized)),
                    .input_token_count => try std.testing.expectError(error.Cancelled, fixture.count(authorized)),
                }
            } else {
                const observed = switch (kind) {
                    .inference => observed: {
                        var value = try fixture.call(authorized);
                        defer value.deinit();
                        break :observed value.failed;
                    },
                    .input_token_count => (try fixture.count(authorized)).failed,
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
}

test "Bedrock captures explicit no-body outcomes on failed cancelled and allocation-failed transport" {
    for ([_][]const u8{ "transport_failed", "cancelled", "allocation_failed" }, 0..) |outcome, scenario| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator, .bedrock);
        defer fixture.deinit();
        var capture: CaptureSpy = .{ .allocator = std.testing.allocator, .expected_secret = fixture.auth.material.ready.bytes };
        defer capture.deinit();
        var wire: CaptureObservedWire = .{ .inner = &fixture.wire, .capture = &capture };
        fixture.real.capture = capture.port();
        fixture.real.transport = wire.port();
        const authorized = try fixture.start(.inference);
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

test "shared fake and Bedrock count conformance: exact evidence and single use" {
    inline for (std.meta.tags(Backend)) |backend| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator, backend);
        defer fixture.deinit();
        const authorized = try fixture.start(.input_token_count);
        const observed = try fixture.count(authorized);
        const evidence = try operation.ExactInputTokenCountEvidence.fromObservation(observed, fixture.base.request, fixture.base.provider_binding);
        try std.testing.expect(evidence.count_operation_id.eql(authorized.invoked.id));
        try std.testing.expectEqual(@as(u64, 10), evidence.input_tokens);
        const reused = try fixture.count(authorized);
        try std.testing.expectEqual(.authorization_denied, reused.failed.cause);
        try std.testing.expectEqual(@as(usize, 1), fixture.effects());
    }
}

test "shared fake and Bedrock reject foreign request binding operation kind and deadlines before effects" {
    inline for (std.meta.tags(Backend)) |backend| {
        for (0..5) |scenario| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator, backend);
            defer fixture.deinit();
            const authorized = try fixture.start(.inference);
            var request_copy = fixture.base.request.model_request_id.*;
            var operation_copy = authorized.invoked.*;
            switch (scenario) {
                0 => fixture.base.request.model_request_id = &request_copy,
                1 => fixture.base.provider_binding.slot_id = .{ .bytes = "foreign" },
                2 => fixture.base.clock.now_ms = authorized.invoked.deadline_monotonic_ms,
                3 => operation_copy.id.kind = .input_token_count,
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
            const authorized = try fixture.start(.inference);
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
                    fixture.wire.result = .{ .received = .{ .status = 200, .body = "{\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"\"},\"finish_reason\":\"length\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2,\"total_tokens\":12}}" } };
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

test "production contracts require exact externally selected model region and closed config" {
    try contracts.registry.validate();
    const model = contracts.registry.entries[0];
    try std.testing.expect(!model.capabilities.input_token_count);
    try std.testing.expect(model.acceptsConfig(.{ .aws_bedrock = .{ .region = .@"ap-southeast-2" } }));
    try std.testing.expect(!model.acceptsConfig(.{ .aws_bedrock = .{ .region = .@"us-west-2" } }));
    const config = @import("domain/llm_provider_config_schema.zig");
    for ([_][]const u8{ "{}", "{\"region\":null}", "{\"region\":\"unknown\"}", "{\"region\":\"ap-southeast-2\",\"apiKey\":null}", "{\"region\":\"ap-southeast-2\",\"endpoint\":null}", "{\"region\":\"ap-southeast-2\",\"inputTokens\":10}" }) |bytes| {
        var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, bytes, .{});
        defer parsed.deinit();
        try std.testing.expect(config.decode(.aws_bedrock, parsed.value) == null);
    }
}

test "Bedrock endpoint encoding is HTTPS fixed-region with no target reinterpretation" {
    const http = @import("adapters/provider/bedrock_http.zig");
    const value = try http.endpoint(std.testing.allocator, .{ .region = .@"ap-southeast-2", .model = contracts.registry.entries[0].model, .kind = .inference, .body = "", .api_key = "", .deadline_monotonic_ms = 1 });
    defer std.testing.allocator.free(value);
    try std.testing.expectEqualStrings("https://bedrock-runtime.ap-southeast-2.amazonaws.com/model/openai.gpt-oss-20b-1%3A0/invoke", value);
    // Force native HTTP implementation compilation without a network request.
    _ = &http.Adapter.port;
}

test "Bedrock count decoding rejects malformed unknown duplicate non-integer and overflowing evidence" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    for ([_][]const u8{ "{}", "{\"inputTokens\":-1}", "{\"inputTokens\":1.0}", "{\"inputTokens\":\"1\"}", "{\"inputTokens\":18446744073709551616}", "{\"inputTokens\":1,\"inputTokens\":1}", "{\"inputTokens\":1} {}", "{\"inputTokens\":1,\"extra\":false}" }) |bytes| {
        const result = try response.count(std.testing.allocator, .{ .received = .{ .status = 200, .body = bytes } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.input_token_count));
        try std.testing.expectEqual(.exact_token_count_unavailable, result.failed.cause);
    }
}

test "Bedrock allocation failures release request response and single-use authorization owners" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
fn allocationCase(allocator: std.mem.Allocator) !void {
    var fixture: Fixture = undefined;
    try fixture.init(allocator, .bedrock);
    defer fixture.deinit();
    const authorized = try fixture.start(.inference);
    var observed = try fixture.call(authorized);
    defer observed.deinit();
}

test "Bedrock projects the exact input once for both APIs without size controls or identity echoes" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    fixture.base.request.response_schema = try parser.compiler().compile(fixture.base.schema_arena.allocator(),
        \\{ "$defs": {"flag": {"type":"boolean"}}, "type":"object", "properties":{"ok":{"$ref":"#/$defs/flag"}}, "required":["ok"], "additionalProperties":false }
    );
    const encoding = @import("adapters/provider/bedrock_request.zig");
    const infer = try encoding.encode(std.testing.allocator, &fixture.base.request, .inference);
    defer std.testing.allocator.free(infer);
    const count_body = try encoding.encode(std.testing.allocator, &fixture.base.request, .input_token_count);
    defer std.testing.allocator.free(count_body);
    var first = try strict.parse(std.testing.allocator, infer, .{ .maximum_depth = 32 }, false, null);
    defer first.deinit();
    const decoded_count = try @import("bedrock_transport_test_fixture.zig").requestBody(std.testing.allocator, count_body, .input_token_count);
    defer std.testing.allocator.free(decoded_count);
    try std.testing.expectEqualStrings(infer, decoded_count);
    try std.testing.expectEqual(@as(usize, 3), first.value.object.get("messages").?.array.items[0].object.get("content").?.array.items.len);
    const framing = @import("domain/model_controls.zig").response_format_guidance;
    try std.testing.expectEqualStrings(framing, first.value.object.get("messages").?.array.items[0].object.get("content").?.array.items[1].object.get("text").?.string);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, infer, framing));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, decoded_count, framing));
    try std.testing.expectEqualStrings(fixture.base.request.response_schema.modelBytes(), first.value.object.get("messages").?.array.items[0].object.get("content").?.array.items[2].object.get("text").?.string);
    try std.testing.expect(std.mem.indexOf(u8, infer, "$ref") == null);
    try std.testing.expect(std.mem.indexOf(u8, infer, "$defs") == null);
    for ([_][]const u8{ "max_completion_tokens", "model_request_id", "binding_id", "deadline", "Authorization", "outputConfig" }) |name| {
        try std.testing.expect(std.mem.indexOf(u8, infer, name) == null);
        try std.testing.expect(std.mem.indexOf(u8, decoded_count, name) == null);
    }
}

test "Bedrock native projection retains complete guidance and registered mode without fallback" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    fixture.base.registry_entry.capabilities = contracts.registry.entries[0].capabilities;
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
        const body = try @import("adapters/provider/bedrock_request.zig").encode(std.testing.allocator, &fixture.base.request, .inference);
        defer std.testing.allocator.free(body);
        var parsed = try strict.parse(std.testing.allocator, body, .{ .maximum_depth = 32 }, false, null);
        defer parsed.deinit();
        const format = parsed.value.object.get("response_format").?;
        try std.testing.expectEqualStrings("json_schema", format.object.get("type").?.string);
        const schema = try std.json.Stringify.valueAlloc(std.testing.allocator, format.object.get("json_schema").?.object.get("schema").?, .{});
        defer std.testing.allocator.free(schema);
        try std.testing.expectEqualStrings(fixture.base.request.response_schema.modelBytes(), schema);
        try std.testing.expectEqualDeep(fixture.base.request.response_schema.root().*, (try parser.compiler().compile(fixture.base.schema_arena.allocator(), schema)).root().*);
        try std.testing.expectEqual(@as(usize, 3), parsed.value.object.get("messages").?.array.items[0].object.get("content").?.array.items.len);
        const framing = @import("domain/model_controls.zig").response_format_guidance;
        try std.testing.expectEqualStrings(framing, parsed.value.object.get("messages").?.array.items[0].object.get("content").?.array.items[1].object.get("text").?.string);
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, body, framing));
    }
    for ([_][]const u8{ "{\"type\":\"string\",\"maxLength\":100}", "{\"type\":\"integer\",\"minimum\":0,\"maximum\":4}", "{\"type\":\"array\",\"maxItems\":2,\"items\":{\"type\":\"boolean\"}}" }) |property| {
        const bytes = try std.fmt.allocPrint(fixture.base.schema_arena.allocator(), "{{\"type\":\"object\",\"properties\":{{\"value\":{s}}},\"required\":[\"value\"],\"additionalProperties\":false}}", .{property});
        fixture.base.request.response_schema = try parser.compiler().compile(fixture.base.schema_arena.allocator(), bytes);
        try std.testing.expect(fixture.base.request.matchesBinding(fixture.base.provider_binding));
        const native = try @import("adapters/provider/bedrock_request.zig").encode(std.testing.allocator, &fixture.base.request, .inference);
        defer std.testing.allocator.free(native);
        var wire = try strict.parse(std.testing.allocator, native, .{ .maximum_depth = 32 }, false, null);
        defer wire.deinit();
        try std.testing.expectEqualStrings(fixture.base.request.response_schema.modelBytes(), wire.value.object.get("messages").?.array.items[0].object.get("content").?.array.items[2].object.get("text").?.string);
        const projection = try std.json.Stringify.valueAlloc(std.testing.allocator, wire.value.object.get("response_format").?.object.get("json_schema").?.object.get("schema").?, .{});
        defer std.testing.allocator.free(projection);
        for ([_][]const u8{ "maxLength", "minimum", "maximum", "maxItems" }) |unsupported| try std.testing.expect(std.mem.indexOf(u8, projection, unsupported) == null);
        fixture.base.request.response_guidance_mode = .prompt_only;
        fixture.base.registry_entry.json = false;
        try std.testing.expect(fixture.base.request.matchesBinding(fixture.base.provider_binding));
        fixture.base.request.response_guidance_mode = .native_schema;
        fixture.base.registry_entry.json = true;
    }
}

test "Bedrock reasoning effort is explicit registered and retained in the counted body" {
    const encoding = @import("adapters/provider/bedrock_request.zig");
    for ([_]?[]const u8{ null, "low", "medium", "high" }) |effort| {
        for (contracts.registry.entries, 0..) |contract, index| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator, .bedrock);
            defer fixture.deinit();
            fixture.base.registry_entry.provider = contract.provider;
            fixture.base.registry_entry.model = contract.model;
            fixture.base.registry_entry.capabilities = contract.capabilities;
            fixture.base.registry_entry.config = .{ .aws_bedrock = .{ .region = contract.bedrock_regions[0] } };
            fixture.base.registry_entry.supported_reasoning_efforts = contract.supported_reasoning_efforts;
            fixture.base.provider_binding.reasoning_effort = effort;
            fixture.base.request.binding_id = fixture.base.provider_binding.bindingId();
            const authorized = try fixture.start(.inference);
            var observed = try fixture.call(authorized);
            defer observed.deinit();
            if (index == 1 and effort != null) {
                try std.testing.expectEqual(.request_rejected, observed.failed.cause);
                try std.testing.expectEqual(.not_sent, observed.failed.delivery);
                try std.testing.expectEqual(@as(usize, 0), fixture.effects());
                continue;
            }
            try std.testing.expect(observed == .completed);
            try std.testing.expectEqual(@as(usize, 1), fixture.effects());
            const bytes = try encoding.encode(std.testing.allocator, &fixture.base.request, .inference);
            defer std.testing.allocator.free(bytes);
            var parsed = try strict.parse(std.testing.allocator, bytes, .{ .maximum_depth = 32 }, false, null);
            defer parsed.deinit();
            const additional = parsed.value.object.get("reasoning_effort");
            if (effort) |value| {
                try std.testing.expectEqualStrings(value, additional.?.string);
            } else try std.testing.expect(additional == null);
            const counted = try encoding.encode(std.testing.allocator, &fixture.base.request, .input_token_count);
            defer std.testing.allocator.free(counted);
            const counted_body = try @import("bedrock_transport_test_fixture.zig").requestBody(std.testing.allocator, counted, .input_token_count);
            defer std.testing.allocator.free(counted_body);
            try std.testing.expectEqualStrings(bytes, counted_body);
            try std.testing.expect(!parsed.value.object.contains("max_completion_tokens"));
        }
    }
    for ([_][]const u8{ "", "LOW", "none", "minimal", "xhigh", "low\n", "unknown" }) |invalid|
        try std.testing.expectError(error.InvalidRequest, encoding.reasoningEffort(invalid));
}

test "Bedrock response rejects malformed UTF8 identity-shaped unknown data and inconsistent usage" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    const original = @import("bedrock_transport_test_fixture.zig").complete;
    const changes = [_][2][]const u8{
        .{ "\"content\":\"{}\"", "\"content\":\"\xff\"" },
        .{ "\"content\":\"{}\"", "\"content\":\"{}\",\"content\":\"{}\"" },
        .{ "\"total_tokens\":12", "\"total_tokens\":11" },
        .{ "\"prompt_tokens\":10", "\"prompt_tokens\":\"10\"" },
        .{ "\"prompt_tokens\":10", "\"prompt_tokens\":18446744073709551615" },
        .{ "\"total_tokens\":12", "\"total_tokens\":12,\"secret\":true" },
        .{ "\"role\":\"assistant\"", "\"role\":\"user\"" },
        .{ "\"stop\"", "\"stop_sequence\"" },
        .{ "\"stop\"", "\"unknown\"" },
    };
    for (changes, 0..) |change, index| {
        const bytes = try std.mem.replaceOwned(u8, std.testing.allocator, original, change[0], change[1]);
        defer std.testing.allocator.free(bytes);
        var observed = try response.inference(std.testing.allocator, .{ .received = .{ .status = 200, .body = bytes } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
        defer observed.deinit();
        if (index >= 6) {
            try std.testing.expectEqual(.invalid_content, observed.completed.raw_result.rejected.reason);
            try std.testing.expectEqual(@as(u64, 12), observed.completed.raw_result.rejected.usage.total_tokens);
        } else {
            try std.testing.expectEqual(.response_invalid, observed.failed.cause);
            try std.testing.expectEqual(.response_received, observed.failed.delivery);
        }
    }
}

test "Bedrock InvokeModel separates reasoning and retains usage on invalid final content" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    const cases = [_]struct { content: []const u8, missing: bool = false, expected: []const u8 = "{}" }{
        .{ .content = "{}" },
        .{ .content = "<reasoning>metadata</reasoning>{}" },
        .{ .content = " \n<reasoning>metadata</reasoning> \n{}" },
        .{ .content = "<reasoning>{}</reasoning>", .missing = true },
        .{ .content = "<reasoning>unfinished", .missing = true },
        .{ .content = "", .missing = true },
        .{ .content = " \t\n", .missing = true },
        .{ .content = "<reasoning>notes</reasoning>{broken", .expected = "{broken" },
        .{ .content = "prefix {}", .expected = "prefix {}" },
        .{ .content = "{\"text\":\"<reasoning>literal</reasoning>\"}", .expected = "{\"text\":\"<reasoning>literal</reasoning>\"}" },
    };
    for (cases) |case| {
        const bytes = try std.json.Stringify.valueAlloc(std.testing.allocator, .{
            .choices = .{.{ .index = @as(u32, 0), .message = .{ .role = "assistant", .content = case.content }, .finish_reason = "stop" }},
            .usage = .{ .prompt_tokens = 10, .completion_tokens = 2, .total_tokens = 12 },
        }, .{});
        defer std.testing.allocator.free(bytes);
        var observed = try response.inference(std.testing.allocator, .{ .received = .{ .status = 200, .body = bytes } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
        defer observed.deinit();
        if (case.missing) {
            const rejected = observed.completed.raw_result.rejected;
            try std.testing.expectEqual(.missing_final_text, rejected.reason);
            try std.testing.expectEqual(@as(u64, 12), rejected.usage.total_tokens);
            try std.testing.expect(rejected.request_id == fixture.base.model_request_id);
            try std.testing.expect(rejected.binding_id.eql(fixture.base.provider_binding.bindingId()));
        } else {
            try std.testing.expectEqualStrings(case.expected, observed.completed.raw_result.complete.content.bytes);
            try std.testing.expectEqual(@as(u64, 12), observed.completed.raw_result.complete.usage.total_tokens);
        }
    }
}

test "InvokeModel content failures preserve usage and reject ambiguous answers" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    const original = @import("bedrock_transport_test_fixture.zig").complete;
    for ([_]struct { old: []const u8, new: []const u8, reason: operation.ProviderContentDiagnostic = .invalid_content }{
        .{ .old = "\"index\":0", .new = "\"index\":1" },
        .{ .old = "\"content\":\"{}\"", .new = "\"content\":{}" },
        .{ .old = "\"content\":\"{}\"", .new = "\"content\":null", .reason = .missing_final_text },
        .{ .old = ",\"content\":\"{}\"", .new = "", .reason = .missing_final_text },
        .{ .old = "\"message\":", .new = "\"logprobs\":{},\"message\":" },
        .{ .old = "\"role\":\"assistant\"", .new = "\"role\":\"assistant\",\"unexpected\":true" },
    }) |case| {
        const bytes = try std.mem.replaceOwned(u8, std.testing.allocator, original, case.old, case.new);
        defer std.testing.allocator.free(bytes);
        try std.testing.expect(!std.mem.eql(u8, bytes, original));
        var observed = try response.inference(std.testing.allocator, .{ .received = .{ .status = 200, .body = bytes } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
        defer observed.deinit();
        try std.testing.expectEqual(case.reason, observed.completed.raw_result.rejected.reason);
        try std.testing.expectEqual(@as(u64, 12), observed.completed.raw_result.rejected.usage.total_tokens);
    }
    for ([_]usize{ 0, 2 }) |count| {
        const choice = .{ .index = @as(u32, 0), .message = .{ .role = "assistant", .content = "{}" }, .finish_reason = "stop" };
        const choices = [_]@TypeOf(choice){ choice, choice };
        const bytes = try std.json.Stringify.valueAlloc(std.testing.allocator, .{
            .choices = choices[0..count],
            .usage = .{ .prompt_tokens = 10, .completion_tokens = 2, .total_tokens = 12 },
        }, .{});
        defer std.testing.allocator.free(bytes);
        var observed = try response.inference(std.testing.allocator, .{ .received = .{ .status = 200, .body = bytes } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
        defer observed.deinit();
        try std.testing.expectEqual(.invalid_content, observed.completed.raw_result.rejected.reason);
        try std.testing.expectEqual(@as(u64, 12), observed.completed.raw_result.rejected.usage.total_tokens);
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
    const secret_body = try std.json.Stringify.valueAlloc(std.testing.allocator, .{ .message = fixture.auth.material.ready.bytes }, .{});
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
    const head = try @import("adapters/provider/bedrock_http_head.zig").receive(std.testing.allocator, &reader);
    defer std.testing.allocator.free(head);
    const parsed = try std.http.Client.Response.Head.parse(head);
    try std.testing.expectEqual(.ok, parsed.status);
    try std.testing.expectEqualStrings("{}", reader.buffered());
}

test "native Bedrock inference and token counting cannot connect from tests with credentials" {
    const http_fixture = @import("bedrock_http_test_fixture.zig");
    var connection: http_fixture.Fixture = undefined;
    connection.init("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}");
    defer connection.deinit();
    var adapter: @import("adapters/provider/bedrock_http.zig").Adapter = .{
        .io = connection.io(),
        .clock = connection.adapter().clock,
        .runtime = .{},
    };
    for ([_]operation.ProviderOperationKind{ .inference, .input_token_count }) |kind| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const observed = try adapter.port().exchange(arena.allocator(), connection.request(kind));
        try std.testing.expectEqual(.transport_failed, observed.failed.cause);
        try std.testing.expectEqual(.not_sent, observed.failed.delivery);
        try std.testing.expectEqual(@as(usize, 0), connection.connects);
        try std.testing.expectEqual(@as(usize, 0), connection.wire.items.len);
    }
}

test "Bedrock HTTP rejects expired deadlines and cancellation before network setup" {
    var clock: fixture_module.TestClock = .{ .now_ms = 1000 };
    var adapter: @import("adapters/provider/bedrock_http.zig").Adapter = .{ .io = std.testing.io, .clock = clock.port(), .runtime = .{} };
    const request: transport.Request = .{ .region = .@"ap-southeast-2", .model = contracts.registry.entries[0].model, .kind = .inference, .body = "{}", .api_key = "", .deadline_monotonic_ms = 1000 };
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

test "Bedrock environment source accepts only its exact key and owns an immutable snapshot" {
    const source = @import("adapters/system/bedrock_api_key_source.zig");
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var missing = source.read(std.testing.allocator, &environment);
    defer missing.deinit();
    try std.testing.expect(missing == .unavailable);
    var canary: [48]u8 = undefined;
    std.testing.io.random(&canary);
    for (&canary) |*byte| byte.* = 'A' + byte.* % 26;
    defer std.crypto.secureZero(u8, &canary);
    for ([_][]const u8{ "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "BEDROCK_API_KEY", "AWS_REGION", "AWS_ENDPOINT_URL", "HTTPS_PROXY", "AWS_CA_BUNDLE", "TEST_AWS_BEARER_TOKEN_BEDROCK", "TEST_OPENAI_API_KEY", "TEST_EVALUATION_PROVIDER", "TEST_EVALUATION_MODEL", "TEST_EVALUATION_REGION" }) |name| try environment.put(name, &canary);
    var ignored = source.read(std.testing.allocator, &environment);
    defer ignored.deinit();
    try std.testing.expect(ignored == .unavailable);
    try environment.put("AWS_BEARER_TOKEN_BEDROCK", &canary);
    var material = source.read(std.testing.allocator, &environment);
    defer material.deinit();
    try std.testing.expect(material == .ready);
    try std.testing.expect(std.mem.eql(u8, material.ready.bytes, &canary));
    try environment.put("AWS_BEARER_TOKEN_BEDROCK", "");
    try std.testing.expect(std.mem.eql(u8, material.ready.bytes, &canary));
    for ([_][]const u8{ "", " ", "\r\n", "\xff" }) |invalid| {
        try environment.put("AWS_BEARER_TOKEN_BEDROCK", invalid);
        var rejected = source.read(std.testing.allocator, &environment);
        defer rejected.deinit();
        try std.testing.expect(rejected == .unavailable);
    }
}

test "shared fake and Bedrock count failures and cancellation consume only their count lease" {
    inline for (std.meta.tags(Backend)) |backend| {
        for ([_]bool{ false, true }) |cancelled| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator, backend);
            defer fixture.deinit();
            const authorized = try fixture.start(.input_token_count);
            if (cancelled) {
                fixture.fake_provider.count_plan = .cancelled;
                fixture.wire.cancelled = true;
                try std.testing.expectError(error.Cancelled, fixture.count(authorized));
            } else {
                fixture.fake_provider.count_plan = .{ .failed = .{ .cause = .timeout, .retry_class = .policy_eligible, .delivery = .accepted_or_unknown } };
                fixture.wire.result = .{ .failed = .{ .cause = .timeout, .retry_class = .policy_eligible, .delivery = .accepted_or_unknown } };
                const observed = try fixture.count(authorized);
                try std.testing.expectEqual(.timeout, observed.failed.cause);
                try std.testing.expectEqual(.policy_eligible, observed.failed.retry_class);
                try std.testing.expectEqual(.accepted_or_unknown, observed.failed.delivery);
            }
            const reused = try fixture.count(authorized);
            try std.testing.expectEqual(.authorization_denied, reused.failed.cause);
            try std.testing.expectEqual(@as(usize, 1), fixture.effects());
        }
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
        const observed = try response.count(std.testing.allocator, .{ .received = .{ .status = 424, .exception = "ModelErrorException", .body = case.body } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.input_token_count));
        try std.testing.expectEqual(case.cause, observed.failed.cause);
    }
}

test "Bedrock uses AWS restJson1 error discriminators without guessing from prose" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    for ([_][]const u8{ "{\"code\":\"ThrottlingException\"}", "{\"__type\":\"com.amazonaws.bedrock#ThrottlingException:detail\"}", "{\"__type\":\"ThrottlingException\",\"code\":\"ThrottlingException\"}" }) |body| {
        const observed = try response.count(std.testing.allocator, .{ .received = .{ .status = 429, .body = body } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.input_token_count));
        try std.testing.expectEqual(.throttled, observed.failed.cause);
    }
    const conflict = try response.count(std.testing.allocator, .{ .received = .{ .status = 429, .exception = "ThrottlingException", .body = "{\"code\":\"AccessDeniedException\"}" } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.input_token_count));
    try std.testing.expectEqual(.response_invalid, conflict.failed.cause);
}

test "Bedrock capitalized messages preserve closed error classification for inference and counting" {
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
            const counted = try response.count(std.testing.allocator, wire, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.input_token_count));
            for ([_]operation.ProviderFailure{ inferred.failed, counted.failed }) |failure| {
                try std.testing.expectEqual(case.cause, failure.cause);
                try std.testing.expectEqual(.response_received, failure.delivery);
                try std.testing.expectEqual(@as(operation.ProviderRetryClass, if (case.status == 403) .never else .policy_eligible), failure.retry_class);
            }
        }
    }
    for ([_][]const u8{ "{\"Message\":1}", "{\"Message\":null}", "{\"message\":\"same\",\"Message\":\"same\"}", "{\"message\":\"a\",\"Message\":\"b\"}", "{\"Message\":\"a\",\"unknown\":true}", "{\"Message\":\"a\",\"code\":\"ThrottlingException\"}" }) |body| {
        const wire: transport.Response = .{ .received = .{ .status = 403, .exception = "AccessDeniedException", .body = body } };
        var inferred = try response.inference(std.testing.allocator, wire, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
        defer inferred.deinit();
        const counted = try response.count(std.testing.allocator, wire, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.input_token_count));
        try std.testing.expectEqual(.response_invalid, inferred.failed.cause);
        try std.testing.expectEqual(.response_invalid, counted.failed.cause);
    }
}

test "Bedrock inference serializes zero for every registered model and omits unsupported temperature" {
    const encoding = @import("adapters/provider/bedrock_request.zig");
    for (contracts.registry.entries) |contract| {
        for ([_]bool{ true, false }) |temperature_supported| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator, .bedrock);
            defer fixture.deinit();
            fixture.base.registry_entry.provider = contract.provider;
            fixture.base.registry_entry.model = contract.model;
            fixture.base.registry_entry.capabilities = contract.capabilities;
            // The unsupported variant is a synthetic registered capability contract.
            fixture.base.registry_entry.capabilities.temperature = temperature_supported;
            fixture.base.provider_binding.controls = fixture.base.registry_entry.capabilities.inferenceControls();
            fixture.base.request.controls = fixture.base.provider_binding.controls;
            try std.testing.expect(fixture.base.request.matchesBinding(fixture.base.provider_binding));
            const bytes = try encoding.encode(std.testing.allocator, &fixture.base.request, .inference);
            defer std.testing.allocator.free(bytes);
            var parsed = try strict.parse(std.testing.allocator, bytes, .{ .maximum_depth = 32 }, false, null);
            defer parsed.deinit();
            if (temperature_supported) {
                try std.testing.expectEqualStrings("0", parsed.value.object.get("temperature").?.number_string);
            } else try std.testing.expect(parsed.value.object.get("temperature") == null);
            const counted = try encoding.encode(std.testing.allocator, &fixture.base.request, .input_token_count);
            defer std.testing.allocator.free(counted);
            try std.testing.expect(std.mem.indexOf(u8, counted, "\"temperature\"") == null);
            var altered = fixture.base.request;
            altered.controls = .forTemperatureSupport(!temperature_supported);
            var altered_binding = fixture.base.provider_binding;
            altered_binding.controls = altered.controls;
            try std.testing.expect(!altered.matchesBinding(fixture.base.provider_binding));
            try std.testing.expect(!altered.matchesBinding(altered_binding));
        }
    }
}
