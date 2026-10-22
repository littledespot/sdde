//! Anthropic Messages API wire encoding from the shared text layout (ADR 0028).
//! Only inference exists: no token counting, sampling, thinking, stop sequence,
//! tool, cache, geography or speed field is ever sent.
const std = @import("std");
const operation = @import("../../domain/llm_provider_operation.zig");
const text = @import("model_text_request.zig");
const ModelMaximumOutput = @import("../../domain/llm_provider_contracts.zig").ModelMaximumOutput;

pub const Error = text.Error;

pub fn encode(allocator: std.mem.Allocator, request: *const operation.IdentifiedProviderNeutralModelRequest, model: []const u8, max_output_tokens: ModelMaximumOutput) Error![]const u8 {
    const schema = try text.schemaFor(allocator, request);
    defer text.freeSchema(allocator, schema);
    return encodeText(allocator, .{
        .model = model,
        .content = request.content,
        .schema = schema,
        .temperature = request.controls.temperature,
        .reasoning_effort = try text.reasoningEffort(request.binding_id.reasoning_effort),
        .max_output_tokens = max_output_tokens,
    });
}

pub const TextRequest = struct {
    model: []const u8,
    content: []const operation.ModelVisibleContent,
    schema: text.TextSchema,
    /// Registered Anthropic models declare no temperature; any value rejects.
    temperature: ?@import("../../domain/model_controls.zig").Temperature,
    reasoning_effort: ?text.ReasoningEffort,
    /// The catalogue's documented maximum, sent unchanged as `max_tokens`.
    max_output_tokens: ModelMaximumOutput,
};

pub fn encodeText(allocator: std.mem.Allocator, request: TextRequest) Error![]const u8 {
    if (request.temperature != null or request.model.len == 0) return error.InvalidRequest;
    try text.validateStructure(allocator, request.schema);
    const parts = try text.layout(allocator, request.content, request.schema);
    defer parts.deinit(allocator);
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    writeMessages(&output.writer, request, parts) catch return error.OutOfMemory;
    return output.toOwnedSlice();
}

fn writeMessages(writer: *std.Io.Writer, request: TextRequest, parts: text.Layout) std.Io.Writer.Error!void {
    var json: std.json.Stringify = .{ .writer = writer, .options = .{} };
    try json.beginObject();
    try json.objectField("model");
    try json.write(request.model);
    try json.objectField("max_tokens");
    try json.write(request.max_output_tokens.tokens);
    try json.objectField("system");
    try json.beginArray();
    for (parts.system) |value| try json.write(.{ .type = "text", .text = value });
    try json.endArray();
    try json.objectField("messages");
    try json.beginArray();
    try json.beginObject();
    try json.objectField("role");
    try json.write("user");
    try json.objectField("content");
    try json.beginArray();
    for (parts.user) |value| try json.write(.{ .type = "text", .text = value });
    try json.endArray();
    try json.endObject();
    try json.endArray();
    if (request.reasoning_effort != null or request.schema == .native) {
        try json.objectField("output_config");
        try json.beginObject();
        if (request.reasoning_effort) |effort| {
            try json.objectField("effort");
            try json.write(effort);
        }
        if (request.schema == .native) {
            // The Messages API takes the schema as a JSON object, not a string.
            try json.objectField("format");
            try json.beginObject();
            try json.objectField("type");
            try json.write("json_schema");
            try json.objectField("schema");
            try json.beginWriteRaw();
            try json.writer.writeAll(request.schema.native.structure);
            json.endWriteRaw();
            try json.endObject();
        }
        try json.endObject();
    }
    try json.endObject();
}

test "Messages request carries the layout, maximum, effort and schema object" {
    const a = std.testing.allocator;
    const content = [_]operation.ModelVisibleContent{ .{ .system = "rules" }, .{ .user = "input" } };
    const body = try encodeText(a, .{
        .model = "claude-haiku-5-5",
        .content = &content,
        .schema = .{ .native = .{ .guidance = "{\"schema\":1}", .structure = "{\"type\":\"object\",\"additionalProperties\":false}" } },
        .temperature = null,
        .reasoning_effort = .low,
        .max_output_tokens = .{ .tokens = 128000 },
    });
    defer a.free(body);
    const guidance = @import("../../domain/model_controls.zig").response_format_guidance;
    const expected = try std.fmt.allocPrint(a, "{{\"model\":\"claude-haiku-5-5\",\"max_tokens\":128000,\"system\":[{{\"type\":\"text\",\"text\":\"rules\"}},{{\"type\":\"text\",\"text\":\"{s}\"}},{{\"type\":\"text\",\"text\":\"{{\\\"schema\\\":1}}\"}}],\"messages\":[{{\"role\":\"user\",\"content\":[{{\"type\":\"text\",\"text\":\"input\"}}]}}],\"output_config\":{{\"effort\":\"low\",\"format\":{{\"type\":\"json_schema\",\"schema\":{{\"type\":\"object\",\"additionalProperties\":false}}}}}}}}", .{guidance});
    defer a.free(expected);
    try std.testing.expectEqualStrings(expected, body);
}

test "prompt-only Messages request without effort sends no output configuration" {
    const a = std.testing.allocator;
    const content = [_]operation.ModelVisibleContent{.{ .evidence = "source" }};
    const body = try encodeText(a, .{ .model = "claude-opus-5-5", .content = &content, .schema = .{ .prompt_only = "{}" }, .temperature = null, .reasoning_effort = null, .max_output_tokens = .{ .tokens = 64 } });
    defer a.free(body);
    var parsed = try std.json.parseFromSlice(std.json.Value, a, body, .{});
    defer parsed.deinit();
    try std.testing.expect(!parsed.value.object.contains("output_config"));
    inline for (.{ "temperature", "top_p", "top_k", "thinking", "stop_sequences", "tools", "inference_geo", "speed", "anthropic-beta" }) |forbidden| {
        try std.testing.expect(std.mem.indexOf(u8, body, forbidden) == null);
    }
    try std.testing.expectEqual(@as(i64, 64), parsed.value.object.get("max_tokens").?.integer);
}

test "Messages request rejects temperature, missing user text and non-object schemas before send" {
    const a = std.testing.allocator;
    const content = [_]operation.ModelVisibleContent{.{ .user = "input" }};
    const base: TextRequest = .{ .model = "claude-sonnet-5-5", .content = &content, .schema = .{ .prompt_only = "{}" }, .temperature = null, .reasoning_effort = null, .max_output_tokens = .{ .tokens = 1 } };
    var with_temperature = base;
    with_temperature.temperature = .fixed;
    try std.testing.expectError(error.InvalidRequest, encodeText(a, with_temperature));
    var without_user = base;
    without_user.content = &.{.{ .system = "rules" }};
    try std.testing.expectError(error.InvalidRequest, encodeText(a, without_user));
    var array_schema = base;
    array_schema.schema = .{ .native = .{ .guidance = "{}", .structure = "[]" } };
    try std.testing.expectError(error.InvalidRequest, encodeText(a, array_schema));
    var unnamed = base;
    unnamed.model = "";
    try std.testing.expectError(error.InvalidRequest, encodeText(a, unnamed));
}
