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
    fn invoke(context: *provider.Context, a: std.mem.Allocator, body: []const u8, timeout_ms: u32) provider.Error!wire.Observation {
        const self: *Adapter = @ptrCast(@alignCast(context));
        if (!validKey(self.api_key)) return .{ .failure = .authentication };
        var result: wire.Observation = .{ .failure = .timeout };
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
    fn fetch(self: *Adapter, a: std.mem.Allocator, body: []const u8, result: *wire.Observation) provider.Error!void {
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
    fn exchange(self: *Adapter, a: std.mem.Allocator, body: []const u8, result: *wire.Observation) !void {
        const authorization = try std.fmt.allocPrint(a, "Bearer {s}", .{self.api_key});
        defer {
            std.crypto.secureZero(u8, authorization);
            a.free(authorization);
        }
        var client: std.http.Client = .{ .allocator = a, .io = self.io };
        defer client.deinit();
        var request = try client.request(.POST, comptime std.Uri.parse("https://api.openai.com/v1/responses") catch unreachable, .{
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
        if (statusFailure(@intFromEnum(response.head.status))) |failure| {
            result.failure = failure;
            // Error bodies and credentials are not copied into reports.
            return;
        }
        if (response.head.content_encoding != .identity) return error.InvalidEvaluationContract;
        var bytes: std.Io.Writer.Allocating = .init(a);
        defer bytes.deinit();
        var transfer_buffer: [4096]u8 = undefined;
        const reader = response.reader(&transfer_buffer);
        _ = reader.streamRemaining(&bytes.writer) catch |err| switch (err) {
            error.ReadFailed => return response.bodyErr().?,
            else => return err,
        };
        const request_id = result.request_id;
        result.* = try wire.response(a, bytes.written());
        result.request_id = request_id;
    }
};
pub fn statusFailure(status: u16) ?reports.Failure {
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
