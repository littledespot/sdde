//! In-memory sockets and event-driven faults below the concrete HTTP adapter.
//! All filesystem, process, DNS and real network operations remain disabled.
const std = @import("std");
const http = @import("adapters/provider/bedrock_http.zig");
const transport = @import("adapters/provider/bedrock_transport.zig");
const lease = @import("ports/provider_authorization_lease.zig");

pub const Adapter = http.HttpAdapter(openRequest);
pub const Point = enum { connect, write, head, body };
pub const Fault = enum { none, reset, eof, cancelled, deadline, held };

pub const Fixture = struct {
    threaded: std.Io.Threaded,
    vtable: std.Io.VTable,
    response: []const u8,
    expected_host: []const u8 = "bedrock-runtime.ap-southeast-2.amazonaws.com",
    point: Point = .body,
    fault: Fault = .none,
    finish_after_cancel: bool = false,
    maximum_read: usize = 7,
    maximum_write: usize = 13,
    cursor: usize = 0,
    body_start: usize,
    fault_fired: bool = false,
    wire: std.ArrayList(u8) = .empty,
    canary: [48]u8,
    connects: usize = 0,
    opens: usize = 0,
    closes: usize = 0,
    fail_spawn: ?usize = null,
    spawns: usize = 0,
    active_socket_calls: std.atomic.Value(usize) = .init(0),
    active_timers: std.atomic.Value(usize) = .init(0),
    timer_cancellations: std.atomic.Value(usize) = .init(0),
    socket_cancellations: std.atomic.Value(usize) = .init(0),
    now_ms: std.atomic.Value(u64) = .init(1000),
    reached: std.Io.Event = .unset,
    never: std.Io.Event = .unset,

    pub fn init(self: *Fixture, response: []const u8) void {
        self.* = .{
            .threaded = .init(std.testing.allocator, .{}),
            .vtable = std.Io.failing.vtable.*,
            .response = response,
            .body_start = (std.mem.indexOf(u8, response, "\r\n\r\n") orelse @panic("fixture needs HTTP head")) + 4,
            .canary = undefined,
        };
        // Only scheduling/synchronization use the actual I/O implementation.
        const real = self.threaded.io().vtable;
        inline for (.{ "async", "concurrent", "await", "cancel", "groupAsync", "groupConcurrent", "groupAwait", "groupCancel", "recancel", "swapCancelProtection", "checkCancel", "futexWait", "futexWaitUncancelable", "futexWake", "now" }) |name| {
            @field(self.vtable, name) = @field(real.*, name);
        }
        self.vtable.netConnectIp = connect;
        self.vtable.netLookup = lookup;
        self.vtable.netRead = read;
        self.vtable.netWrite = write;
        self.vtable.netClose = close;
        self.vtable.sleep = sleep;
        self.vtable.groupConcurrent = spawn;
        std.testing.io.random(&self.canary);
        for (&self.canary) |*byte| byte.* = 'A' + byte.* % 26;
    }

    pub fn deinit(self: *Fixture) void {
        self.threaded.deinit();
        std.crypto.secureZero(u8, &self.canary);
        std.crypto.secureZero(u8, self.wire.items);
        self.wire.deinit(std.testing.allocator);
    }

    pub fn io(self: *Fixture) std.Io {
        return .{ .userdata = &self.threaded, .vtable = &self.vtable };
    }

    pub fn adapter(self: *Fixture) Adapter {
        return .{ .io = self.io(), .clock = .{ .context = @ptrCast(self), .now_fn = now }, .runtime = .{} };
    }

    pub fn request(self: *const Fixture, kind: @import("domain/llm_provider_operation.zig").ProviderOperationKind) transport.Request {
        return .{ .region = .@"ap-southeast-2", .model = .{ .bytes = "openai.gpt-oss-20b-1:0" }, .kind = kind, .body = "{\"messages\":[]}", .api_key = &self.canary, .deadline_monotonic_ms = 1100 };
    }

    pub fn expectJoined(self: *const Fixture) !void {
        try self.expectCleaned();
        try std.testing.expectEqual(@as(usize, 1), self.connects);
        try std.testing.expectEqual(@as(usize, if (self.fault == .deadline) 0 else 1), self.timer_cancellations.load(.acquire));
    }

    pub fn expectCleaned(self: *const Fixture) !void {
        try std.testing.expectEqual(@as(usize, 0), self.active_socket_calls.load(.acquire));
        try std.testing.expectEqual(@as(usize, 0), self.active_timers.load(.acquire));
        try std.testing.expectEqual(self.opens, self.closes);
        try std.testing.expect(self.connects <= 1);
        try std.testing.expect(std.mem.count(u8, self.wire.items, "POST ") <= 1);
    }

    fn cast(context: ?*anyopaque) *Fixture {
        const threaded: *std.Io.Threaded = @ptrCast(@alignCast(context.?));
        return @fieldParentPtr("threaded", threaded);
    }

    fn now(context: *lease.Context) error{ClockUnavailable}!u64 {
        const self: *Fixture = @ptrCast(@alignCast(context));
        return self.now_ms.load(.acquire);
    }

    fn interrupt(self: *Fixture, point: Point) error{Canceled}!bool {
        if (self.fault == .none or self.fault_fired or self.point != point) return false;
        self.fault_fired = true;
        self.reached.set(self.io());
        switch (self.fault) {
            .none => unreachable,
            .reset, .eof => return true,
            .cancelled => return error.Canceled,
            .deadline, .held => {
                self.never.wait(self.io()) catch |err| {
                    _ = self.socket_cancellations.fetchAdd(1, .release);
                    // A buffered read can complete while cancellation is being
                    // joined. This deliberately exercises that losing result.
                    if (self.finish_after_cancel) return false;
                    return err;
                };
                unreachable;
            },
        }
    }

    fn connect(context: ?*anyopaque, address: *const std.Io.net.IpAddress, _: std.Io.net.IpAddress.ConnectOptions) std.Io.net.IpAddress.ConnectError!std.Io.net.Socket {
        const self = cast(context);
        self.opens += 1;
        return .{ .handle = 41, .address = address.* };
    }

    fn lookup(context: ?*anyopaque, host: std.Io.net.HostName, resolved: *std.Io.Queue(std.Io.net.HostName.LookupResult), options: std.Io.net.HostName.LookupOptions) std.Io.net.HostName.LookupError!void {
        const self = cast(context);
        defer resolved.close(self.io());
        std.debug.assert(std.mem.eql(u8, host.bytes, self.expected_host));
        resolved.putOne(self.io(), .{ .address = .{ .ip4 = .loopback(options.port) } }) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            error.Closed => unreachable,
        };
    }

    fn read(context: ?*anyopaque, handle: std.Io.net.Socket.Handle, buffers: [][]u8) std.Io.net.Stream.Reader.Error!usize {
        const self = cast(context);
        std.debug.assert(handle == 41 and self.opens > self.closes);
        _ = self.active_socket_calls.fetchAdd(1, .acq_rel);
        defer _ = self.active_socket_calls.fetchSub(1, .release);
        // Expose part of the body before its fault, even with a large read buffer.
        const point: Point = if (self.cursor < self.body_start + 1) .head else .body;
        if (self.cursor > 0 and try self.interrupt(point)) return if (self.fault == .eof) 0 else error.ConnectionResetByPeer;
        if (self.cursor == self.response.len) return 0;
        const boundary = if (self.cursor < self.body_start + 1) @min(self.body_start + 1, self.response.len) else self.response.len;
        const n = @min(buffers[0].len, self.maximum_read, boundary - self.cursor);
        @memcpy(buffers[0][0..n], self.response[self.cursor..][0..n]);
        self.cursor += n;
        return n;
    }

    fn write(context: ?*anyopaque, handle: std.Io.net.Socket.Handle, header: []const u8, buffers: []const []const u8, splat: usize) std.Io.net.Stream.Writer.Error!usize {
        const self = cast(context);
        std.debug.assert(handle == 41 and self.opens > self.closes);
        _ = self.active_socket_calls.fetchAdd(1, .acq_rel);
        defer _ = self.active_socket_calls.fetchSub(1, .release);
        // Fail after at least one partial write, not merely before transmission.
        if (self.wire.items.len > 0 and try self.interrupt(.write)) return error.ConnectionResetByPeer;
        const bytes = if (header.len > 0) header else first: {
            for (buffers, 0..) |buffer, index| {
                if (index == buffers.len - 1 and splat == 0) break;
                if (buffer.len > 0) break :first buffer;
            }
            return 0;
        };
        const n = @min(bytes.len, self.maximum_write);
        self.wire.appendSlice(std.testing.allocator, bytes[0..n]) catch return error.SystemResources;
        return n;
    }

    fn close(context: ?*anyopaque, handles: []const std.Io.net.Socket.Handle) void {
        const self = cast(context);
        for (handles) |handle| {
            std.debug.assert(handle == 41 and self.opens > self.closes);
            self.closes += 1;
        }
    }

    fn sleep(context: ?*anyopaque, timeout: std.Io.Timeout) std.Io.Cancelable!void {
        const self = cast(context);
        _ = self.active_timers.fetchAdd(1, .acq_rel);
        defer _ = self.active_timers.fetchSub(1, .release);
        std.debug.assert(timeout.duration.raw.toNanoseconds() == 100 * std.time.ns_per_ms);
        if (self.fault == .deadline) {
            try self.reached.wait(self.io());
            self.now_ms.store(1100, .release);
            return;
        }
        self.never.wait(self.io()) catch |err| {
            _ = self.timer_cancellations.fetchAdd(1, .release);
            return err;
        };
        unreachable;
    }

    fn spawn(context: ?*anyopaque, group: *std.Io.Group, arguments: []const u8, alignment: std.mem.Alignment, start: *const fn (*const anyopaque) void) std.Io.ConcurrentError!void {
        const self = cast(context);
        self.spawns += 1;
        if (self.fail_spawn == self.spawns) {
            // Refuse the timer only once a partial HTTP read is actually held.
            if (self.spawns == 2) self.reached.waitUncancelable(self.io());
            return error.ConcurrencyUnavailable;
        }
        return self.threaded.io().vtable.groupConcurrent(context, group, arguments, alignment, start);
    }
};

fn openRequest(client: *std.http.Client, method: std.http.Method, uri: std.Uri, options: std.http.Client.RequestOptions) std.http.Client.RequestError!std.http.Client.Request {
    const fixture = Fixture.cast(client.io.userdata);
    fixture.connects += 1;
    _ = fixture.active_socket_calls.fetchAdd(1, .acq_rel);
    defer _ = fixture.active_socket_calls.fetchSub(1, .release);
    if (try fixture.interrupt(.connect)) return error.ConnectionRefused;
    std.debug.assert(method == .POST and std.mem.eql(u8, uri.scheme, "https"));
    std.debug.assert(options.redirect_behavior == .unhandled and !options.keep_alive);
    // A synthetic already-connected stream requires no certificate-store read.
    // Production uses std.http.Client.request directly, retaining system TLS trust.
    client.now = .fromNanoseconds(0);
    var connected = options;
    var host_buffer: [std.Io.net.HostName.max_len]u8 = undefined;
    connected.connection = try client.connectTcp(try uri.getHost(&host_buffer), 443, .plain);
    return client.request(method, uri, connected);
}
