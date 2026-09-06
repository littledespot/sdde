const std = @import("std");
const operation = @import("../../domain/llm_provider_operation.zig");

pub const Error = std.mem.Allocator.Error || error{InvalidRequest};

pub fn encode(allocator: std.mem.Allocator, request: *const operation.IdentifiedProviderNeutralModelRequest, kind: operation.ProviderOperationKind) Error![]const u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    write(&output.writer, request, kind) catch |err| return if (err == error.InvalidRequest) error.InvalidRequest else error.OutOfMemory;
    return output.toOwnedSlice();
}

fn write(writer: *std.Io.Writer, request: *const operation.IdentifiedProviderNeutralModelRequest, kind: operation.ProviderOperationKind) !void {
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
        if (request.controls.temperature) |temperature| {
            try json.objectField("inferenceConfig");
            try json.beginObject();
            try json.objectField("temperature");
            try json.write(@as(f64, @floatFromInt(temperature.value)) / 1000.0);
            try json.endObject();
        }
        if (request.response_guidance_mode == .native_schema) {
            try json.objectField("outputConfig");
            try json.write(.{ .textFormat = .{ .type = "json_schema", .structure = .{ .jsonSchema = .{
                .schema = request.response_schema.bytes(),
                .name = "sdde_model_envelope_v1",
            } } } });
        }
    }
    try json.endObject();
}

// One projection for both APIs. The result schema is sent once: as guidance
// for prompt-only, or as native outputConfig for registered native support.
fn textInput(json: *std.json.Stringify, request: *const operation.IdentifiedProviderNeutralModelRequest) !void {
    try json.objectField("system");
    try json.beginArray();
    for (request.content) |part| switch (part) {
        .system, .guidance => |text| try json.write(.{ .text = text }),
        .user, .evidence => {},
    };
    if (request.response_guidance_mode == .prompt_only) try json.write(.{ .text = request.response_schema.bytes() });
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
