const std = @import("std");
const operation = @import("../../domain/llm_provider_operation.zig");

pub const Error = std.mem.Allocator.Error || error{InvalidRequest};

pub const ReasoningEffort = enum { low, medium, high };

pub fn reasoningEffort(value: ?[]const u8) error{InvalidRequest}!?ReasoningEffort {
    const selected = value orelse return null;
    return std.meta.stringToEnum(ReasoningEffort, selected) orelse error.InvalidRequest;
}

pub fn encode(allocator: std.mem.Allocator, request: *const operation.IdentifiedProviderNeutralModelRequest, kind: operation.ProviderOperationKind) Error![]const u8 {
    const schema: TextSchema = switch (request.response_guidance_mode) {
        .prompt_only => .{ .prompt_only = request.response_schema.modelBytes() },
        .native_schema => .{ .native = .{
            .guidance = request.response_schema.modelBytes(),
            .structure = try @import("../../domain/model_schema_projection.zig").render(allocator, request.response_schema, .bedrock),
        } },
    };
    defer if (schema == .native) allocator.free(schema.native.structure);
    return encodeText(allocator, .{
        .content = request.content,
        .schema = schema,
        .schema_name = "sdde_model_envelope_v1",
        .temperature = request.controls.temperature,
        .reasoning_effort = try reasoningEffort(request.binding_id.reasoning_effort),
    }, kind);
}

pub const TextSchema = union(enum) {
    prompt_only: []const u8,
    native: struct { guidance: []const u8, structure: []const u8 },

    pub fn guidance(self: TextSchema) []const u8 {
        return switch (self) {
            .prompt_only => |bytes| bytes,
            .native => |native| native.guidance,
        };
    }
};

pub const TextRequest = struct {
    content: []const operation.ModelVisibleContent,
    schema: TextSchema,
    schema_name: []const u8,
    temperature: ?@import("../../domain/model_controls.zig").Temperature,
    reasoning_effort: ?ReasoningEffort,
};

// Shared text serialization; callers supply validated settings and schema.
pub fn encodeText(allocator: std.mem.Allocator, request: TextRequest, kind: operation.ProviderOperationKind) Error![]const u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    var schema: ?std.json.Parsed(std.json.Value) = null;
    if (request.schema == .native) schema = std.json.parseFromSlice(std.json.Value, allocator, request.schema.native.structure, .{}) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidRequest;
    defer if (schema) |*parsed| parsed.deinit();
    writeInvoke(&output.writer, request, if (schema) |parsed| parsed.value else null) catch |err| return if (err == error.InvalidRequest) error.InvalidRequest else error.OutOfMemory;
    if (kind == .inference) return output.toOwnedSlice();
    const encoder = std.base64.standard.Encoder;
    const encoded = try allocator.alloc(u8, encoder.calcSize(output.written().len));
    defer allocator.free(encoded);
    return std.json.Stringify.valueAlloc(allocator, .{ .input = .{ .invokeModel = .{ .body = encoder.encode(encoded, output.written()) } } }, .{});
}

// GPT-OSS InvokeModel uses the OpenAI chat-completion body. Model and stream
// are omitted: the endpoint fixes both. Schema remains a JSON object on this wire.
fn writeInvoke(writer: *std.Io.Writer, request: TextRequest, schema: ?std.json.Value) !void {
    var json: std.json.Stringify = .{ .writer = writer, .options = .{} };
    try json.beginObject();
    try json.objectField("messages");
    try json.beginArray();
    for ([_]bool{ true, false }) |system| {
        try json.beginObject();
        try json.objectField("role");
        try json.write(if (system) "developer" else "user");
        try json.objectField("content");
        try json.beginArray();
        var count: usize = 0;
        for (request.content) |part| {
            const selected = switch (part) {
                .system, .guidance => |text| if (system) text else null,
                .user, .evidence => |text| if (!system) text else null,
            };
            if (selected) |text| {
                try json.write(.{ .type = "text", .text = text });
                count += 1;
            }
        }
        if (system) {
            try json.write(.{ .type = "text", .text = @import("../../domain/model_controls.zig").response_format_guidance });
            try json.write(.{ .type = "text", .text = request.schema.guidance() });
        } else if (count == 0) return error.InvalidRequest;
        try json.endArray();
        try json.endObject();
    }
    try json.endArray();
    if (request.reasoning_effort) |effort| {
        try json.objectField("reasoning_effort");
        try json.write(effort);
    }
    if (request.temperature) |temperature| {
        try json.objectField("temperature");
        try json.write(temperature.wireValue());
    }
    if (schema) |shape| {
        try json.objectField("response_format");
        try json.write(.{ .type = "json_schema", .json_schema = .{ .name = request.schema_name, .schema = shape } });
    }
    try json.endObject();
}
