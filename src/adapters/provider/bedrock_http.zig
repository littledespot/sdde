const std = @import("std");
const transport = @import("bedrock_transport.zig");
const lease = @import("../../ports/provider_authorization_lease.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Adapter = struct {
    io: std.Io,
    clock: lease.Clock,
    runtime: pipeline.NodeRuntime,

    pub fn port(self: *Adapter) transport.Port {
        return .{ .context = @ptrCast(self), .exchange_fn = exchange };
    }

    fn exchange(context: *transport.Context, allocator: std.mem.Allocator, request: transport.Request) transport.Error!transport.Response {
        const self: *Adapter = @ptrCast(@alignCast(context));
        switch (self.runtime.status()) {
            .cancelled => return error.Cancelled,
            .deadline_exhausted => return failed(.timeout, false),
            .active => {},
        }
        const now = self.clock.now() catch return failed(.transport_failed, false);
        if (now >= request.deadline_monotonic_ms) return failed(.timeout, false);
        var state: Exchange = .{};
        const Event = union(enum) { network: transport.Error!void, timer: std.Io.Cancelable!void };
        var buffer: [2]Event = undefined;
        var tasks: std.Io.Select(Event) = .init(self.io, &buffer);
        defer tasks.cancelDiscard();
        tasks.concurrent(.network, fetch, .{ self, allocator, request, &state }) catch return failed(.transport_failed, false);
        tasks.concurrent(.timer, sleep, .{ self.io, request.deadline_monotonic_ms - now }) catch {
            tasks.cancelDiscard();
            return failed(.transport_failed, state.sent);
        };
        const event = tasks.await() catch return error.Cancelled;
        switch (event) {
            .network => |finished| try finished,
            .timer => |finished| {
                finished catch return error.Cancelled;
                tasks.cancelDiscard();
                return failed(.timeout, state.sent);
            },
        }
        return state.response;
    }

    fn sleep(io: std.Io, milliseconds: u64) std.Io.Cancelable!void {
        try io.sleep(.fromNanoseconds(@as(i96, milliseconds) * std.time.ns_per_ms), .awake);
    }

    fn fetch(self: *Adapter, allocator: std.mem.Allocator, request: transport.Request, state: *Exchange) transport.Error!void {
        self.send(allocator, request, state) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            if (err == error.Canceled) return error.Cancelled;
            state.response = failed(if (err == error.InvalidResponse) .response_invalid else .transport_failed, state.sent);
        };
    }

    fn send(self: *Adapter, allocator: std.mem.Allocator, input: transport.Request, state: *Exchange) !void {
        const url = try endpoint(allocator, input);
        const authorization = try std.fmt.allocPrint(allocator, "Bearer {s}", .{input.api_key});
        defer std.crypto.secureZero(u8, authorization);
        var client: std.http.Client = .{ .allocator = allocator, .io = self.io };
        defer client.deinit();
        // No environment initialization, proxy, endpoint override, redirect,
        // connection reuse, credential chain, or retry mechanism is installed.
        var request = try client.request(.POST, try std.Uri.parse(url), .{
            .redirect_behavior = .unhandled,
            .keep_alive = false,
            .headers = .{
                .content_type = .{ .override = "application/json" },
                .accept_encoding = .{ .override = "identity" },
            },
            .privileged_headers = &.{.{ .name = "Authorization", .value = authorization }},
        });
        defer request.deinit();
        request.transfer_encoding = .{ .content_length = input.body.len };
        state.sent = true;
        var outgoing = try request.sendBodyUnflushed(&.{});
        try outgoing.writer.writeAll(input.body);
        try outgoing.end();
        try request.connection.?.flush();
        var response: std.http.Client.Response = while (true) {
            const bytes = try @import("bedrock_http_head.zig").receive(allocator, request.reader.in);
            const head = std.http.Client.Response.Head.parse(bytes) catch return error.InvalidResponse;
            if (head.status == .@"continue") continue;
            request.reader.state = .received_head;
            request.response_transfer_encoding = head.transfer_encoding;
            request.response_content_length = head.content_length;
            request.connection.?.closing = true;
            break .{ .request = &request, .head = head };
        };
        if (response.head.status.class() == .redirect) {
            state.response = .{ .failed = .{ .cause = .response_invalid, .retry_class = .never, .delivery = .response_received } };
            return;
        }
        if (response.head.content_encoding != .identity) return error.InvalidResponse;
        var exception: ?[]const u8 = null;
        var headers = response.head.iterateHeaders();
        while (headers.next()) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "x-amzn-errortype")) {
                if (exception != null) return error.InvalidResponse;
                exception = try allocator.dupe(u8, header.value);
            }
        }
        var bytes: std.Io.Writer.Allocating = .init(allocator);
        defer bytes.deinit();
        var buffer: [4096]u8 = undefined;
        const reader = response.reader(&buffer);
        _ = reader.streamRemaining(&bytes.writer) catch |err| switch (err) {
            error.ReadFailed => return response.bodyErr().?,
            error.WriteFailed => return error.OutOfMemory,
        };
        state.response = .{ .received = .{ .status = @intFromEnum(response.head.status), .exception = exception, .body = try bytes.toOwnedSlice() } };
    }
};

const Exchange = struct {
    sent: bool = false,
    response: transport.Response = .{ .failed = .{ .cause = .transport_failed, .retry_class = .policy_eligible, .delivery = .not_sent } },
};

fn failed(cause: @import("../../domain/llm_provider_operation.zig").ProviderFailureCause, sent: bool) transport.Response {
    return .{ .failed = .{ .cause = cause, .retry_class = if (cause == .response_invalid) .never else .policy_eligible, .delivery = if (sent) .accepted_or_unknown else .not_sent } };
}

pub fn endpoint(allocator: std.mem.Allocator, request: transport.Request) std.mem.Allocator.Error![]const u8 {
    var encoded: std.Io.Writer.Allocating = .init(allocator);
    defer encoded.deinit();
    for (request.model.bytes) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or byte == '.' or byte == '~') {
            encoded.writer.writeByte(byte) catch return error.OutOfMemory;
        } else {
            encoded.writer.print("%{X:0>2}", .{byte}) catch return error.OutOfMemory;
        }
    }
    // Region is a closed enum, not a user-supplied host or URL string.
    return std.fmt.allocPrint(allocator, "https://bedrock-runtime.{s}.amazonaws.com/model/{s}/{s}", .{
        @tagName(request.region), encoded.written(), if (request.kind == .inference) "converse" else "count-tokens",
    });
}
