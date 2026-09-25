//! The single native connection boundary for model-provider HTTP requests.
const std = @import("std");
const builtin = @import("builtin");

pub const RequestError = std.http.Client.RequestError || error{LiveModelCallsDisabled};

const enabled = if (builtin.is_test) false else @import("root").live_model_connections;

pub fn request(client: *std.http.Client, method: std.http.Method, uri: std.Uri, options: std.http.Client.RequestOptions) RequestError!std.http.Client.Request {
    // Compile the network call out of every test executable, independently of
    // credentials, endpoint, request kind, or the caller's provider wiring.
    if (!enabled) return error.LiveModelCallsDisabled;
    return client.request(method, uri, options);
}

test "native model connections are denied before I/O for every provider endpoint" {
    var client: std.http.Client = .{ .allocator = std.testing.allocator, .io = .failing };
    defer client.deinit();
    for ([_][]const u8{
        "https://bedrock-runtime.ap-southeast-2.amazonaws.com/model/example/invoke",
        "https://bedrock-runtime.us-east-1.amazonaws.com/model/example/count-tokens",
        "https://api.openai.com/v1/responses",
        "https://unrelated.invalid/model",
    }) |endpoint| {
        try std.testing.expectError(error.LiveModelCallsDisabled, request(&client, .POST, try std.Uri.parse(endpoint), .{
            .headers = .{ .authorization = .{ .override = "Bearer test-credential" } },
        }));
    }
}
