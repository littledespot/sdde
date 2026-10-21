const std = @import("std");
const transport = @import("adapters/provider/model_http_transport.zig");

pub const complete = "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"{}\"}]}},\"stopReason\":\"end_turn\",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12}}";

pub const Wire = struct {
    calls: usize = 0,
    expected_json: ?bool = null,
    result: ?transport.Response = null,
    cancelled: bool = false,
    inference_body: []const u8 = complete,
    /// When set, inference must send exactly this maximum and counting none.
    expected_max_tokens: ?u32 = null,

    pub fn port(self: *Wire) transport.Port {
        return .{ .context = @ptrCast(self), .exchange_fn = exchange };
    }
    fn exchange(context: *transport.Context, allocator: std.mem.Allocator, request: transport.Request) transport.Error!transport.Response {
        const self: *Wire = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (self.expected_json) |enabled| {
            var parsed = std.json.parseFromSlice(std.json.Value, allocator, request.body, .{}) catch |err| return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => @panic("provider emitted malformed JSON"),
            };
            defer parsed.deinit();
            std.debug.assert(parsed.value.object.contains("outputConfig") == enabled);
        }
        if (self.expected_max_tokens) |maximum| {
            var parsed = std.json.parseFromSlice(std.json.Value, allocator, request.body, .{}) catch |err| return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => @panic("provider emitted malformed JSON"),
            };
            defer parsed.deinit();
            const sent = if (parsed.value.object.get("inferenceConfig")) |config| config.object.get("maxTokens") else null;
            switch (request.kind()) {
                .inference => std.debug.assert(sent != null and sent.?.integer == maximum),
                .input_token_count => std.debug.assert(std.mem.indexOf(u8, request.body, "maxTokens") == null),
            }
        }
        std.debug.assert(request.api_key.len != 0);
        std.debug.assert(std.mem.indexOf(u8, request.body, request.api_key) == null);
        if (self.cancelled) return error.Cancelled;
        return self.result orelse .{ .received = .{ .status = 200, .body = if (request.kind() == .input_token_count) "{\"inputTokens\":10}" else self.inference_body } };
    }
};

// Inspect the Converse body or CountTokens' identical input projection.
pub fn requestBody(a: std.mem.Allocator, bytes: []const u8, kind: @import("domain/llm_provider_operation.zig").ProviderOperationKind) ![]u8 {
    if (kind == .inference) return a.dupe(u8, bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, a, bytes, .{});
    defer parsed.deinit();
    return std.json.Stringify.valueAlloc(a, parsed.value.object.get("input").?.object.get("converse").?, .{});
}
