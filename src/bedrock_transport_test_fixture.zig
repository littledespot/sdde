const std = @import("std");
const transport = @import("adapters/provider/bedrock_transport.zig");

pub const complete = "{\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"{}\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2,\"total_tokens\":12}}";

pub const Wire = struct {
    calls: usize = 0,
    expected_json: ?bool = null,
    result: ?transport.Response = null,
    cancelled: bool = false,
    inference_body: []const u8 = complete,

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
            std.debug.assert(parsed.value.object.contains("response_format") == enabled);
        }
        std.debug.assert(request.api_key.len != 0);
        std.debug.assert(std.mem.indexOf(u8, request.body, request.api_key) == null);
        if (self.cancelled) return error.Cancelled;
        return self.result orelse .{ .received = .{ .status = 200, .body = if (request.kind == .input_token_count) "{\"inputTokens\":10}" else self.inference_body } };
    }
};

// Inspect the actual InvokeModel body, including its CountTokens binary wrapper.
pub fn requestBody(a: std.mem.Allocator, bytes: []const u8, kind: @import("domain/llm_provider_operation.zig").ProviderOperationKind) ![]u8 {
    if (kind == .inference) return a.dupe(u8, bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, a, bytes, .{});
    defer parsed.deinit();
    const encoded = parsed.value.object.get("input").?.object.get("invokeModel").?.object.get("body").?.string;
    const decoder = std.base64.standard.Decoder;
    const body = try a.alloc(u8, try decoder.calcSizeForSlice(encoded));
    errdefer a.free(body);
    try decoder.decode(body, encoded);
    return body;
}
