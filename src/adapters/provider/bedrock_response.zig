const std = @import("std");
const operation = @import("../../domain/llm_provider_operation.zig");
const binding = @import("../../domain/llm_provider_binding.zig");
const strict = @import("../../domain/strict_json.zig");
const transport = @import("bedrock_transport.zig");
const Invalid = error{InvalidResponse};

pub fn failure(id: operation.ProviderOperationId, cause: operation.ProviderFailureCause, delivery: operation.ProviderDeliveryDisposition) operation.ProviderFailure {
    return .{ .operation_id = id, .cause = cause, .delivery = delivery, .retry_class = switch (cause) {
        .throttled, .timeout, .service_unavailable, .transport_failed => .policy_eligible,
        .authentication_failed, .authorization_denied, .request_rejected, .model_unavailable, .response_invalid, .exact_token_count_unavailable => .never,
    } };
}

pub fn count(allocator: std.mem.Allocator, response: transport.Response, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, id: operation.ProviderOperationId) std.mem.Allocator.Error!operation.ProviderTokenCountObservation {
    if (try errorResponse(allocator, response, id)) |rejected| return .{ .failed = rejected };
    var parsed = strict.parse(allocator, response.received.body, .{ .maximum_depth = std.math.maxInt(usize) }, false) catch |err| return switch (err) {
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
    var parsed = strict.parse(allocator, response.received.body, .{ .maximum_depth = std.math.maxInt(usize) }, false) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => .{ .failed = failure(id, .response_invalid, .response_received) },
    };
    defer parsed.deinit();
    return decodeInference(allocator, parsed.value, selected, request, id) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => .{ .failed = failure(id, .response_invalid, .response_received) },
    };
}

fn decodeInference(allocator: std.mem.Allocator, raw: std.json.Value, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, id: operation.ProviderOperationId) (Invalid || std.mem.Allocator.Error)!operation.ProviderInvocationObservation {
    try fields(raw, &.{ "output", "stopReason", "usage", "metrics" });
    const stop = try string(try field(raw, "stopReason"));
    const usage = try field(raw, "usage");
    try fields(usage, &.{ "inputTokens", "outputTokens", "totalTokens" });
    const reported = operation.ProviderUsage.init(
        try integer(try field(usage, "inputTokens")),
        try integer(try field(usage, "outputTokens")),
        try integer(try field(usage, "totalTokens")),
    ) orelse return error.InvalidResponse;
    var latency: ?u32 = null;
    if (raw.object.get("metrics")) |metrics| {
        try fields(metrics, &.{"latencyMs"});
        latency = std.math.cast(u32, try integer(try field(metrics, "latencyMs"))) orelse return error.InvalidResponse;
    }
    if (std.mem.eql(u8, stop, "end_turn")) {
        const output = try field(raw, "output");
        try fields(output, &.{"message"});
        const message = try field(output, "message");
        try fields(message, &.{ "role", "content" });
        if (!std.mem.eql(u8, try string(try field(message, "role")), "assistant")) return error.InvalidResponse;
        const content = try field(message, "content");
        if (content != .array or content.array.items.len != 1) return error.InvalidResponse;
        try fields(content.array.items[0], &.{"text"});
        const text = try string(try field(content.array.items[0], "text"));
        const owned = operation.CompleteOwnedUtf8.init(allocator, text) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidResponse;
        return .{ .completed = .{ .operation_id = id, .raw_result = .{ .complete = .{
            .request_id = request.model_request_id,
            .binding_id = selected.bindingId(),
            .content = owned,
            .usage = reported,
            .provider_latency_ms = latency,
        } } } };
    }
    const reason: operation.ProviderNonCandidateStopReason = if (std.mem.eql(u8, stop, "max_tokens")) .output_limit else if (std.mem.eql(u8, stop, "tool_use")) .unsupported_tool_request else if (std.mem.eql(u8, stop, "guardrail_intervened") or std.mem.eql(u8, stop, "content_filtered")) .content_filtered else if (std.mem.eql(u8, stop, "malformed_model_output") or std.mem.eql(u8, stop, "malformed_tool_use")) .malformed_output else if (std.mem.eql(u8, stop, "model_context_window_exceeded")) .context_limit else return error.InvalidResponse;
    return .{ .completed = .{ .operation_id = id, .raw_result = .{ .stopped = .{
        .request_id = request.model_request_id,
        .binding_id = selected.bindingId(),
        .reason = reason,
        .usage = reported,
        .provider_latency_ms = latency,
    } } } };
}

fn errorResponse(allocator: std.mem.Allocator, response: transport.Response, id: operation.ProviderOperationId) std.mem.Allocator.Error!?operation.ProviderFailure {
    const received = switch (response) {
        .failed => |value| return .{ .operation_id = id, .cause = value.cause, .retry_class = value.retry_class, .delivery = value.delivery },
        .received => |value| value,
    };
    if (received.status == 200 and received.exception == null) return null;
    const invalid = failure(id, .response_invalid, .response_received);
    var parsed = strict.parse(allocator, received.body, .{ .maximum_depth = std.math.maxInt(usize) }, false) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else invalid;
    defer parsed.deinit();
    const cause = decodeError(parsed.value, received.status, received.exception) catch return invalid;
    return failure(id, cause, .response_received);
}

fn decodeError(raw: std.json.Value, status: u16, header: ?[]const u8) Invalid!operation.ProviderFailureCause {
    try fields(raw, &.{ "message", "__type", "code", "originalStatusCode", "resourceName" });
    if (raw.object.get("message")) |message| _ = try string(message);
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
