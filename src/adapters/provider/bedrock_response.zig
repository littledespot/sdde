const std = @import("std");
const operation = @import("../../domain/llm_provider_operation.zig");
const binding = @import("../../domain/llm_provider_binding.zig");
const strict = @import("../../domain/strict_json.zig");
const transport = @import("bedrock_transport.zig");
const provider_reasoning = @import("../../domain/provider_reasoning.zig");
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
    reasoning: []const provider_reasoning.Block,

    pub fn deinit(self: *Inference, allocator: std.mem.Allocator) void {
        if (self.output == .text) allocator.free(self.output.text);
        provider_reasoning.deinit(allocator, self.reasoning);
        self.* = undefined;
    }
};

// Converse wire facts. Usage survives a rejected candidate; provider reasoning
// never becomes authored content or workflow authority. Text owns its exact join.
pub fn decodeConverse(allocator: std.mem.Allocator, raw: std.json.Value) (Invalid || std.mem.Allocator.Error)!Inference {
    try fields(raw, &.{ "output", "stopReason", "usage", "metrics", "serviceTier", "performanceConfig", "additionalModelResponseFields" });
    var latency_ms: ?u32 = null;
    if (raw.object.get("metrics")) |metrics| {
        try fields(metrics, &.{"latencyMs"});
        latency_ms = std.math.cast(u32, try integer(try field(metrics, "latencyMs"))) orelse return error.InvalidResponse;
    }
    if (raw.object.get("serviceTier")) |tier| {
        try fields(tier, &.{"type"});
        try enumeration(try field(tier, "type"), &.{ "default", "priority", "flex", "reserved" });
    }
    if (raw.object.get("performanceConfig")) |performance| {
        try fields(performance, &.{"latency"});
        try enumeration(try field(performance, "latency"), &.{ "standard", "optimized" });
    }
    if (raw.object.get("additionalModelResponseFields")) |extra| {
        if (extra != .null) try fields(extra, &.{});
    }
    const usage = try field(raw, "usage");
    try fields(usage, &.{ "inputTokens", "outputTokens", "totalTokens", "cacheReadInputTokens", "cacheWriteInputTokens", "cacheDetails" });
    const cache_read = if (usage.object.get("cacheReadInputTokens")) |v| try integer(v) else 0;
    const cache_write = if (usage.object.get("cacheWriteInputTokens")) |v| try integer(v) else 0;
    if (usage.object.get("cacheDetails")) |details| {
        if (details != .array) return error.InvalidResponse;
        var described: u64 = 0;
        var previous: ?[]const u8 = null;
        for (details.array.items) |detail| {
            try fields(detail, &.{ "inputTokens", "ttl" });
            const ttl = try string(try field(detail, "ttl"));
            try enumeration(try field(detail, "ttl"), &.{ "1h", "5m" });
            if (previous) |prior| if (std.mem.eql(u8, prior, ttl) or std.mem.eql(u8, prior, "5m")) return error.InvalidResponse;
            previous = ttl;
            described = std.math.add(u64, described, try integer(try field(detail, "inputTokens"))) catch return error.InvalidResponse;
        }
        if (described != cache_write) return error.InvalidResponse;
    }
    // AWS reports uncached input separately from cache reads and writes.
    const uncached_and_read = std.math.add(u64, try integer(try field(usage, "inputTokens")), cache_read) catch return error.InvalidResponse;
    const inclusive_input = std.math.add(u64, uncached_and_read, cache_write) catch return error.InvalidResponse;
    const reported = operation.ProviderUsage.init(
        inclusive_input,
        try integer(try field(usage, "outputTokens")),
        try integer(try field(usage, "totalTokens")),
    ) orelse return error.InvalidResponse;
    var reasoning_blocks: std.ArrayList(provider_reasoning.Block) = .empty;
    defer reasoning_blocks.deinit(allocator);
    errdefer for (reasoning_blocks.items) |block| block.deinit(allocator);
    const output: @FieldType(Inference, "output") = decodeOutput(allocator, raw, &reasoning_blocks) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidResponse => .{ .invalid = .invalid_content },
    };
    errdefer if (output == .text) allocator.free(output.text);
    return .{ .usage = reported, .latency_ms = latency_ms, .output = output, .reasoning = try reasoning_blocks.toOwnedSlice(allocator) };
}

fn decodeOutput(allocator: std.mem.Allocator, raw: std.json.Value, reasoning_blocks: *std.ArrayList(provider_reasoning.Block)) (Invalid || std.mem.Allocator.Error)!@FieldType(Inference, "output") {
    const decoded = decodeMessage(allocator, raw, reasoning_blocks) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidResponse => @as(@FieldType(Inference, "output"), .{ .invalid = .invalid_content }),
    };
    errdefer if (decoded == .text) allocator.free(decoded.text);
    const stop = try string(try field(raw, "stopReason"));
    const Stop = enum { end_turn, tool_use, max_tokens, stop_sequence, guardrail_intervened, content_filtered, malformed_model_output, malformed_tool_use, model_context_window_exceeded };
    const selected = std.meta.stringToEnum(Stop, stop) orelse return error.InvalidResponse;
    const stopped: ?operation.ProviderNonCandidateStopReason = switch (selected) {
        .end_turn => null,
        .tool_use, .malformed_tool_use => .unsupported_tool_request,
        .max_tokens => .output_limit,
        .guardrail_intervened, .content_filtered => .content_filtered,
        .malformed_model_output, .stop_sequence => .malformed_output,
        .model_context_window_exceeded => .context_limit,
    };
    if (stopped) |reason| {
        if (decoded == .text) allocator.free(decoded.text);
        return .{ .stopped = reason };
    }
    return decoded;
}

fn decodeMessage(allocator: std.mem.Allocator, raw: std.json.Value, reasoning_blocks: *std.ArrayList(provider_reasoning.Block)) (Invalid || std.mem.Allocator.Error)!@FieldType(Inference, "output") {
    const output = raw.object.get("output") orelse return .{ .invalid = .missing_final_text };
    try fields(output, &.{"message"});
    const message = try field(output, "message");
    try fields(message, &.{ "role", "content" });
    if (!std.mem.eql(u8, try string(try field(message, "role")), "assistant")) return error.InvalidResponse;
    const content = message.object.get("content") orelse return .{ .invalid = .missing_final_text };
    if (content != .array) return error.InvalidResponse;
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    var invalid_content = false;
    for (content.array.items) |block| {
        fields(block, &.{ "text", "reasoningContent" }) catch {
            invalid_content = true;
            continue;
        };
        if (block.object.count() != 1) {
            invalid_content = true;
            continue;
        }
        if (block.object.get("text")) |part| {
            const value = string(part) catch {
                invalid_content = true;
                continue;
            };
            text.writer.writeAll(value) catch return error.OutOfMemory;
        } else {
            const owned = reasoning(allocator, try field(block, "reasoningContent")) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidResponse => {
                    invalid_content = true;
                    continue;
                },
            };
            errdefer owned.deinit(allocator);
            try reasoning_blocks.append(allocator, owned);
        }
    }
    if (invalid_content) return .{ .invalid = .invalid_content };
    if (std.mem.trim(u8, text.written(), " \r\n\t").len == 0) return .{ .invalid = .missing_final_text };
    return .{ .text = try text.toOwnedSlice() };
}

fn reasoning(allocator: std.mem.Allocator, raw: std.json.Value) (Invalid || std.mem.Allocator.Error)!provider_reasoning.Block {
    try fields(raw, &.{ "reasoningText", "redactedContent" });
    if (raw.object.count() != 1) return error.InvalidResponse;
    if (raw.object.get("reasoningText")) |text| {
        try fields(text, &.{ "text", "signature" });
        return (provider_reasoning.Block{ .text = .{
            .text = try string(try field(text, "text")),
            .signature = if (text.object.get("signature")) |signature| try string(signature) else null,
        } }).clone(allocator);
    } else {
        const encoded = try string(try field(raw, "redactedContent"));
        const size = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return error.InvalidResponse;
        const bytes = try allocator.alloc(u8, size);
        defer allocator.free(bytes);
        std.base64.standard.Decoder.decode(bytes, encoded) catch return error.InvalidResponse;
        return (provider_reasoning.Block{ .redacted = .{ .base64 = encoded } }).clone(allocator);
    }
}

fn enumeration(raw: std.json.Value, allowed: []const []const u8) Invalid!void {
    const value = try string(raw);
    for (allowed) |name| if (std.mem.eql(u8, value, name)) return;
    return error.InvalidResponse;
}

fn decodeInference(allocator: std.mem.Allocator, raw: std.json.Value, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, id: operation.ProviderOperationId) (Invalid || std.mem.Allocator.Error)!operation.ProviderInvocationObservation {
    var decoded = try decodeConverse(allocator, raw);
    defer decoded.deinit(allocator);
    var result: operation.RawProviderModelResult = switch (decoded.output) {
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
    };
    if (decoded.reasoning.len != 0) switch (result) {
        inline .complete, .stopped, .rejected => |*value| value.reasoning = provider_reasoning.Owned.take(allocator, &decoded.reasoning),
    };
    return .{ .completed = .{ .operation_id = id, .raw_result = result } };
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
