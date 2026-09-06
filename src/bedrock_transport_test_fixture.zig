const std = @import("std");
const transport = @import("adapters/provider/bedrock_transport.zig");

pub const complete = "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"{}\"}]}},\"stopReason\":\"end_turn\",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12},\"metrics\":{\"latencyMs\":1}}";

pub const Wire = struct {
    calls: usize = 0,
    result: ?transport.Response = null,
    cancelled: bool = false,
    inference_body: []const u8 = complete,

    pub fn port(self: *Wire) transport.Port {
        return .{ .context = @ptrCast(self), .exchange_fn = exchange };
    }
    fn exchange(context: *transport.Context, _: std.mem.Allocator, request: transport.Request) transport.Error!transport.Response {
        const self: *Wire = @ptrCast(@alignCast(context));
        self.calls += 1;
        std.debug.assert(request.api_key.len != 0);
        std.debug.assert(std.mem.indexOf(u8, request.body, request.api_key) == null);
        if (self.cancelled) return error.Cancelled;
        return self.result orelse .{ .received = .{ .status = 200, .body = if (request.kind == .input_token_count) "{\"inputTokens\":10}" else self.inference_body } };
    }
};
