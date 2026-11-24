//! Native HTTPS adapter, restricted to one OpenAI endpoint with no redirects.
const std = @import("std");
const wire = @import("openai.zig");
const provider = @import("provider.zig");
const contracts = @import("contracts.zig");
const reports = @import("report.zig");
pub const Adapter = struct {
    io: std.Io,
    api_key: []const u8,
    pub fn port(self: *Adapter) provider.Port {
        return .{ .context = @ptrCast(self), .invoke_fn = invoke };
    }
    fn invoke(context: *provider.Context, a: std.mem.Allocator, body: []const u8, timeout_ms: u32) provider.Error!provider.Observation {
        const self: *Adapter = @ptrCast(@alignCast(context));
        if (!validKey(self.api_key)) return .{ .failure = .authentication };
        var result: provider.Observation = .{ .failure = .timeout };
        const Event = union(enum) { network: provider.Error!void, timer: std.Io.Cancelable!void };
        var buffer: [2]Event = undefined;
        var selection: std.Io.Select(Event) = .init(self.io, &buffer);
        // Network allocations belong to the caller's arena; both tasks are
        // joined before it can be released. The timer never uses the allocator.
        defer selection.cancelDiscard();
        selection.concurrent(.network, fetch, .{ self, a, body, &result }) catch return .{ .failure = .provider_failed };
        selection.concurrent(.timer, sleep, .{ self.io, timeout_ms }) catch {
            selection.cancelDiscard();
            result.failure = .provider_failed;
            result.payload = null;
            return result;
        };
        const event = selection.await() catch {
            selection.cancelDiscard();
            result.failure = .cancelled;
            result.payload = null;
            return result;
        };
        switch (event) {
            .network => |finished| try finished,
            .timer => |finished| {
                finished catch return error.Cancelled;
                // Join first; a completion racing the deadline must not replace
                // the timeout disposition returned by this invocation.
                selection.cancelDiscard();
                result.failure = .timeout;
                result.payload = null;
            },
        }
        return result;
    }
    fn sleep(io: std.Io, timeout_ms: u32) std.Io.Cancelable!void {
        try io.sleep(.fromMilliseconds(timeout_ms), .awake);
    }
    fn fetch(self: *Adapter, a: std.mem.Allocator, body: []const u8, result: *provider.Observation) provider.Error!void {
        exchange(self, a, body, result) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            result.failure = switch (err) {
                error.Canceled => .cancelled,
                error.InvalidEvaluationContract => .invalid_response,
                else => .provider_failed,
            };
            result.payload = null;
        };
    }
    fn exchange(self: *Adapter, a: std.mem.Allocator, body: []const u8, result: *provider.Observation) !void {
        const authorization = try std.fmt.allocPrint(a, "Bearer {s}", .{self.api_key});
        defer {
            std.crypto.secureZero(u8, authorization);
            a.free(authorization);
        }
        var client: std.http.Client = .{ .allocator = a, .io = self.io };
        defer client.deinit();
        var request = try @import("../../src/adapters/provider/native_model_http.zig").request(&client, .POST, comptime std.Uri.parse("https://api.openai.com/v1/responses") catch unreachable, .{
            .redirect_behavior = .unhandled,
            .keep_alive = false,
            .headers = .{
                .content_type = .{ .override = "application/json" },
                .accept_encoding = .{ .override = "identity" },
            },
            .privileged_headers = &.{.{ .name = "Authorization", .value = authorization }},
        });
        defer request.deinit();
        request.transfer_encoding = .{ .content_length = body.len };
        var outgoing = try request.sendBodyUnflushed(&.{});
        try outgoing.writer.writeAll(body);
        try outgoing.end();
        try request.connection.?.flush();
        var response = try request.receiveHead(&.{});
        var headers = response.head.iterateHeaders();
        while (headers.next()) |header| if (std.ascii.eqlIgnoreCase(header.name, "x-request-id")) {
            if (result.request_id != null or !contracts.id(header.value)) return error.InvalidEvaluationContract;
            result.request_id = try a.dupe(u8, header.value);
        };
        const status_failure = statusFailure(@intFromEnum(response.head.status));
        result.failure = status_failure;
        if (response.head.content_encoding != .identity) return error.InvalidEvaluationContract;
        var transfer_buffer: [4096]u8 = undefined;
        const received = try drain(a, response.reader(&transfer_buffer), &request.reader.state);
        result.response_body = received;
        // A body that is not complete keeps the bytes that arrived; the failure is the framing's or the
        // connection's, and an EOF the framing didn't expect is an end of stream, as in the engine's exchange.
        if (!received.complete) {
            if (response.bodyErr()) |framing_error| return framing_error;
            if (request.connection.?.getReadError()) |read_error| return read_error;
            return error.EndOfStream;
        }
        if (status_failure != null) return;
        const request_id = result.request_id;
        result.* = try wire.response(a, received.bytes);
        result.response_body = received;
        result.request_id = request_id;
    }
};
/// Reads a response body to its end, with the bytes that did arrive. It is complete only if the read ended and the
/// HTTP framing ended with it: the standard content-length reader reports an underlying EOF as an ordinary end of
/// stream, so only its terminal state `framing` proves the body arrived whole (the engine's exchange does the same).
pub fn drain(a: std.mem.Allocator, reader: *std.Io.Reader, framing: *const std.http.Reader.State) error{OutOfMemory}!provider.Body {
    var bytes: std.Io.Writer.Allocating = .init(a);
    defer bytes.deinit();
    const ended = if (reader.streamRemaining(&bytes.writer)) |_| true else |err| switch (err) {
        error.ReadFailed => false,
        // The allocating writer fails only for lack of memory.
        error.WriteFailed => return error.OutOfMemory,
    };
    const framed = switch (framing.*) {
        .ready, .body_none => true,
        else => false,
    };
    return .{ .bytes = try a.dupe(u8, bytes.written()), .complete = ended and framed };
}
pub fn statusFailure(status: u16) ?provider.Failure {
    return switch (status) {
        200 => null,
        401, 403 => .authentication,
        429 => .rate_limited,
        400, 404, 422 => .configuration,
        else => .provider_failed,
    };
}
pub fn validKey(key: []const u8) bool {
    if (key.len == 0) return false;
    for (key) |byte| if (byte <= 32 or byte >= 127) return false;
    return true;
}
