//! Loopback-only HTTP adapter; no filesystem, workflow or provider access.
const std = @import("std");
const session_port = @import("../../ports/request_debugger_session.zig");
const debug = @import("../../domain/request_debugger.zig");
pub const Server = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    session: session_port.Session,

    pub fn serve(self: Server) !void {
        const address: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
        var listener = try address.listen(self.io, .{});
        defer listener.deinit(self.io);
        var random: [16]u8 = undefined;
        self.io.random(&random);
        const token = std.fmt.bytesToHex(random, .lower);
        const origin = try std.fmt.allocPrint(self.allocator, "http://127.0.0.1:{d}", .{listener.socket.address.getPort()});
        defer self.allocator.free(origin);
        const message = try std.fmt.allocPrint(self.allocator, "LLM request debugger: {s}/#{s}\nReplay runs one selected prompt. Press Ctrl-C to stop.\n", .{ origin, token });
        defer self.allocator.free(message);
        try std.Io.File.stdout().writeStreamingAll(self.io, message);
        while (true) {
            const stream = try listener.accept(self.io);
            defer stream.close(self.io);
            self.connection(stream, origin, &token) catch |err| {
                if (err == error.Canceled) return err;
                // A bad/disconnected HTTP client does not alter diagnostic state.
                const line = try std.fmt.allocPrint(self.allocator, "Debugger HTTP connection failed: {s}\n", .{@errorName(err)});
                defer self.allocator.free(line);
                try std.Io.File.stderr().writeStreamingAll(self.io, line);
            };
        }
    }
    fn connection(self: Server, stream: std.Io.net.Stream, origin: []const u8, token: []const u8) !void {
        var input_buffer: [8192]u8 = undefined;
        var output_buffer: [8192]u8 = undefined;
        var reader = stream.reader(self.io, &input_buffer);
        var writer = stream.writer(self.io, &output_buffer);
        var http = std.http.Server.init(&reader.interface, &writer.interface);
        var request = try http.receiveHead();
        const target = request.head.target;
        var host: ?[]const u8 = null;
        var supplied_origin: ?[]const u8 = null;
        var supplied_token: ?[]const u8 = null;
        var content_type: ?[]const u8 = null;
        var headers = request.iterateHeaders();
        while (headers.next()) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "host")) {
                if (host != null) return respond(&request, .bad_request, "text/plain", "Duplicate Host");
                host = header.value;
            }
            if (std.ascii.eqlIgnoreCase(header.name, "origin")) {
                if (supplied_origin != null) return respond(&request, .bad_request, "text/plain", "Duplicate Origin");
                supplied_origin = header.value;
            }
            if (std.ascii.eqlIgnoreCase(header.name, "x-sdde-debugger-token")) {
                if (supplied_token != null) return respond(&request, .bad_request, "text/plain", "Duplicate token");
                supplied_token = header.value;
            }
            if (std.ascii.eqlIgnoreCase(header.name, "content-type")) content_type = header.value;
        }
        if (!std.mem.eql(u8, host orelse "", origin["http://".len..])) return respond(&request, .forbidden, "text/plain", "Invalid host");
        if (request.head.method == .GET) {
            if (std.mem.eql(u8, target, "/")) return respond(&request, .ok, "text/html; charset=utf-8", @embedFile("../../debugger/index.html"));
            if (std.mem.eql(u8, target, "/app.js")) return respond(&request, .ok, "application/javascript", @embedFile("../../debugger/app.js"));
            if (std.mem.eql(u8, target, "/style.css")) return respond(&request, .ok, "text/css", @embedFile("../../debugger/style.css"));
        }
        if (!authorized(token, supplied_token, origin, supplied_origin, request.head.method == .POST)) return respond(&request, .forbidden, "text/plain", "Open the debugger using its printed session link.");
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const calls = if (request.head.method == .GET and std.mem.eql(u8, target, "/api/calls"))
            self.session.list_fn(self.session.context, a)
        else if (request.head.method == .POST and std.mem.eql(u8, target, "/api/replay")) replay: {
            if (!std.mem.eql(u8, content_type orelse "", "application/json")) return respond(&request, .bad_request, "text/plain", "Expected application/json");
            var body_buffer: [4096]u8 = undefined;
            const body_reader = try request.readerExpectContinue(&body_buffer);
            const bytes = try body_reader.allocRemaining(a, .unlimited);
            const input = debug.ReplayInput.decode(a, bytes) catch return respond(&request, .bad_request, "text/plain", "Invalid replay request");
            break :replay self.session.replay_fn(self.session.context, a, input);
        } else return respond(&request, .not_found, "text/plain", "Not found");
        const result = calls catch |err| return respond(&request, .bad_request, "text/plain", @errorName(err));
        return respond(&request, .ok, "application/json", try std.json.Stringify.valueAlloc(a, result, .{}));
    }
};
pub fn authorized(token: []const u8, supplied: ?[]const u8, origin: []const u8, supplied_origin: ?[]const u8, post: bool) bool {
    if (!std.mem.eql(u8, token, supplied orelse return false)) return false;
    if (supplied_origin) |value| return std.mem.eql(u8, value, origin);
    return !post;
}
fn respond(request: *std.http.Server.Request, status: std.http.Status, content_type: []const u8, bytes: []const u8) !void {
    try request.respond(bytes, .{ .status = status, .keep_alive = false, .extra_headers = &.{
        .{ .name = "content-type", .value = content_type },
        .{ .name = "cache-control", .value = "no-store" },
        .{ .name = "x-content-type-options", .value = "nosniff" },
        .{ .name = "referrer-policy", .value = "no-referrer" },
        .{ .name = "content-security-policy", .value = "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'" },
    } });
}
