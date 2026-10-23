const std = @import("std");
const transport = @import("adapters/provider/model_http_transport.zig");

pub const complete = "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"{}\"}]}},\"stopReason\":\"end_turn\",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12}}";

pub const Wire = struct {
    calls: usize = 0,
    expected_json: ?bool = null,
    result: ?transport.Response = null,
    cancelled: bool = false,
    inference_body: []const u8 = complete,
    /// When set, every request must send exactly this maximum.
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
            std.debug.assert(sent != null and sent.?.integer == maximum);
        }
        std.debug.assert(request.api_key.len != 0);
        std.debug.assert(std.mem.indexOf(u8, request.body, request.api_key) == null);
        if (self.cancelled) return error.Cancelled;
        return self.result orelse .{ .received = .{ .status = 200, .body = self.inference_body } };
    }
};
