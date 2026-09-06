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

const Backend = enum { fake, bedrock };
const Wire = @import("bedrock_transport_test_fixture.zig").Wire;

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
                    fixture.wire.result = .{ .received = .{ .status = 200, .body = "{\"stopReason\":\"max_tokens\",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12}}" } };
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
    try std.testing.expectEqualStrings("https://bedrock-runtime.ap-southeast-2.amazonaws.com/model/openai.gpt-oss-20b-1%3A0/converse", value);
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
    const encoding = @import("adapters/provider/bedrock_request.zig");
    const infer = try encoding.encode(std.testing.allocator, &fixture.base.request, .inference);
    defer std.testing.allocator.free(infer);
    const count_body = try encoding.encode(std.testing.allocator, &fixture.base.request, .input_token_count);
    defer std.testing.allocator.free(count_body);
    var first = try strict.parse(std.testing.allocator, infer, .{ .maximum_depth = 32 }, false);
    defer first.deinit();
    var second = try strict.parse(std.testing.allocator, count_body, .{ .maximum_depth = 32 }, false);
    defer second.deinit();
    const counted = second.value.object.get("input").?.object.get("converse").?;
    for ([_][]const u8{ "system", "messages" }) |name| {
        const a = try std.json.Stringify.valueAlloc(std.testing.allocator, first.value.object.get(name).?, .{});
        defer std.testing.allocator.free(a);
        const b = try std.json.Stringify.valueAlloc(std.testing.allocator, counted.object.get(name).?, .{});
        defer std.testing.allocator.free(b);
        try std.testing.expectEqualStrings(a, b);
    }
    try std.testing.expectEqual(@as(usize, 2), first.value.object.get("system").?.array.items.len);
    for ([_][]const u8{ "maxTokens", "model_request_id", "binding_id", "deadline", "Authorization", "outputConfig" }) |name| {
        try std.testing.expect(std.mem.indexOf(u8, infer, name) == null);
        try std.testing.expect(std.mem.indexOf(u8, count_body, name) == null);
    }
}

test "Bedrock native profile proves exact representability without stripping constraints or fallback" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    fixture.base.registry_entry.capabilities = contracts.registry.entries[0].capabilities;
    fixture.base.provider_binding.response_mode = .native_schema;
    fixture.base.request.response_guidance_mode = .native_schema;
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const accepted = [_][]const u8{
        "{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":false}",
        "{\"type\":\"object\",\"properties\":{\"ok\":{\"type\":\"boolean\"},\"value\":{\"enum\":[\"a\",\"b\"]}},\"required\":[\"ok\"],\"additionalProperties\":false}",
    };
    for (accepted) |bytes| {
        fixture.base.request.response_schema = try parser.compiler().compile(fixture.base.schema_arena.allocator(), bytes);
        try std.testing.expect(fixture.base.request.matchesBinding(fixture.base.provider_binding));
        const body = try @import("adapters/provider/bedrock_request.zig").encode(std.testing.allocator, &fixture.base.request, .inference);
        defer std.testing.allocator.free(body);
        var parsed = try strict.parse(std.testing.allocator, body, .{ .maximum_depth = 32 }, false);
        defer parsed.deinit();
        const schema = parsed.value.object.get("outputConfig").?.object.get("textFormat").?.object.get("structure").?.object.get("jsonSchema").?.object.get("schema").?.string;
        try std.testing.expectEqualStrings(bytes, schema);
        try std.testing.expectEqual(@as(usize, 1), parsed.value.object.get("system").?.array.items.len);
    }
    for ([_][]const u8{ "{\"type\":\"string\",\"maxLength\":100}", "{\"type\":\"integer\",\"minimum\":0,\"maximum\":4}", "{\"type\":\"array\",\"maxItems\":2,\"items\":{\"type\":\"boolean\"}}" }) |property| {
        const bytes = try std.fmt.allocPrint(fixture.base.schema_arena.allocator(), "{{\"type\":\"object\",\"properties\":{{\"value\":{s}}},\"required\":[\"value\"],\"additionalProperties\":false}}", .{property});
        fixture.base.request.response_schema = try parser.compiler().compile(fixture.base.schema_arena.allocator(), bytes);
        try std.testing.expect(!fixture.base.request.matchesBinding(fixture.base.provider_binding));
        fixture.base.request.response_guidance_mode = .prompt_only;
        fixture.base.provider_binding.response_mode = .prompt_only;
        try std.testing.expect(fixture.base.request.matchesBinding(fixture.base.provider_binding));
        fixture.base.request.response_guidance_mode = .native_schema;
        fixture.base.provider_binding.response_mode = .native_schema;
    }
}

test "Bedrock response rejects malformed UTF8 identity-shaped unknown data and inconsistent usage" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .bedrock);
    defer fixture.deinit();
    const original = @import("bedrock_transport_test_fixture.zig").complete;
    const changes = [_][2][]const u8{
        .{ "\"text\":\"{}\"", "\"text\":\"\xff\"" },
        .{ "\"text\":\"{}\"", "\"text\":\"{}\",\"text\":\"{}\"" },
        .{ "\"totalTokens\":12", "\"totalTokens\":11" },
        .{ "\"inputTokens\":10", "\"inputTokens\":\"10\"" },
        .{ "\"inputTokens\":10", "\"inputTokens\":18446744073709551615" },
        .{ "\"latencyMs\":1", "\"latencyMs\":1,\"secret\":true" },
        .{ "\"role\":\"assistant\"", "\"role\":\"user\"" },
        .{ "\"end_turn\"", "\"stop_sequence\"" },
        .{ "\"end_turn\"", "\"unknown\"" },
    };
    for (changes) |change| {
        const bytes = try std.mem.replaceOwned(u8, std.testing.allocator, original, change[0], change[1]);
        defer std.testing.allocator.free(bytes);
        var observed = try response.inference(std.testing.allocator, .{ .received = .{ .status = 200, .body = bytes } }, &fixture.base.provider_binding, &fixture.base.request, fixture.base.id(.inference));
        defer observed.deinit();
        try std.testing.expectEqual(.response_invalid, observed.failed.cause);
        try std.testing.expectEqual(.response_received, observed.failed.delivery);
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
    for ([_][]const u8{ "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "BEDROCK_API_KEY", "AWS_REGION", "AWS_ENDPOINT_URL", "HTTPS_PROXY", "AWS_CA_BUNDLE" }) |name| try environment.put(name, &canary);
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
