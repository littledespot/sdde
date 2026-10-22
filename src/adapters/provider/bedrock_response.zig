//! Bedrock Converse and CountTokens response contract: closed envelope, usage
//! counters, stop mapping and AWS error table. Shared readers and assembly
//! own everything provider-neutral.
const std = @import("std");
const operation = @import("../../domain/llm_provider_operation.zig");
const binding = @import("../../domain/llm_provider_binding.zig");
const transport = @import("model_http_transport.zig");
const provider_reasoning = @import("../../domain/provider_reasoning.zig");
const support = @import("provider_response_support.zig");
const assembly = @import("provider_response_assembly.zig");
const Invalid = support.Invalid;
const fields = support.fields;
const diagnosedFields = support.diagnosedFields;
const field = support.field;
const string = support.string;
const integer = support.integer;
const enumeration = support.enumeration;

pub fn count(allocator: std.mem.Allocator, response: transport.Response, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, id: operation.ProviderOperationId) std.mem.Allocator.Error!operation.ProviderTokenCountObservation {
    if (try classifyResponse(allocator, response)) |rejected| return .{ .failed = assembly.rejected(id, rejected) };
    var parsed = support.parse(allocator, response.received.body) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => .{ .failed = assembly.failure(id, .exact_token_count_unavailable, .response_received) },
    };
    defer parsed.deinit();
    const tokens = decodeCount(parsed.value) catch return .{ .failed = assembly.failure(id, .exact_token_count_unavailable, .response_received) };
    return .{ .counted = .{ .operation_id = id, .binding_id = selected.bindingId(), .model_visible_input_id = request.model_visible_input_id, .input_tokens = tokens } };
}

fn decodeCount(value: std.json.Value) Invalid!u64 {
    try fields(value, &.{"inputTokens"});
    return integer(try field(value, "inputTokens"));
}

pub fn inference(allocator: std.mem.Allocator, response: transport.Response, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, id: operation.ProviderOperationId) std.mem.Allocator.Error!operation.ProviderInvocationObservation {
    return assembly.inference(allocator, response, selected, request, id, classifyResponse, decode);
}

fn decode(allocator: std.mem.Allocator, raw: std.json.Value, _: *const binding.ValidatedProviderModelBinding, diagnostic: ?*?support.DecodeDiagnostic) (Invalid || std.mem.Allocator.Error)!assembly.Inference {
    return decodeConverse(allocator, raw, diagnostic);
}

// Converse wire facts. Usage survives a rejected candidate; provider reasoning
// never becomes authored content or workflow authority. Text owns its exact join.
pub fn decodeConverse(allocator: std.mem.Allocator, raw: std.json.Value, diagnostic: ?*?support.DecodeDiagnostic) (Invalid || std.mem.Allocator.Error)!assembly.Inference {
    if (diagnostic) |out| out.* = null;
    return decodeConverseValue(allocator, raw, diagnostic) catch |err| {
        if (err == error.InvalidResponse) try support.DecodeDiagnostic.fallback(allocator, diagnostic);
        return err;
    };
}

fn decodeConverseValue(allocator: std.mem.Allocator, raw: std.json.Value, diagnostic: ?*?support.DecodeDiagnostic) (Invalid || std.mem.Allocator.Error)!assembly.Inference {
    try diagnosedFields(allocator, raw, &.{ "output", "stopReason", "usage", "metrics", "serviceTier", "performanceConfig", "additionalModelResponseFields" }, &.{}, diagnostic);
    var latency_ms: ?u32 = null;
    if (raw.object.get("metrics")) |metrics| {
        try diagnosedFields(allocator, metrics, &.{"latencyMs"}, &.{.{ .property = "metrics" }}, diagnostic);
        latency_ms = std.math.cast(u32, try integer(try field(metrics, "latencyMs"))) orelse return error.InvalidResponse;
    }
    if (raw.object.get("serviceTier")) |tier| {
        try diagnosedFields(allocator, tier, &.{"type"}, &.{.{ .property = "serviceTier" }}, diagnostic);
        try enumeration(try field(tier, "type"), &.{ "default", "priority", "flex", "reserved" });
    }
    if (raw.object.get("performanceConfig")) |performance| {
        try diagnosedFields(allocator, performance, &.{"latency"}, &.{.{ .property = "performanceConfig" }}, diagnostic);
        try enumeration(try field(performance, "latency"), &.{ "standard", "optimized" });
    }
    if (raw.object.get("additionalModelResponseFields")) |extra| {
        if (extra != .null) try diagnosedFields(allocator, extra, &.{}, &.{.{ .property = "additionalModelResponseFields" }}, diagnostic);
    }
    const usage = try field(raw, "usage");
    try diagnosedFields(allocator, usage, &.{ "inputTokens", "outputTokens", "totalTokens", "cacheReadInputTokens", "cacheWriteInputTokens", "cacheDetails", "serverToolUsage" }, &.{.{ .property = "usage" }}, diagnostic);
    if (usage.object.get("serverToolUsage")) |tools| {
        // Native Converse receipt 2026-10-15T20:29:20Z supplies this empty
        // metadata object. No nonempty tool-usage contract is registered.
        try diagnosedFields(allocator, tools, &.{}, &.{ .{ .property = "usage" }, .{ .property = "serverToolUsage" } }, diagnostic);
    }
    const cache_read = if (usage.object.get("cacheReadInputTokens")) |v| try integer(v) else 0;
    const cache_write = if (usage.object.get("cacheWriteInputTokens")) |v| try integer(v) else 0;
    if (usage.object.get("cacheDetails")) |details| {
        if (details != .array) return error.InvalidResponse;
        var described: u64 = 0;
        var previous: ?[]const u8 = null;
        for (details.array.items, 0..) |detail, index| {
            try diagnosedFields(allocator, detail, &.{ "inputTokens", "ttl" }, &.{ .{ .property = "usage" }, .{ .property = "cacheDetails" }, .{ .index = index } }, diagnostic);
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
    var accumulated: assembly.Accumulator = .init(allocator);
    defer accumulated.deinit();
    const output: assembly.Output = decodeOutput(raw, &accumulated) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidResponse => .{ .invalid = .invalid_content },
    };
    errdefer if (output == .text) allocator.free(output.text);
    return .{ .usage = reported, .latency_ms = latency_ms, .output = output, .reasoning = try accumulated.takeReasoning() };
}

fn decodeOutput(raw: std.json.Value, accumulated: *assembly.Accumulator) (Invalid || std.mem.Allocator.Error)!assembly.Output {
    const message = decodeMessage(raw, accumulated) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidResponse => @as(?assembly.Output, .{ .invalid = .invalid_content }),
    };
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
    if (stopped) |reason| return .{ .stopped = reason };
    if (message) |value| return value;
    return accumulated.output(null);
}

/// Accumulates the message's text and reasoning, or names why it has none.
fn decodeMessage(raw: std.json.Value, accumulated: *assembly.Accumulator) (Invalid || std.mem.Allocator.Error)!?assembly.Output {
    const output = raw.object.get("output") orelse return .{ .invalid = .missing_final_text };
    try fields(output, &.{"message"});
    const message = try field(output, "message");
    try fields(message, &.{ "role", "content" });
    if (!std.mem.eql(u8, try string(try field(message, "role")), "assistant")) return error.InvalidResponse;
    const content = message.object.get("content") orelse return .{ .invalid = .missing_final_text };
    if (content != .array) return error.InvalidResponse;
    for (content.array.items) |block| {
        fields(block, &.{ "text", "reasoningContent" }) catch {
            accumulated.invalid_content = true;
            continue;
        };
        if (block.object.count() != 1) {
            accumulated.invalid_content = true;
            continue;
        }
        if (block.object.get("text")) |part| {
            const value = string(part) catch {
                accumulated.invalid_content = true;
                continue;
            };
            try accumulated.appendText(value);
        } else {
            const owned = reasoning(accumulated.allocator, try field(block, "reasoningContent")) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidResponse => {
                    accumulated.invalid_content = true;
                    continue;
                },
            };
            try accumulated.appendReasoning(owned);
        }
    }
    return null;
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

pub fn classifyResponse(allocator: std.mem.Allocator, response: transport.Response) std.mem.Allocator.Error!?transport.Failure {
    const received = switch (response) {
        .failed => |value| return value,
        .received => |value| value,
    };
    if (received.status == 200 and received.exception == null) return null;
    return try assembly.classifyErrorBody(allocator, received, decodeError);
}

fn decodeError(raw: std.json.Value, received: assembly.Received) Invalid!operation.ProviderFailureCause {
    const status = received.status;
    const header = received.exception;
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

// AWS restJson1 defines these decorations as part of error serialization.
// Only the resulting recognized shape name and matching status classify it.
fn exceptionName(raw: []const u8) []const u8 {
    const value = raw[0 .. std.mem.indexOfScalar(u8, raw, ':') orelse raw.len];
    return if (std.mem.indexOfScalar(u8, value, '#')) |index| value[index + 1 ..] else value;
}
