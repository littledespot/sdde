const std = @import("std");
const operation = @import("../../domain/llm_provider_operation.zig");

pub const Error = std.mem.Allocator.Error || error{InvalidRequest};

pub const ReasoningEffort = enum { low, medium, high };

pub fn reasoningEffort(value: ?[]const u8) error{InvalidRequest}!?ReasoningEffort {
    const selected = value orelse return null;
    return std.meta.stringToEnum(ReasoningEffort, selected) orelse error.InvalidRequest;
}

pub fn encode(allocator: std.mem.Allocator, request: *const operation.IdentifiedProviderNeutralModelRequest, kind: operation.ProviderOperationKind) Error![]const u8 {
    return encodeText(allocator, .{
        .content = request.content,
        .schema = request.response_schema.modelBytes(),
        .response_mode = request.response_guidance_mode,
        .schema_name = "sdde_model_envelope_v1",
        .temperature = if (request.controls.temperature) |temperature| @as(f64, @floatFromInt(temperature.value)) / 1000.0 else null,
        .reasoning_effort = try reasoningEffort(request.binding_id.reasoning_effort),
    }, kind);
}

pub const TextRequest = struct {
    content: []const operation.ModelVisibleContent,
    schema: []const u8,
    response_mode: @import("../../domain/model_controls.zig").ResponseGuidanceMode,
    schema_name: []const u8,
    temperature: ?f64,
    reasoning_effort: ?ReasoningEffort,
};

// Shared text serialization; callers supply validated settings and schema.
pub fn encodeText(allocator: std.mem.Allocator, request: TextRequest, kind: operation.ProviderOperationKind) Error![]const u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    write(&output.writer, request, kind) catch |err| return if (err == error.InvalidRequest) error.InvalidRequest else error.OutOfMemory;
    return output.toOwnedSlice();
}

fn write(writer: *std.Io.Writer, request: TextRequest, kind: operation.ProviderOperationKind) !void {
    var json: std.json.Stringify = .{ .writer = writer, .options = .{} };
    try json.beginObject();
    if (kind == .input_token_count) {
        try json.objectField("input");
        try json.beginObject();
        try json.objectField("converse");
        try json.beginObject();
    }
    try textInput(&json, request);
    if (kind == .input_token_count) {
        try json.endObject();
        try json.endObject();
    } else {
        if (request.reasoning_effort) |effort| {
            try json.objectField("additionalModelRequestFields");
            try json.write(.{ .reasoning_effort = effort });
        }
        if (request.temperature) |temperature| {
            try json.objectField("inferenceConfig");
            try json.beginObject();
            try json.objectField("temperature");
            try json.write(temperature);
            try json.endObject();
        }
        if (request.response_mode == .native_schema) {
            try json.objectField("outputConfig");
            try json.write(.{ .textFormat = .{ .type = "json_schema", .structure = .{ .jsonSchema = .{
                .schema = request.schema,
                .name = request.schema_name,
            } } } });
        }
    }
    try json.endObject();
}

// One projection for both APIs. The result schema is sent once: as guidance
// for prompt-only, or as native outputConfig for registered native support.
fn textInput(json: *std.json.Stringify, request: TextRequest) !void {
    try json.objectField("system");
    try json.beginArray();
    for (request.content) |part| switch (part) {
        .system, .guidance => |text| try json.write(.{ .text = text }),
        .user, .evidence => {},
    };
    try json.write(.{ .text = @import("../../domain/model_controls.zig").response_format_guidance });
    if (request.response_mode == .prompt_only) try json.write(.{ .text = request.schema });
    try json.endArray();
    try json.objectField("messages");
    try json.beginArray();
    try json.beginObject();
    try json.objectField("role");
    try json.write("user");
    try json.objectField("content");
    try json.beginArray();
    var has_input = false;
    for (request.content) |part| switch (part) {
        .user, .evidence => |text| {
            has_input = true;
            try json.write(.{ .text = text });
        },
        .system, .guidance => {},
    };
    if (!has_input) return error.InvalidRequest;
    try json.endArray();
    try json.endObject();
    try json.endArray();
}
