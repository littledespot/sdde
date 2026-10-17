const std = @import("std");
const operation = @import("../../domain/llm_provider_operation.zig");

pub const Error = std.mem.Allocator.Error || error{InvalidRequest};

pub const ReasoningEffort = enum { low, medium, high, xhigh, max };
pub const RequestProfile = @import("../../domain/llm_provider_contracts.zig").BedrockRequestProfile;

pub fn reasoningEffort(value: ?[]const u8) error{InvalidRequest}!?ReasoningEffort {
    const selected = value orelse return null;
    return std.meta.stringToEnum(ReasoningEffort, selected) orelse error.InvalidRequest;
}

pub fn encode(allocator: std.mem.Allocator, request: *const operation.IdentifiedProviderNeutralModelRequest, kind: operation.ProviderOperationKind, profile: RequestProfile) Error![]const u8 {
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
        .max_output_tokens = request.controls.max_output_tokens,
        .reasoning_effort = try reasoningEffort(request.binding_id.reasoning_effort),
        .request_profile = profile,
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
    max_output_tokens: ?@import("../../domain/model_controls.zig").OutputTokenAllowance = null,
    reasoning_effort: ?ReasoningEffort,
    request_profile: RequestProfile = .none,
};

// Shared text serialization; callers supply validated settings and schema.
pub fn encodeText(allocator: std.mem.Allocator, request: TextRequest, kind: operation.ProviderOperationKind) Error![]const u8 {
    if (request.max_output_tokens) |allowance| if (!allowance.isValid()) return error.InvalidRequest;
    if (request.schema == .native) {
        var projected = @import("../../domain/strict_json.zig").parse(allocator, request.schema.native.structure, .{ .maximum_depth = std.math.maxInt(usize) }, false, null) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidRequest;
        defer projected.deinit();
        if (projected.value != .object) return error.InvalidRequest;
    }
    switch (request.request_profile) {
        .none => if (request.reasoning_effort != null) return error.InvalidRequest,
        .openai_oss => if (request.reasoning_effort) |effort| switch (effort) {
            .low, .medium, .high => {},
            .xhigh, .max => return error.InvalidRequest,
        },
        .openai_luna => if (request.reasoning_effort != null or request.temperature != null) return error.InvalidRequest,
    }
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    writeConverse(&output.writer, request, kind) catch |err| return if (err == error.InvalidRequest) error.InvalidRequest else error.OutOfMemory;
    return output.toOwnedSlice();
}

fn writeConverse(writer: *std.Io.Writer, request: TextRequest, kind: operation.ProviderOperationKind) (std.Io.Writer.Error || error{InvalidRequest})!void {
    var json: std.json.Stringify = .{ .writer = writer, .options = .{} };
    try json.beginObject();
    if (kind == .input_token_count) {
        try json.objectField("input");
        try json.beginObject();
        try json.objectField("converse");
        try json.beginObject();
    }
    try writeInput(&json, request);
    try writeModelFields(&json, request, kind);
    if (kind == .inference) {
        if (request.temperature != null or request.max_output_tokens != null) {
            try json.objectField("inferenceConfig");
            try json.beginObject();
            if (request.temperature) |temperature| {
                try json.objectField("temperature");
                try json.write(temperature.wireValue());
            }
            if (request.max_output_tokens) |allowance| {
                try json.objectField("maxTokens");
                try json.write(allowance.value);
            }
            try json.endObject();
        }
        if (request.schema == .native) {
            try json.objectField("outputConfig");
            try json.write(.{ .textFormat = .{ .type = "json_schema", .structure = .{ .jsonSchema = .{ .name = request.schema_name, .schema = request.schema.native.structure } } } });
        }
    } else {
        try json.endObject();
        try json.endObject();
    }
    try json.endObject();
}

// Converse shares its model-visible input with CountTokens. Provider-specific
// fields use the registered typed profile, never model-name text.
fn writeInput(json: *std.json.Stringify, request: TextRequest) (std.Io.Writer.Error || error{InvalidRequest})!void {
    try json.objectField("system");
    try json.beginArray();
    for (request.content) |part| switch (part) {
        .system, .guidance => |text| try json.write(.{ .text = text }),
        .user, .evidence => {},
    };
    try json.write(.{ .text = @import("../../domain/model_controls.zig").response_format_guidance });
    try json.write(.{ .text = request.schema.guidance() });
    try json.endArray();
    try json.objectField("messages");
    try json.beginArray();
    try json.beginObject();
    try json.objectField("role");
    try json.write("user");
    try json.objectField("content");
    try json.beginArray();
    var count: usize = 0;
    for (request.content) |part| switch (part) {
        .user, .evidence => |text| {
            try json.write(.{ .text = text });
            count += 1;
        },
        .system, .guidance => {},
    };
    if (count == 0) return error.InvalidRequest;
    try json.endArray();
    try json.endObject();
    try json.endArray();
}

fn writeModelFields(json: *std.json.Stringify, request: TextRequest, kind: operation.ProviderOperationKind) std.Io.Writer.Error!void {
    const reasoning = request.request_profile == .openai_oss and request.reasoning_effort != null;
    const strict_json = request.request_profile == .openai_luna and request.schema == .native and kind == .inference;
    if (reasoning or strict_json) {
        try json.objectField("additionalModelRequestFields");
        try json.beginObject();
        if (reasoning) {
            try json.objectField("reasoning_effort");
            try json.write(request.reasoning_effort.?);
        }
        if (strict_json) {
            try json.objectField("text");
            try json.write(.{ .format = .{ .strict = true } });
        }
        try json.endObject();
    }
}
