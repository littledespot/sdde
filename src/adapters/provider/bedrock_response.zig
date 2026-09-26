const std = @import("std");
const operation = @import("../../domain/llm_provider_operation.zig");
const binding = @import("../../domain/llm_provider_binding.zig");
const strict = @import("../../domain/strict_json.zig");
const transport = @import("bedrock_transport.zig");
const Invalid = error{InvalidResponse};

pub fn failure(id: operation.ProviderOperationId, cause: operation.ProviderFailureCause, delivery: operation.ProviderDeliveryDisposition) operation.ProviderFailure {
    const value = transportFailure(cause, delivery);
    return .{ .operation_id = id, .cause = value.cause, .delivery = value.delivery, .retry_class = value.retry_class };
}

fn transportFailure(cause: operation.ProviderFailureCause, delivery: operation.ProviderDeliveryDisposition) transport.Failure {
    return .{ .cause = cause, .delivery = delivery, .retry_class = switch (cause) {
        .throttled, .timeout, .service_unavailable, .transport_failed => .policy_eligible,
        .authentication_failed, .authorization_denied, .request_rejected, .model_unavailable, .response_invalid, .exact_token_count_unavailable => .never,
    } };
}

pub fn count(allocator: std.mem.Allocator, response: transport.Response, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, id: operation.ProviderOperationId) std.mem.Allocator.Error!operation.ProviderTokenCountObservation {
    if (try errorResponse(allocator, response, id)) |rejected| return .{ .failed = rejected };
    var parsed = strict.parse(allocator, response.received.body, .{ .maximum_depth = std.math.maxInt(usize) }, false, null) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => .{ .failed = failure(id, .exact_token_count_unavailable, .response_received) },
    };
    defer parsed.deinit();
    const tokens = decodeCount(parsed.value) catch return .{ .failed = failure(id, .exact_token_count_unavailable, .response_received) };
    return .{ .counted = .{ .operation_id = id, .binding_id = selected.bindingId(), .model_visible_input_id = request.model_visible_input_id, .input_tokens = tokens } };
}

fn decodeCount(value: std.json.Value) Invalid!u64 {
    try fields(value, &.{"inputTokens"});
    return integer(try field(value, "inputTokens"));
}

pub fn inference(allocator: std.mem.Allocator, response: transport.Response, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, id: operation.ProviderOperationId) std.mem.Allocator.Error!operation.ProviderInvocationObservation {
    if (try errorResponse(allocator, response, id)) |rejected| return .{ .failed = rejected };
    var parsed = strict.parse(allocator, response.received.body, .{ .maximum_depth = std.math.maxInt(usize) }, false, null) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => .{ .failed = failure(id, .response_invalid, .response_received) },
    };
    defer parsed.deinit();
    return decodeInference(allocator, parsed.value, selected, request, id) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => .{ .failed = failure(id, .response_invalid, .response_received) },
    };
}

pub const Inference = struct {
    usage: operation.ProviderUsage,
    latency_ms: ?u32,
    output: union(enum) { text: []const u8, stopped: operation.ProviderNonCandidateStopReason, invalid: operation.ProviderContentDiagnostic },
};

// Borrowed InvokeModel wire facts. Usage survives a rejected candidate; returned
// identities and reasoning never become workflow authority.
pub fn decodeInvoke(raw: std.json.Value) Invalid!Inference {
    try fields(raw, &.{ "id", "object", "created", "model", "choices", "usage", "service_tier", "system_fingerprint" });
    for ([_][]const u8{ "id", "model" }) |name| if (raw.object.get(name)) |v| {
        _ = try string(v);
    };
    if (raw.object.get("object")) |v| if (!std.mem.eql(u8, try string(v), "chat.completion")) return error.InvalidResponse;
    if (raw.object.get("created")) |v| {
        _ = try integer(v);
    }
    for ([_][]const u8{ "service_tier", "system_fingerprint" }) |name| if (raw.object.get(name)) |v| {
        if (v != .null) _ = try string(v);
    };
    const usage = try field(raw, "usage");
    try fields(usage, &.{ "prompt_tokens", "completion_tokens", "total_tokens", "prompt_tokens_details", "completion_tokens_details" });
    try usageDetails(usage, "prompt_tokens_details", &.{ "cached_tokens", "audio_tokens" });
    try usageDetails(usage, "completion_tokens_details", &.{ "reasoning_tokens", "audio_tokens", "accepted_prediction_tokens", "rejected_prediction_tokens" });
    const reported = operation.ProviderUsage.init(
        try integer(try field(usage, "prompt_tokens")),
        try integer(try field(usage, "completion_tokens")),
        try integer(try field(usage, "total_tokens")),
    ) orelse return error.InvalidResponse;
    return .{ .usage = reported, .latency_ms = null, .output = decodeOutput(raw) catch .{ .invalid = .invalid_content } };
}

fn usageDetails(usage: std.json.Value, name: []const u8, allowed: []const []const u8) Invalid!void {
    const detail = usage.object.get(name) orelse return;
    if (detail == .null) return;
    try fields(detail, allowed);
    for (detail.object.values()) |v| _ = try integer(v);
}

fn decodeOutput(raw: std.json.Value) Invalid!@FieldType(Inference, "output") {
    const choices = try field(raw, "choices");
    if (choices != .array or choices.array.items.len != 1) return error.InvalidResponse;
    const choice = choices.array.items[0];
    try fields(choice, &.{ "index", "message", "finish_reason", "logprobs" });
    if (try integer(try field(choice, "index")) != 0) return error.InvalidResponse;
    if (choice.object.get("logprobs")) |v| if (v != .null) return error.InvalidResponse;
    const stop = try string(try field(choice, "finish_reason"));
    if (!std.mem.eql(u8, stop, "stop")) {
        const reason: operation.ProviderNonCandidateStopReason = if (std.mem.eql(u8, stop, "length")) .output_limit else if (std.mem.eql(u8, stop, "tool_calls") or std.mem.eql(u8, stop, "function_call")) .unsupported_tool_request else if (std.mem.eql(u8, stop, "content_filter")) .content_filtered else return error.InvalidResponse;
        return .{ .stopped = reason };
    }
    const message = try field(choice, "message");
    try fields(message, &.{ "role", "content", "refusal", "tool_calls" });
    if (!std.mem.eql(u8, try string(try field(message, "role")), "assistant")) return error.InvalidResponse;
    if (message.object.get("refusal")) |v| if (v != .null) {
        _ = try string(v);
        return .{ .stopped = .content_filtered };
    };
    if (message.object.get("tool_calls")) |v| if (v != .null) {
        if (v != .array) return error.InvalidResponse;
        if (v.array.items.len != 0) return .{ .stopped = .unsupported_tool_request };
    };
    const content = message.object.get("content") orelse return .{ .invalid = .missing_final_text };
    if (content == .null) return .{ .invalid = .missing_final_text };
    const text = try string(content);
    // AWS documents one leading <reasoning> block for this API. Strip that
    // framing only, never scan for JSON or repair arbitrary provider text.
    const trimmed = std.mem.trimStart(u8, text, " \r\n\t");
    const answer = if (std.mem.startsWith(u8, trimmed, "<reasoning>")) answer: {
        const close = std.mem.indexOf(u8, trimmed, "</reasoning>") orelse return .{ .invalid = .missing_final_text };
        break :answer std.mem.trimStart(u8, trimmed[close + "</reasoning>".len ..], " \r\n\t");
    } else text;
    if (std.mem.trim(u8, answer, " \r\n\t").len == 0) return .{ .invalid = .missing_final_text };
    return .{ .text = answer };
}

fn decodeInference(allocator: std.mem.Allocator, raw: std.json.Value, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, id: operation.ProviderOperationId) (Invalid || std.mem.Allocator.Error)!operation.ProviderInvocationObservation {
    const decoded = try decodeInvoke(raw);
    return .{ .completed = .{ .operation_id = id, .raw_result = switch (decoded.output) {
        .invalid => |reason| .{ .rejected = .{
            .request_id = request.model_request_id,
            .binding_id = selected.bindingId(),
            .reason = reason,
            .usage = decoded.usage,
            .provider_latency_ms = decoded.latency_ms,
        } },
        .text => |text| .{ .complete = .{
            .request_id = request.model_request_id,
            .binding_id = selected.bindingId(),
            .content = operation.CompleteOwnedUtf8.init(allocator, text) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidResponse,
            .usage = decoded.usage,
            .provider_latency_ms = decoded.latency_ms,
        } },
        .stopped => |reason| .{ .stopped = .{
            .request_id = request.model_request_id,
            .binding_id = selected.bindingId(),
            .reason = reason,
            .usage = decoded.usage,
            .provider_latency_ms = decoded.latency_ms,
        } },
    } } };
}

fn errorResponse(allocator: std.mem.Allocator, response: transport.Response, id: operation.ProviderOperationId) std.mem.Allocator.Error!?operation.ProviderFailure {
    const rejected = try classifyResponse(allocator, response) orelse return null;
    return .{ .operation_id = id, .cause = rejected.cause, .retry_class = rejected.retry_class, .delivery = rejected.delivery, .transport = rejected.diagnostic };
}

pub fn classifyResponse(allocator: std.mem.Allocator, response: transport.Response) std.mem.Allocator.Error!?transport.Failure {
    const received = switch (response) {
        .failed => |value| return value,
        .received => |value| value,
    };
    if (received.status == 200 and received.exception == null) return null;
    const invalid = transportFailure(.response_invalid, .response_received);
    var parsed = strict.parse(allocator, received.body, .{ .maximum_depth = std.math.maxInt(usize) }, false, null) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else invalid;
    defer parsed.deinit();
    const cause = decodeError(parsed.value, received.status, received.exception) catch return invalid;
    return transportFailure(cause, .response_received);
}

fn decodeError(raw: std.json.Value, status: u16, header: ?[]const u8) Invalid!operation.ProviderFailureCause {
    try fields(raw, &.{ "message", "Message", "__type", "code", "originalStatusCode", "resourceName" });
    if (raw.object.contains("message") and raw.object.contains("Message")) return error.InvalidResponse;
    if (raw.object.get("message")) |message| _ = try string(message);
    if (raw.object.get("Message")) |message| _ = try string(message);
    if (raw.object.get("resourceName")) |name| _ = try string(name);
    var resolved: ?[]const u8 = if (header) |value| exceptionName(value) else null;
    for ([_][]const u8{ "__type", "code" }) |key_name| {
        if (raw.object.get(key_name)) |value| {
            const name = exceptionName(try string(value));
            if (resolved) |previous| if (!std.mem.eql(u8, name, previous)) return error.InvalidResponse;
            resolved = name;
        }
    }
    const discriminator = resolved orelse return error.InvalidResponse;
    if (std.mem.eql(u8, discriminator, "ModelErrorException") and status == 424) {
        return switch (try integer(try field(raw, "originalStatusCode"))) {
            408, 429, 500, 503 => .service_unavailable,
            400, 409, 422 => .request_rejected,
            401 => .authentication_failed,
            403 => .authorization_denied,
            404 => .model_unavailable,
            else => error.InvalidResponse,
        };
    }
    if (raw.object.contains("originalStatusCode")) return error.InvalidResponse;
    const Mapping = struct { name: []const u8, status: u16, cause: operation.ProviderFailureCause };
    const mappings = [_]Mapping{
        .{ .name = "UnrecognizedClientException", .status = 403, .cause = .authentication_failed },
        .{ .name = "InvalidSignatureException", .status = 403, .cause = .authentication_failed },
        .{ .name = "ExpiredTokenException", .status = 403, .cause = .authentication_failed },
        .{ .name = "AccessDeniedException", .status = 403, .cause = .authorization_denied },
        .{ .name = "ValidationException", .status = 400, .cause = .request_rejected },
        .{ .name = "ResourceNotFoundException", .status = 404, .cause = .model_unavailable },
        .{ .name = "ModelNotReadyException", .status = 429, .cause = .service_unavailable },
        .{ .name = "ThrottlingException", .status = 429, .cause = .throttled },
        .{ .name = "ModelTimeoutException", .status = 408, .cause = .timeout },
        .{ .name = "InternalServerException", .status = 500, .cause = .service_unavailable },
        .{ .name = "ServiceUnavailableException", .status = 503, .cause = .service_unavailable },
    };
    for (mappings) |mapping| if (status == mapping.status and std.mem.eql(u8, discriminator, mapping.name)) return mapping.cause;
    return error.InvalidResponse;
}

fn fields(raw: std.json.Value, allowed: []const []const u8) Invalid!void {
    if (raw != .object) return error.InvalidResponse;
    for (raw.object.keys()) |key| {
        for (allowed) |name| if (std.mem.eql(u8, key, name)) break else {} else return error.InvalidResponse;
    }
}

// AWS restJson1 defines these decorations as part of error serialization.
// Only the resulting recognized shape name and matching status classify it.
fn exceptionName(raw: []const u8) []const u8 {
    const value = raw[0 .. std.mem.indexOfScalar(u8, raw, ':') orelse raw.len];
    return if (std.mem.indexOfScalar(u8, value, '#')) |index| value[index + 1 ..] else value;
}
fn field(raw: std.json.Value, name: []const u8) Invalid!std.json.Value {
    if (raw != .object) return error.InvalidResponse;
    return raw.object.get(name) orelse error.InvalidResponse;
}
fn string(raw: std.json.Value) Invalid![]const u8 {
    return if (raw == .string) raw.string else error.InvalidResponse;
}
fn integer(raw: std.json.Value) Invalid!u64 {
    if (raw != .number_string or raw.number_string.len == 0) return error.InvalidResponse;
    for (raw.number_string) |byte| if (byte < '0' or byte > '9') return error.InvalidResponse;
    return std.fmt.parseInt(u64, raw.number_string, 10) catch error.InvalidResponse;
}
