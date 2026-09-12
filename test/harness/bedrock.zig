//! Internal Bedrock evaluator adapter; no workflow identity or authority.
const std = @import("std");
const c = @import("contracts.zig");
const configuration = @import("configuration.zig");
const provider = @import("provider.zig");
const packet = @import("packet.zig");
const http = @import("http.zig");
const encoding = @import("../../src/adapters/provider/bedrock_request.zig");
const decoding = @import("../../src/adapters/provider/bedrock_response.zig");
const transport = @import("../../src/adapters/provider/bedrock_transport.zig");
const lease = @import("../../src/ports/provider_authorization_lease.zig");
const operation = @import("../../src/domain/llm_provider_operation.zig");
const strict = @import("../../src/domain/strict_json.zig");
const Region = @import("../../src/domain/llm_provider_contracts.zig").BedrockRegion;

pub fn request(a: std.mem.Allocator, config: configuration.Config, capture: c.Capture) c.Error![]const u8 {
    try configuration.validate(config);
    if (config.api != .bedrock_converse) return error.InvalidEvaluationContract;
    const content = [_]operation.ModelVisibleContent{
        .{ .system = packet.instructions },
        .{ .user = try packet.input(a, capture) },
    };
    return encoding.encodeText(a, .{
        .content = &content,
        .schema = .{ .prompt_only = try packet.resultSchema(a) },
        .schema_name = "rubric_judgment",
        .temperature = config.temperature,
        .reasoning_effort = encoding.reasoningEffort(if (config.reasoning_effort) |effort| @tagName(effort) else null) catch return error.InvalidEvaluationContract,
    }, .inference) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidRequest => error.InvalidEvaluationContract,
    };
}

pub const Adapter = struct {
    transport: transport.Port,
    clock: lease.Clock,
    model: c.ModelId,
    region: Region,
    api_key: []const u8,

    pub fn port(self: *Adapter) provider.Port {
        return .{ .context = @ptrCast(self), .invoke_fn = invoke };
    }

    fn invoke(context: *provider.Context, a: std.mem.Allocator, body: []const u8, timeout_ms: u32) provider.Error!provider.Observation {
        const self: *Adapter = @ptrCast(@alignCast(context));
        if (!http.validKey(self.api_key)) return .{ .failure = .authentication };
        const now = self.clock.now() catch return .{ .failure = .provider_failed };
        const deadline = std.math.add(u64, now, timeout_ms) catch return .{ .failure = .configuration };
        const received = try self.transport.exchange(a, .{
            .region = self.region,
            .model = self.model,
            .kind = .inference,
            .body = body,
            .api_key = self.api_key,
            .deadline_monotonic_ms = deadline,
        });
        var result = try response(a, received);
        if (received == .received) {
            result.request_id = received.received.request_id;
            result.response_body = received.received.body;
        }
        // Converse has no response/model identity fields. Record only the
        // exact transport target; do not invent an echoed model or response ID.
        result.identity = .{ .bedrock_target = .{ .model = self.model.bytes, .region = self.region } };
        return result;
    }
};

pub fn response(a: std.mem.Allocator, received: transport.Response) std.mem.Allocator.Error!provider.Observation {
    if (try decoding.classifyResponse(a, received)) |failure| return .{ .failure = switch (failure.cause) {
        .authentication_failed, .authorization_denied => .authentication,
        .request_rejected, .model_unavailable => .configuration,
        .throttled => .rate_limited,
        .timeout => .timeout,
        .service_unavailable, .transport_failed => .provider_failed,
        .response_invalid, .exact_token_count_unavailable => .invalid_response,
    } };
    var parsed = strict.parse(a, received.received.body, .{ .maximum_depth = std.math.maxInt(usize) }, false, null) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else .{ .failure = .invalid_response };
    defer parsed.deinit();
    const decoded = decoding.decodeConverse(parsed.value) catch return .{ .failure = .invalid_response };
    return switch (decoded.output) {
        .invalid => .{ .usage = decoded.usage, .failure = .invalid_response },
        .text => |text| .{ .usage = decoded.usage, .payload = try a.dupe(u8, text) },
        .stopped => |reason| .{ .usage = decoded.usage, .failure = switch (reason) {
            .output_limit, .context_limit => .incomplete,
            .content_filtered => .refused,
            .unsupported_tool_request, .malformed_output => .invalid_response,
        } },
    };
}
