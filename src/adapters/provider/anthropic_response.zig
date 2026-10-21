//! Anthropic Messages API response contract (ADR 0028, F0009 wire manifest of
//! 21 October 2026): closed envelope, usage counters, stop mapping and error
//! table. Shared readers and assembly own everything provider-neutral.
const std = @import("std");
const operation = @import("../../domain/llm_provider_operation.zig");
const binding = @import("../../domain/llm_provider_binding.zig");
const transport = @import("model_http_transport.zig");
const provider_reasoning = @import("../../domain/provider_reasoning.zig");
const support = @import("provider_response_support.zig");
const assembly = @import("provider_response_assembly.zig");
const Invalid = support.Invalid;
const field = support.field;
const string = support.string;
const integer = support.integer;

/// Every documented field is present on a non-streaming response; nullable
/// ones are present as null. No other field is admitted.
const message_fields = [_][]const u8{ "id", "type", "role", "model", "content", "stop_reason", "stop_sequence", "stop_details", "usage", "container", "diagnostics" };
const usage_fields = [_][]const u8{ "input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "cache_creation", "output_tokens_details", "server_tool_use", "service_tier", "inference_geo", "speed" };

pub fn inference(allocator: std.mem.Allocator, response: transport.Response, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, id: operation.ProviderOperationId) std.mem.Allocator.Error!operation.ProviderInvocationObservation {
    return assembly.inference(allocator, response, selected, request, id, classifyResponse, decode);
}

fn decode(allocator: std.mem.Allocator, raw: std.json.Value, selected: *const binding.ValidatedProviderModelBinding, diagnostic: ?*?support.DecodeDiagnostic) (Invalid || std.mem.Allocator.Error)!assembly.Inference {
    return decodeMessages(allocator, raw, selected.registry_entry.model.bytes, diagnostic);
}

/// Decode one Messages response for the model the binding selected. Usage
/// survives a rejected or stopped candidate once the envelope is valid.
pub fn decodeMessages(allocator: std.mem.Allocator, raw: std.json.Value, model: []const u8, diagnostic: ?*?support.DecodeDiagnostic) (Invalid || std.mem.Allocator.Error)!assembly.Inference {
    if (diagnostic) |out| out.* = null;
    return decodeValue(allocator, raw, model, diagnostic) catch |err| {
        if (err == error.InvalidResponse) try support.DecodeDiagnostic.fallback(allocator, diagnostic);
        return err;
    };
}

fn decodeValue(allocator: std.mem.Allocator, raw: std.json.Value, model: []const u8, diagnostic: ?*?support.DecodeDiagnostic) (Invalid || std.mem.Allocator.Error)!assembly.Inference {
    try support.diagnosedFields(allocator, raw, &message_fields, &.{}, diagnostic);
    try support.required(raw, &message_fields);
    if ((try string(try field(raw, "id"))).len == 0) return error.InvalidResponse;
    if (!std.mem.eql(u8, try string(try field(raw, "type")), "message")) return error.InvalidResponse;
    if (!std.mem.eql(u8, try string(try field(raw, "role")), "assistant")) return error.InvalidResponse;
    // The returned model must be the selected one; it never replaces the
    // runner's own request association.
    if (!std.mem.eql(u8, try string(try field(raw, "model")), model)) return error.InvalidResponse;
    // No container tool and no cache diagnostics were requested.
    if (try field(raw, "container") != .null or try field(raw, "diagnostics") != .null) return error.InvalidResponse;
    const usage = try decodeUsage(allocator, try field(raw, "usage"), diagnostic);
    var accumulated: assembly.Accumulator = .init(allocator);
    defer accumulated.deinit();
    const output: assembly.Output = decodeOutput(raw, &accumulated) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidResponse => .{ .invalid = .invalid_content },
    };
    errdefer if (output == .text) allocator.free(output.text);
    return .{ .usage = usage, .latency_ms = null, .output = output, .reasoning = try accumulated.takeReasoning() };
}

fn decodeUsage(allocator: std.mem.Allocator, usage: std.json.Value, diagnostic: ?*?support.DecodeDiagnostic) (Invalid || std.mem.Allocator.Error)!operation.ProviderUsage {
    try support.diagnosedFields(allocator, usage, &usage_fields, &.{.{ .property = "usage" }}, diagnostic);
    try support.required(usage, &usage_fields);
    const output_tokens = try integer(try field(usage, "output_tokens"));
    const cache_write = try support.optionalInteger(try field(usage, "cache_creation_input_tokens"));
    const cache_read = try support.optionalInteger(try field(usage, "cache_read_input_tokens"));
    const breakdown = try field(usage, "cache_creation");
    if (breakdown != .null) {
        try support.diagnosedFields(allocator, breakdown, &.{ "ephemeral_1h_input_tokens", "ephemeral_5m_input_tokens" }, &.{ .{ .property = "usage" }, .{ .property = "cache_creation" } }, diagnostic);
        try support.required(breakdown, &.{ "ephemeral_1h_input_tokens", "ephemeral_5m_input_tokens" });
        const described = std.math.add(u64, try integer(try field(breakdown, "ephemeral_1h_input_tokens")), try integer(try field(breakdown, "ephemeral_5m_input_tokens"))) catch return error.InvalidResponse;
        // The breakdown describes the cache-write counter; it is never added again.
        if (described != cache_write) return error.InvalidResponse;
    }
    const details = try field(usage, "output_tokens_details");
    if (details != .null) {
        try support.diagnosedFields(allocator, details, &.{"thinking_tokens"}, &.{ .{ .property = "usage" }, .{ .property = "output_tokens_details" } }, diagnostic);
        // Thinking is already inside output_tokens: checked, never added.
        if (try integer(try field(details, "thinking_tokens")) > output_tokens) return error.InvalidResponse;
    }
    const tools = try field(usage, "server_tool_use");
    if (tools != .null) {
        try support.diagnosedFields(allocator, tools, &.{ "web_fetch_requests", "web_search_requests" }, &.{ .{ .property = "usage" }, .{ .property = "server_tool_use" } }, diagnostic);
        // No server tool was offered, so only zero counts are consistent.
        if (try integer(try field(tools, "web_fetch_requests")) != 0 or try integer(try field(tools, "web_search_requests")) != 0) return error.InvalidResponse;
    }
    try nullableEnumeration(try field(usage, "service_tier"), &.{ "standard", "priority", "batch" });
    try nullableEnumeration(try field(usage, "speed"), &.{ "standard", "fast" });
    const geography = try field(usage, "inference_geo");
    if (geography != .null) _ = try string(geography);
    const uncached_and_read = std.math.add(u64, try integer(try field(usage, "input_tokens")), cache_read) catch return error.InvalidResponse;
    const inclusive_input = std.math.add(u64, uncached_and_read, cache_write) catch return error.InvalidResponse;
    const total = std.math.add(u64, inclusive_input, output_tokens) catch return error.InvalidResponse;
    return operation.ProviderUsage.init(inclusive_input, output_tokens, total) orelse error.InvalidResponse;
}

fn nullableEnumeration(raw: std.json.Value, allowed: []const []const u8) Invalid!void {
    if (raw != .null) try support.enumeration(raw, allowed);
}

fn decodeOutput(raw: std.json.Value, accumulated: *assembly.Accumulator) (Invalid || std.mem.Allocator.Error)!assembly.Output {
    const content = try field(raw, "content");
    if (content != .array) return error.InvalidResponse;
    for (content.array.items) |block| try decodeBlock(block, accumulated);
    const Stop = enum { end_turn, max_tokens, stop_sequence, tool_use, pause_turn, refusal, model_context_window_exceeded };
    const stop = std.meta.stringToEnum(Stop, try string(try field(raw, "stop_reason"))) orelse return error.InvalidResponse;
    const details = try field(raw, "stop_details");
    if (stop == .refusal) {
        if (details != .null) try refusalDetails(details);
    } else if (details != .null) return error.InvalidResponse;
    const sequence = try field(raw, "stop_sequence");
    if ((sequence != .null) != (stop == .stop_sequence)) return error.InvalidResponse;
    if (sequence != .null) _ = try string(sequence);
    const stopped: ?operation.ProviderNonCandidateStopReason = switch (stop) {
        .end_turn => null,
        .max_tokens => .output_limit,
        .model_context_window_exceeded => .context_limit,
        // A refusal is the existing content-filter stop (user decision, ADR 0028).
        .refusal => .content_filtered,
        .tool_use, .pause_turn => .unsupported_tool_request,
        // The engine sends no stop sequences.
        .stop_sequence => .malformed_output,
    };
    return accumulated.output(stopped);
}

fn decodeBlock(block: std.json.Value, accumulated: *assembly.Accumulator) std.mem.Allocator.Error!void {
    const Kind = enum { text, thinking, redacted_thinking };
    const kind = if (block == .object) if (block.object.get("type")) |value| if (value == .string) std.meta.stringToEnum(Kind, value.string) else null else null else null;
    switch (kind orelse {
        // Tool, server-tool and container blocks cannot answer a tool-free request.
        accumulated.invalid_content = true;
        return;
    }) {
        .text => {
            support.fields(block, &.{ "type", "text", "citations" }) catch return markInvalid(accumulated);
            const text = string(block.object.get("text") orelse return markInvalid(accumulated)) catch return markInvalid(accumulated);
            // No citation source is ever sent.
            if ((block.object.get("citations") orelse return markInvalid(accumulated)) != .null) return markInvalid(accumulated);
            try accumulated.appendText(text);
        },
        .thinking => {
            support.fields(block, &.{ "type", "thinking", "signature" }) catch return markInvalid(accumulated);
            const thinking = string(block.object.get("thinking") orelse return markInvalid(accumulated)) catch return markInvalid(accumulated);
            const signature = string(block.object.get("signature") orelse return markInvalid(accumulated)) catch return markInvalid(accumulated);
            try accumulated.appendReasoning(try (provider_reasoning.Block{ .text = .{ .text = thinking, .signature = signature } }).clone(accumulated.allocator));
        },
        .redacted_thinking => {
            support.fields(block, &.{ "type", "data" }) catch return markInvalid(accumulated);
            const data = string(block.object.get("data") orelse return markInvalid(accumulated)) catch return markInvalid(accumulated);
            try accumulated.appendReasoning(try (provider_reasoning.Block{ .redacted = .{ .base64 = data } }).clone(accumulated.allocator));
        },
    }
}

fn markInvalid(accumulated: *assembly.Accumulator) void {
    accumulated.invalid_content = true;
}

fn refusalDetails(raw: std.json.Value) Invalid!void {
    try support.fields(raw, &.{ "type", "category", "explanation" });
    try support.required(raw, &.{ "type", "category", "explanation" });
    if (!std.mem.eql(u8, try string(try field(raw, "type")), "refusal")) return error.InvalidResponse;
    try nullableEnumeration(try field(raw, "category"), &.{ "cyber", "bio", "frontier_llm", "reasoning_extraction", "general_harms" });
    const explanation = try field(raw, "explanation");
    if (explanation != .null) _ = try string(explanation);
}

pub fn classifyResponse(allocator: std.mem.Allocator, response: transport.Response) std.mem.Allocator.Error!?transport.Failure {
    const received = switch (response) {
        .failed => |value| return value,
        .received => |value| value,
    };
    if (received.status == 200) return null;
    return try assembly.classifyErrorBody(allocator, received, decodeError);
}

/// A failure classifies only when both status and `error.type` match; the
/// spend cap is identified by its documented machine code, never by text.
fn decodeError(raw: std.json.Value, received: assembly.Received) Invalid!operation.ProviderFailureCause {
    try support.fields(raw, &.{ "type", "error", "request_id" });
    if (!std.mem.eql(u8, try string(try field(raw, "type")), "error")) return error.InvalidResponse;
    if (raw.object.get("request_id")) |value| _ = try string(value);
    const failure = try field(raw, "error");
    try support.fields(failure, &.{ "type", "message", "details" });
    _ = try string(try field(failure, "message"));
    const kind = try string(try field(failure, "type"));
    var spend_cap = false;
    if (failure.object.get("details")) |details| {
        try support.fields(details, &.{"error_code"});
        if (!std.mem.eql(u8, try string(try field(details, "error_code")), "enforced_spend_limit_reached")) return error.InvalidResponse;
        spend_cap = true;
    }
    const Mapping = struct { status: u16, kind: []const u8, cause: operation.ProviderFailureCause };
    const mappings = [_]Mapping{
        .{ .status = 400, .kind = "invalid_request_error", .cause = .request_rejected },
        .{ .status = 401, .kind = "authentication_error", .cause = .authentication_failed },
        // Billing and the spend cap stop until an account change (user decision).
        .{ .status = 402, .kind = "billing_error", .cause = .authorization_denied },
        .{ .status = 403, .kind = "permission_error", .cause = .authorization_denied },
        .{ .status = 404, .kind = "not_found_error", .cause = .model_unavailable },
        .{ .status = 413, .kind = "request_too_large", .cause = .request_rejected },
        .{ .status = 429, .kind = "rate_limit_error", .cause = .throttled },
        .{ .status = 500, .kind = "api_error", .cause = .service_unavailable },
        .{ .status = 504, .kind = "timeout_error", .cause = .timeout },
        .{ .status = 529, .kind = "overloaded_error", .cause = .service_unavailable },
    };
    for (mappings) |mapping| if (received.status == mapping.status and std.mem.eql(u8, kind, mapping.kind)) {
        if (spend_cap) return if (mapping.status == 429) .authorization_denied else error.InvalidResponse;
        return mapping.cause;
    };
    return error.InvalidResponse;
}
