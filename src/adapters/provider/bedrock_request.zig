//! Bedrock Converse wire encoding from the shared text layout.
const std = @import("std");
const operation = @import("../../domain/llm_provider_operation.zig");
const text = @import("model_text_request.zig");

pub const Error = text.Error;
pub const Family = @import("../../domain/llm_provider_contracts.zig").BedrockFamily;
const ModelMaximumOutput = @import("../../domain/llm_provider_contracts.zig").ModelMaximumOutput;

pub fn encode(allocator: std.mem.Allocator, request: *const operation.IdentifiedProviderNeutralModelRequest, family: Family, max_output_tokens: ModelMaximumOutput) Error![]const u8 {
    const schema = try text.schemaFor(allocator, request);
    defer text.freeSchema(allocator, schema);
    return encodeText(allocator, .{
        .content = request.content,
        .schema = schema,
        .schema_name = "sdde_model_envelope_v1",
        .temperature = request.temperature(),
        .reasoning_effort = try text.reasoningEffort(request.binding_id.reasoning_effort),
        .family = family,
        .max_output_tokens = max_output_tokens,
    });
}

pub const TextRequest = struct {
    content: []const operation.ModelVisibleContent,
    schema: text.TextSchema,
    /// Converse's required JSON-schema name.
    schema_name: []const u8,
    temperature: ?@import("../../domain/model_controls.zig").Temperature,
    reasoning_effort: ?text.ReasoningEffort,
    /// The compiled family that fixes every model-specific request field (ADR 0029).
    family: Family,
    /// The model's documented maximum output (ADR 0011); never a smaller allowance.
    max_output_tokens: ModelMaximumOutput,
};

// Callers supply validated settings and schema.
pub fn encodeText(allocator: std.mem.Allocator, request: TextRequest) Error![]const u8 {
    try text.validateStructure(allocator, request.schema);
    switch (request.family) {
        .converse => if (request.reasoning_effort != null) return error.InvalidRequest,
        .@"gpt-oss" => if (request.reasoning_effort) |effort| switch (effort) {
            .low, .medium, .high => {},
            .xhigh, .max => return error.InvalidRequest,
        },
        .luna => if (request.reasoning_effort != null or request.temperature != null) return error.InvalidRequest,
        // Claude rejects non-default sampling; every documented effort level is valid.
        .claude => if (request.temperature != null) return error.InvalidRequest,
    }
    const parts = try text.layout(allocator, request.content, request.schema);
    defer parts.deinit(allocator);
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    writeConverse(&output.writer, request, parts) catch return error.OutOfMemory;
    return output.toOwnedSlice();
}

fn writeConverse(writer: *std.Io.Writer, request: TextRequest, parts: text.Layout) std.Io.Writer.Error!void {
    var json: std.json.Stringify = .{ .writer = writer, .options = .{} };
    try json.beginObject();
    try writeInput(&json, parts);
    try writeModelFields(&json, request);
    // The model's documented maximum is sent, because Bedrock otherwise
    // applies a smaller default; no slot can narrow it (ADR 0011).
    try json.objectField("inferenceConfig");
    try json.beginObject();
    if (request.temperature) |temperature| {
        try json.objectField("temperature");
        try json.write(temperature.wireValue());
    }
    try json.objectField("maxTokens");
    try json.write(request.max_output_tokens.tokens);
    try json.endObject();
    if (request.schema == .native) {
        try json.objectField("outputConfig");
        try json.write(.{ .textFormat = .{ .type = "json_schema", .structure = .{ .jsonSchema = .{ .name = request.schema_name, .schema = request.schema.native.structure } } } });
    }
    try json.endObject();
}

// Model-specific fields use the catalogue-selected compiled family, never
// model-name text.
fn writeInput(json: *std.json.Stringify, parts: text.Layout) std.Io.Writer.Error!void {
    try json.objectField("system");
    try json.beginArray();
    for (parts.system) |value| try json.write(.{ .text = value });
    try json.endArray();
    try json.objectField("messages");
    try json.beginArray();
    try json.beginObject();
    try json.objectField("role");
    try json.write("user");
    try json.objectField("content");
    try json.beginArray();
    for (parts.user) |value| try json.write(.{ .text = value });
    try json.endArray();
    try json.endObject();
    try json.endArray();
}

fn writeModelFields(json: *std.json.Stringify, request: TextRequest) std.Io.Writer.Error!void {
    const reasoning = request.family == .@"gpt-oss" and request.reasoning_effort != null;
    // Claude takes effort in its own `output_config` object; adaptive thinking is
    // the model's default, so no `thinking` field is sent.
    const effort = request.family == .claude and request.reasoning_effort != null;
    const strict_json = request.family == .luna and request.schema == .native;
    if (reasoning or effort or strict_json) {
        try json.objectField("additionalModelRequestFields");
        try json.beginObject();
        if (reasoning) {
            try json.objectField("reasoning_effort");
            try json.write(request.reasoning_effort.?);
        }
        if (effort) {
            try json.objectField("output_config");
            try json.write(.{ .effort = request.reasoning_effort.? });
        }
        if (strict_json) {
            try json.objectField("text");
            try json.write(.{ .format = .{ .strict = true } });
        }
        try json.endObject();
    }
}
