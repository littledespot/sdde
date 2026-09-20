//! Offline packaged-executable probe. No provider credentials or API dispatch.
const std = @import("std");
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, a);
    _ = args.skip();
    const binary = args.next() orelse return error.MissingExecutable;
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    var child = try std.process.spawn(init.io, .{ .argv = &.{ binary, "--debugger", "debugger-fixture" }, .environ_map = &environment, .stdin = .ignore, .stdout = .pipe });
    defer child.kill(init.io);
    var buffer: [1024]u8 = undefined;
    var reader = child.stdout.?.reader(init.io, &buffer);
    const line = try reader.interface.takeDelimiterExclusive('\n');
    const prefix = "LLM request debugger: ";
    if (!std.mem.startsWith(u8, line, prefix)) return error.InvalidStartup;
    const link = line[prefix.len..];
    const separator = std.mem.indexOf(u8, link, "/#") orelse return error.InvalidStartup;
    const origin = try a.dupe(u8, link[0..separator]);
    const token = try a.dupe(u8, link[separator + 2 ..]);
    if (!std.mem.startsWith(u8, origin, "http://127.0.0.1:") or token.len != 32) return error.InvalidStartup;
    var client: std.http.Client = .{ .allocator = a, .io = init.io };
    defer client.deinit();
    for ([_][2][]const u8{ .{ "/", "Request debugger" }, .{ "/app.js", "Replay edited prompt" }, .{ "/app.js", "Captured file" }, .{ "/app.js", "sourceNavigation" }, .{ "/style.css", ".layout" } }) |asset| {
        var body: std.Io.Writer.Allocating = .init(a);
        const response = try client.fetch(.{ .location = .{ .url = try std.mem.concat(a, u8, &.{ origin, asset[0] }) }, .response_writer = &body.writer, .keep_alive = false });
        if (response.status != .ok or std.mem.indexOf(u8, body.written(), asset[1]) == null) return error.MissingEmbeddedAsset;
    }
    const api = try std.mem.concat(a, u8, &.{ origin, "/api/calls" });
    if ((try client.fetch(.{ .location = .{ .url = api }, .keep_alive = false })).status != .forbidden) return error.UnauthenticatedRead;
    var listing: std.Io.Writer.Allocating = .init(a);
    const result = try client.fetch(.{ .location = .{ .url = api }, .keep_alive = false, .extra_headers = &.{.{ .name = "x-sdde-debugger-token", .value = token }}, .response_writer = &listing.writer });
    if (result.status != .ok or !std.mem.eql(u8, listing.written(), "[]")) return error.InvalidCallListing;
    const replay = try std.mem.concat(a, u8, &.{ origin, "/api/replay" });
    const denied = try client.fetch(.{ .location = .{ .url = replay }, .method = .POST, .payload = "{}", .keep_alive = false, .extra_headers = &.{ .{ .name = "x-sdde-debugger-token", .value = token }, .{ .name = "origin", .value = "https://foreign.example" } } });
    if (denied.status != .forbidden) return error.CrossOriginReplay;
    const invalid = try client.fetch(.{ .location = .{ .url = replay }, .method = .POST, .payload = "{\"call\":0,\"mode\":\"workflow\",\"edit\":null}", .keep_alive = false, .extra_headers = &.{ .{ .name = "x-sdde-debugger-token", .value = token }, .{ .name = "origin", .value = origin }, .{ .name = "content-type", .value = "application/json" } } });
    if (invalid.status != .bad_request) return error.WorkflowReplayAccepted;
}
