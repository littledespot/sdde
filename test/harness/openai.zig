//! OpenAI wire projection only. No credentials, network, scoring or file access.
const std = @import("std");
const c = @import("contracts.zig");
const packet = @import("packet.zig");
const report = @import("report.zig");
const strict_json = @import("../../src/domain/strict_json.zig");
const provider = @import("provider.zig");
const configuration = @import("configuration.zig");

pub fn request(a: std.mem.Allocator, config: configuration.Config, capture: c.Capture) c.Error![]const u8 {
    try configuration.validate(config);
    if (config.api != .openai_responses) return error.InvalidEvaluationContract;
    const schema_bytes = try packet.resultSchema(a);
    const schema = try c.decode(std.json.Value, a, schema_bytes);
    const body = try packet.input(a, capture);
    const Reasoning = struct { effort: []const u8 };
    return std.json.Stringify.valueAlloc(a, .{
        .model = config.model,
        .instructions = packet.instructions,
        .input = [_]struct { role: []const u8, content: []const u8 }{.{ .role = "user", .content = body }},
        .text = .{ .format = .{ .type = "json_schema", .name = "rubric_judgment", .strict = true, .schema = schema } },
        .reasoning = if (config.reasoning_effort) |effort| @as(?Reasoning, .{ .effort = @tagName(effort) }) else null,
        .temperature = config.temperature,
        .tools = [_]struct {}{},
        .store = false,
        .stream = false,
        .truncation = "disabled",
    }, .{ .emit_null_optional_fields = false }) catch return error.OutOfMemory;
}

/// API envelope fields are allowlisted independently of the closed judgment
/// schema. Unknown output kinds (including tool calls) are rejected.
pub fn response(a: std.mem.Allocator, bytes: []const u8) c.Error!provider.Observation {
    var parsed = strict_json.parse(a, bytes, .{ .maximum_depth = 32 }, true) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidEvaluationContract;
    defer parsed.deinit();
    const root = parsed.value;
    try fields(root, &.{ "id", "object", "created_at", "completed_at", "status", "background", "error", "incomplete_details", "instructions", "max_output_tokens", "max_tool_calls", "model", "output", "parallel_tool_calls", "previous_response_id", "prompt", "reasoning", "service_tier", "store", "temperature", "text", "tool_choice", "tools", "top_p", "top_logprobs", "truncation", "usage", "user", "metadata", "safety_identifier", "prompt_cache_key", "prompt_cache_retention", "context_management", "conversation", "moderation", "prompt_cache_options", "prompt_cache_diagnostics" });
    const id = try string(root, "id");
    const model = try string(root, "model");
    if (!c.id(id) or c.ModelId.parse(model) == null or !std.mem.eql(u8, try string(root, "object"), "response")) return error.InvalidEvaluationContract;
    var result: provider.Observation = .{ .identity = .{ .openai_response = .{ .response_id = try a.dupe(u8, id), .actual_model = try a.dupe(u8, model) } } };
    if (root.object.get("usage")) |usage| if (usage != .null) {
        try fields(usage, &.{ "input_tokens", "output_tokens", "total_tokens", "input_tokens_details", "output_tokens_details" });
        result.usage = report.Usage.init(try integer(usage, "input_tokens"), try integer(usage, "output_tokens"), try integer(usage, "total_tokens")) orelse return error.InvalidEvaluationContract;
    };
    readOutput(a, root, &result) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        // Valid usage remains an observation even when output transport fails.
        result.failure = .invalid_response;
        result.payload = null;
    };
    return result;
}
fn readOutput(a: std.mem.Allocator, root: std.json.Value, result: *provider.Observation) c.Error!void {
    const status = try string(root, "status");
    if (std.mem.eql(u8, status, "incomplete")) {
        result.failure = .incomplete;
        return;
    }
    if (std.mem.eql(u8, status, "failed")) {
        result.failure = .provider_failed;
        return;
    }
    if (std.mem.eql(u8, status, "cancelled")) {
        result.failure = .cancelled;
        return;
    }
    if (!std.mem.eql(u8, status, "completed")) return error.InvalidEvaluationContract;
    for ([_][]const u8{ "error", "incomplete_details" }) |field| {
        if (root.object.get(field)) |value| if (value != .null) return error.InvalidEvaluationContract;
    }
    const outputs = root.object.get("output") orelse return error.InvalidEvaluationContract;
    if (outputs != .array) return error.InvalidEvaluationContract;
    for (outputs.array.items) |item| {
        const kind = try string(item, "type");
        if (std.mem.eql(u8, kind, "reasoning")) {
            try fields(item, &.{ "type", "id", "summary", "content", "encrypted_content", "status" });
            if (!c.id(try string(item, "id"))) return error.InvalidEvaluationContract;
            const summary = item.object.get("summary") orelse return error.InvalidEvaluationContract;
            if (summary != .array) return error.InvalidEvaluationContract;
            for (summary.array.items) |part| {
                try fields(part, &.{ "type", "text" });
                if (!std.mem.eql(u8, try string(part, "type"), "summary_text")) return error.InvalidEvaluationContract;
                _ = try string(part, "text");
            }
            continue;
        }
        try fields(item, &.{ "type", "id", "role", "status", "content", "phase" });
        if (!c.id(try string(item, "id")) or !std.mem.eql(u8, kind, "message") or !std.mem.eql(u8, try string(item, "role"), "assistant") or
            !std.mem.eql(u8, try string(item, "status"), "completed")) return error.InvalidEvaluationContract;
        var commentary = false;
        if (item.object.get("phase")) |phase| if (phase != .null) {
            if (phase != .string) return error.InvalidEvaluationContract;
            if (std.mem.eql(u8, phase.string, "commentary")) commentary = true else if (!std.mem.eql(u8, phase.string, "final_answer")) return error.InvalidEvaluationContract;
        };
        const content = item.object.get("content") orelse return error.InvalidEvaluationContract;
        if (content != .array) return error.InvalidEvaluationContract;
        for (content.array.items) |part| {
            const content_type = try string(part, "type");
            if (std.mem.eql(u8, content_type, "refusal")) {
                try fields(part, &.{ "type", "refusal" });
                _ = try string(part, "refusal");
                result.failure = .refused;
            } else {
                try fields(part, &.{ "type", "text", "annotations", "logprobs" });
                if (!std.mem.eql(u8, content_type, "output_text")) return error.InvalidEvaluationContract;
                const annotations = part.object.get("annotations") orelse return error.InvalidEvaluationContract;
                // No tools or file inputs are granted, so no tool citations apply.
                if (annotations != .array or annotations.array.items.len != 0) return error.InvalidEvaluationContract;
                if (part.object.get("logprobs")) |logprobs| if (logprobs != .array or logprobs.array.items.len != 0) return error.InvalidEvaluationContract;
                const text = try string(part, "text");
                if (!commentary) {
                    if (result.payload != null) return error.InvalidEvaluationContract;
                    result.payload = try a.dupe(u8, text);
                }
            }
        }
    }
    if (result.failure != null) result.payload = null else if (result.payload == null) result.failure = .invalid_response;
    if (result.usage == null and result.failure == null) {
        result.failure = .usage_unavailable;
        result.payload = null;
    }
}
fn fields(value: std.json.Value, names: []const []const u8) c.Error!void {
    if (value != .object) return error.InvalidEvaluationContract;
    for (value.object.keys()) |key| {
        var found = false;
        for (names) |name| if (std.mem.eql(u8, key, name)) {
            found = true;
            break;
        };
        if (!found) return error.InvalidEvaluationContract;
    }
}
fn string(value: std.json.Value, key: []const u8) c.Error![]const u8 {
    if (value != .object) return error.InvalidEvaluationContract;
    const field = value.object.get(key) orelse return error.InvalidEvaluationContract;
    return if (field == .string) field.string else error.InvalidEvaluationContract;
}
fn integer(value: std.json.Value, key: []const u8) c.Error!u64 {
    if (value != .object) return error.InvalidEvaluationContract;
    const field = value.object.get(key) orelse return error.InvalidEvaluationContract;
    if (field != .integer) return error.InvalidEvaluationContract;
    return std.math.cast(u64, field.integer) orelse error.InvalidEvaluationContract;
}
