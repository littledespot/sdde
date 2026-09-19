const std = @import("std");
const transport = @import("bedrock_transport.zig");
const lease = @import("../../ports/provider_authorization_lease.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Adapter = HttpAdapter(std.http.Client.request);

// Connection establishment is selected at compile time. Production always uses
// the standard HTTPS opener; tests can supply an in-memory connected stream
// without replacing HTTP serialization, response reads, or task ownership.
pub fn HttpAdapter(comptime open_request: fn (*std.http.Client, std.http.Method, std.Uri, std.http.Client.RequestOptions) std.http.Client.RequestError!std.http.Client.Request) type {
    return struct {
        const Self = @This();
        io: std.Io,
        clock: lease.Clock,
        runtime: pipeline.NodeRuntime,

        pub fn port(self: *Self) transport.Port {
            return .{ .context = @ptrCast(self), .exchange_fn = exchange };
        }

        fn exchange(context: *transport.Context, allocator: std.mem.Allocator, request: transport.Request) transport.Error!transport.Response {
            const self: *Self = @ptrCast(@alignCast(context));
            if (request.response_body_on_error) |slot| slot.* = null;
            var state: Exchange = .{ .body = .init(allocator) };
            defer state.body.deinit();
            // perform joins both tasks on every exit. Only then can the caller
            // observe or take ownership of bytes written by the network task.
            const result = self.perform(allocator, request, &state);
            const retained: ?transport.ResponseBody = if (state.body_started) .{
                // Transfer the arena allocation without copying or allocating,
                // including when the read itself failed for lack of memory.
                .bytes = state.body.toArrayList().items,
                .complete = state.body_complete,
            } else null;
            var response = result catch |err| {
                if (request.response_body_on_error) |slot| slot.* = retained;
                return err;
            };
            switch (response) {
                .received => |*received| received.body = retained.?.bytes,
                .failed => |*failure| failure.body = retained,
            }
            return response;
        }

        fn perform(self: *Self, allocator: std.mem.Allocator, request: transport.Request, state: *Exchange) transport.Error!transport.Response {
            switch (self.runtime.status()) {
                .cancelled => return error.Cancelled,
                .deadline_exhausted => return failed(.timeout, false, .preparing, .timeout),
                .active => {},
            }
            const now = self.clock.now() catch return failed(.transport_failed, false, .preparing, .unknown);
            if (now >= request.deadline_monotonic_ms) return failed(.timeout, false, .preparing, .timeout);
            const Event = union(enum) { network: transport.Error!void, timer: std.Io.Cancelable!void };
            var buffer: [2]Event = undefined;
            var tasks: std.Io.Select(Event) = .init(self.io, &buffer);
            defer tasks.cancelDiscard();
            tasks.concurrent(.network, fetch, .{ self, allocator, request, state }) catch return failed(.transport_failed, false, .preparing, .unknown);
            tasks.concurrent(.timer, sleep, .{ self.io, request.deadline_monotonic_ms - now }) catch {
                tasks.cancelDiscard();
                return failed(.transport_failed, state.sent, state.phase, .unknown);
            };
            const event = tasks.await() catch return error.Cancelled;
            switch (event) {
                .network => |finished| try finished,
                .timer => |finished| {
                    finished catch return error.Cancelled;
                    tasks.cancelDiscard();
                    return if (state.header_failure) |failure| .{ .failed = failure } else failed(.timeout, state.sent, state.phase, .timeout);
                },
            }
            return state.response;
        }

        fn sleep(io: std.Io, milliseconds: u64) std.Io.Cancelable!void {
            try io.sleep(.fromNanoseconds(@as(i96, milliseconds) * std.time.ns_per_ms), .awake);
        }

        fn fetch(self: *Self, allocator: std.mem.Allocator, request: transport.Request, state: *Exchange) transport.Error!void {
            self.send(allocator, request, state) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                if (err == error.Canceled) return error.Cancelled;
                state.response = if (state.header_failure) |failure| .{ .failed = failure } else failed(if (err == error.InvalidResponse) .response_invalid else .transport_failed, state.sent, state.phase, safeCause(err));
            };
        }

        fn send(self: *Self, allocator: std.mem.Allocator, input: transport.Request, state: *Exchange) !void {
            const url = try endpoint(allocator, input);
            const authorization = try std.fmt.allocPrint(allocator, "Bearer {s}", .{input.api_key});
            defer std.crypto.secureZero(u8, authorization);
            var client: std.http.Client = .{ .allocator = allocator, .io = self.io };
            defer client.deinit();
            // No environment initialization, proxy, endpoint override, redirect,
            // connection reuse, credential chain, or retry mechanism is installed.
            state.phase = .connecting;
            var request = try open_request(&client, .POST, try std.Uri.parse(url), .{
                .redirect_behavior = .unhandled,
                .keep_alive = false,
                .headers = .{
                    .authorization = .{ .override = authorization },
                    .content_type = .{ .override = "application/json" },
                    .accept_encoding = .{ .override = "identity" },
                },
            });
            defer request.deinit();
            request.transfer_encoding = .{ .content_length = input.body.len };
            state.phase = .sending;
            state.sent = true;
            sendBody(&request, input.body) catch return request.connection.?.stream_writer.err orelse error.WriteFailed;
            state.phase = .response_headers;
            var response: std.http.Client.Response = while (true) {
                const bytes = @import("bedrock_http_head.zig").receive(allocator, request.reader.in) catch |err| return switch (err) {
                    error.ReadFailed => request.connection.?.getReadError().?,
                    else => err,
                };
                const head = std.http.Client.Response.Head.parse(bytes) catch return error.InvalidResponse;
                if (head.status == .@"continue") continue;
                request.reader.state = .received_head;
                request.response_transfer_encoding = head.transfer_encoding;
                request.response_content_length = head.content_length;
                request.connection.?.closing = true;
                break .{ .request = &request, .head = head };
            };
            if (response.head.status.class() == .redirect) {
                state.header_failure = .{ .cause = .response_invalid, .retry_class = .never, .delivery = .response_received, .diagnostic = .{ .phase = .response_headers, .cause = .malformed_response } };
            }
            if (response.head.content_encoding != .identity) state.rejectHead();
            var exception: ?[]const u8 = null;
            var request_id: ?[]const u8 = null;
            var headers = response.head.iterateHeaders();
            while (headers.next()) |header| {
                if (std.ascii.eqlIgnoreCase(header.name, "x-amzn-errortype")) {
                    if (exception != null) state.rejectHead() else exception = try allocator.dupe(u8, header.value);
                }
                if (std.ascii.eqlIgnoreCase(header.name, "x-amzn-requestid")) {
                    if (request_id != null) state.rejectHead() else request_id = try allocator.dupe(u8, header.value);
                }
            }
            state.phase = .response_body;
            state.body_started = true;
            var buffer: [4096]u8 = undefined;
            // reader removes HTTP transfer framing only. A rejected content
            // encoding is retained exactly as sent, never decompressed.
            const reader = response.reader(&buffer);
            _ = reader.streamRemaining(&state.body.writer) catch |err| switch (err) {
                error.ReadFailed => {
                    if (response.bodyErr()) |framing_error| return framing_error;
                    return request.connection.?.getReadError().?;
                },
                error.WriteFailed => return error.OutOfMemory,
            };
            // The standard content-length reader also reports underlying EOF as
            // EndOfStream. Only its terminal state proves that the frame ended.
            switch (request.reader.state) {
                .ready, .body_none => {},
                else => return error.EndOfStream,
            }
            state.body_complete = true;
            state.response = if (state.header_failure) |failure| .{ .failed = failure } else .{ .received = .{ .status = @intFromEnum(response.head.status), .exception = exception, .request_id = request_id, .body = "" } };
        }
    };
}

fn sendBody(request: *std.http.Client.Request, body: []const u8) std.Io.Writer.Error!void {
    var outgoing = try request.sendBodyUnflushed(&.{});
    try outgoing.writer.writeAll(body);
    try outgoing.end();
    try request.connection.?.flush();
}

const Diagnostic = @import("../../domain/llm_provider_operation.zig").TransportDiagnostic;
const Exchange = struct {
    phase: @FieldType(Diagnostic, "phase") = .preparing,
    sent: bool = false,
    body: std.Io.Writer.Allocating,
    body_started: bool = false,
    body_complete: bool = false,
    header_failure: ?transport.Failure = null,
    response: transport.Response = .{ .failed = .{ .cause = .transport_failed, .retry_class = .policy_eligible, .delivery = .not_sent } },

    fn rejectHead(self: *Exchange) void {
        if (self.header_failure == null) self.header_failure = failed(.response_invalid, self.sent, .response_headers, .malformed_response).failed;
    }
};

fn failed(cause: @import("../../domain/llm_provider_operation.zig").ProviderFailureCause, sent: bool, phase: @FieldType(Diagnostic, "phase"), cause_detail: @FieldType(Diagnostic, "cause")) transport.Response {
    return .{ .failed = .{ .cause = cause, .retry_class = if (cause == .response_invalid) .never else .policy_eligible, .delivery = if (sent) .accepted_or_unknown else .not_sent, .diagnostic = .{ .phase = phase, .cause = cause_detail } } };
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

// Classify only errors actually reported by the transport; unknown failures
// never imply a DNS, TLS or sandbox diagnosis.
fn safeCause(err: anyerror) @FieldType(Diagnostic, "cause") {
    return switch (err) {
        error.UnknownHostName, error.NameServerFailure, error.NameServerUnavailable => .name_resolution,
        error.ConnectionRefused => .connection_refused,
        error.ConnectionResetByPeer => .connection_reset,
        error.TlsInitializationFailed, error.TlsFailure, error.CertificateBundleLoadFailure => .tls,
        error.Timeout, error.ConnectionTimedOut => .timeout,
        error.InvalidResponse => .malformed_response,
        error.EndOfStream => .premature_eof,
        error.ReadFailed => .read,
        error.WriteFailed => .write,
        else => .unknown,
    };
}
