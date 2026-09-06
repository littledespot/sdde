const std = @import("std");
const fixture_module = @import("bedrock_http_test_fixture.zig");
const transport = @import("adapters/provider/bedrock_transport.zig");
const good = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello";

test "concrete HTTP sends each API once and owns a complete fragmented response" {
    for ([_]@import("domain/llm_provider_operation.zig").ProviderOperationKind{ .input_token_count, .inference }) |kind| {
        var fixture: fixture_module.Fixture = undefined;
        fixture.init(good);
        defer fixture.deinit();
        var adapter = fixture.adapter();
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const result = try adapter.port().exchange(arena.allocator(), fixture.request(kind));
        try std.testing.expectEqualStrings("hello", result.received.body);
        try std.testing.expectEqual(@as(u16, 200), result.received.status);
        try fixture.expectJoined();
        try std.testing.expectEqual(@as(usize, 1), fixture.opens);
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, fixture.wire.items, "POST "));
        const path = if (kind == .inference) "/converse HTTP/1.1\r\n" else "/count-tokens HTTP/1.1\r\n";
        try std.testing.expect(std.mem.indexOf(u8, fixture.wire.items, path) != null);
        try std.testing.expect(std.mem.indexOf(u8, fixture.wire.items, "host: bedrock-runtime.ap-southeast-2.amazonaws.com\r\n") != null);
        try std.testing.expect(std.mem.endsWith(u8, fixture.wire.items, fixture.request(kind).body));
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, fixture.wire.items, &fixture.canary));
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, fixture.wire.items, "authorization: Bearer "));
        try std.testing.expect(std.mem.indexOf(u8, result.received.body, &fixture.canary) == null);
    }
}

test "concrete HTTP deadline cancels and joins blocked connect write head and body without resending" {
    for (std.enums.values(fixture_module.Point)) |point| {
        var fixture: fixture_module.Fixture = undefined;
        fixture.init(good);
        defer fixture.deinit();
        fixture.fault = .deadline;
        fixture.point = point;
        var adapter = fixture.adapter();
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const result = try adapter.port().exchange(arena.allocator(), fixture.request(.inference));
        try std.testing.expectEqual(.timeout, result.failed.cause);
        const delivery: @import("domain/llm_provider_operation.zig").ProviderDeliveryDisposition = if (point == .connect) .not_sent else .accepted_or_unknown;
        try std.testing.expectEqual(delivery, result.failed.delivery);
        try std.testing.expectEqual(@as(usize, 1), fixture.socket_cancellations.load(.acquire));
        try fixture.expectJoined();
    }
}

test "concrete HTTP preserves socket cancellation during connect write head and body" {
    for (std.enums.values(fixture_module.Point)) |point| {
        var fixture: fixture_module.Fixture = undefined;
        fixture.init(good);
        defer fixture.deinit();
        fixture.fault = .cancelled;
        fixture.point = point;
        var adapter = fixture.adapter();
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        try std.testing.expectError(error.Cancelled, adapter.port().exchange(arena.allocator(), fixture.request(.inference)));
        try fixture.expectJoined();
    }
}

test "concrete HTTP caller cancellation joins blocked network and timer before return" {
    for (std.enums.values(fixture_module.Point)) |point| {
        var fixture: fixture_module.Fixture = undefined;
        fixture.init(good);
        defer fixture.deinit();
        fixture.fault = .held;
        fixture.point = point;
        var adapter = fixture.adapter();
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        var future = try fixture.io().concurrent(call, .{ &adapter, arena.allocator(), fixture.request(.inference) });
        defer std.testing.expectError(error.Cancelled, future.cancel(fixture.io())) catch @panic("caller cancellation must join the exchange");
        try fixture.reached.waitTimeout(fixture.io(), .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } });
        try std.testing.expectError(error.Cancelled, future.cancel(fixture.io()));
        try std.testing.expectEqual(@as(usize, 1), fixture.socket_cancellations.load(.acquire));
        try fixture.expectJoined();
    }
}

fn call(adapter: *fixture_module.Adapter, allocator: std.mem.Allocator, request: transport.Request) transport.Error!transport.Response {
    return adapter.port().exchange(allocator, request);
}

test "concrete HTTP rejects interrupted response bodies and never returns partial success" {
    for ([_][]const u8{ good, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n" }) |response| {
        for ([_]fixture_module.Fault{ .reset, .eof }) |fault| {
            var fixture: fixture_module.Fixture = undefined;
            fixture.init(response);
            defer fixture.deinit();
            fixture.fault = fault;
            var adapter = fixture.adapter();
            var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
            defer arena.deinit();
            const result = try adapter.port().exchange(arena.allocator(), fixture.request(.inference));
            try std.testing.expect(result == .failed);
            try std.testing.expectEqual(.accepted_or_unknown, result.failed.delivery);
            try std.testing.expect(fixture.cursor > fixture.body_start and fixture.cursor < fixture.response.len);
            try fixture.expectJoined();
        }
    }
}

test "concrete HTTP preserves timeout when a response finishes during cancellation cleanup" {
    var fixture: fixture_module.Fixture = undefined;
    fixture.init(good);
    defer fixture.deinit();
    fixture.fault = .deadline;
    fixture.finish_after_cancel = true;
    var adapter = fixture.adapter();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const result = try adapter.port().exchange(arena.allocator(), fixture.request(.inference));
    try std.testing.expectEqual(.timeout, result.failed.cause);
    try std.testing.expectEqual(.accepted_or_unknown, result.failed.delivery);
    try std.testing.expectEqual(fixture.response.len, fixture.cursor);
    try std.testing.expectEqual(@as(usize, 1), fixture.socket_cancellations.load(.acquire));
    try fixture.expectJoined();
}

test "concrete HTTP partial sends and interrupted heads fail without a resend" {
    for ([_]fixture_module.Point{ .connect, .write, .head }) |point| {
        var fixture: fixture_module.Fixture = undefined;
        fixture.init(good);
        defer fixture.deinit();
        fixture.fault = .reset;
        fixture.point = point;
        var adapter = fixture.adapter();
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const result = try adapter.port().exchange(arena.allocator(), fixture.request(.inference));
        try std.testing.expectEqual(.transport_failed, result.failed.cause);
        const delivery: @import("domain/llm_provider_operation.zig").ProviderDeliveryDisposition = if (point == .connect) .not_sent else .accepted_or_unknown;
        try std.testing.expectEqual(delivery, result.failed.delivery);
        try std.testing.expect(fixture.fault_fired);
        if (point == .write) try std.testing.expect(fixture.wire.items.len > 0 and !std.mem.endsWith(u8, fixture.wire.items, fixture.request(.inference).body));
        if (point == .head) try std.testing.expect(fixture.cursor > 0 and fixture.cursor < fixture.body_start);
        try fixture.expectJoined();
    }
}

test "concrete HTTP reads chunked close-delimited and informational responses without resending" {
    for ([_][]const u8{
        "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nhe\r\n3\r\nllo\r\n0\r\n\r\n",
        "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nhello",
        "HTTP/1.1 100 Continue\r\n\r\n" ++ good,
    }) |response| {
        var fixture: fixture_module.Fixture = undefined;
        fixture.init(response);
        defer fixture.deinit();
        var adapter = fixture.adapter();
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const result = try adapter.port().exchange(arena.allocator(), fixture.request(.inference));
        try std.testing.expectEqualStrings("hello", result.received.body);
        try fixture.expectJoined();
    }
}

test "concrete HTTP returns AWS error responses once and never follows redirects" {
    for ([_]u16{ 302, 307, 429, 500, 503 }) |status| {
        const wire = try std.fmt.allocPrint(std.testing.allocator, "HTTP/1.1 {d} Test\r\nLocation: https://outside.invalid/\r\nx-AmZn-ErrorType: TestException\r\nContent-Length: 2\r\n\r\n{{}}", .{status});
        defer std.testing.allocator.free(wire);
        var fixture: fixture_module.Fixture = undefined;
        fixture.init(wire);
        defer fixture.deinit();
        var adapter = fixture.adapter();
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const result = try adapter.port().exchange(arena.allocator(), fixture.request(.inference));
        if (status < 400) {
            try std.testing.expectEqual(.response_invalid, result.failed.cause);
            try std.testing.expectEqual(.never, result.failed.retry_class);
            try std.testing.expectEqual(.response_received, result.failed.delivery);
        } else {
            try std.testing.expectEqual(status, result.received.status);
            try std.testing.expectEqualStrings("TestException", result.received.exception.?);
            try std.testing.expectEqualStrings("{}", result.received.body);
        }
        try fixture.expectJoined();
    }
}

test "concrete HTTP rejects malformed truncated and encoded responses without partial publication" {
    for ([_][]const u8{
        "NOT-HTTP\r\n\r\n",
        "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello",
        "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n",
        "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nz\r\nhello\r\n",
        "HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\nContent-Length: 5\r\n\r\nhello",
        "HTTP/1.1 429 Error\r\nx-amzn-errortype: A\r\nX-Amzn-ErrorType: B\r\nContent-Length: 2\r\n\r\n{}",
    }) |wire| {
        var fixture: fixture_module.Fixture = undefined;
        fixture.init(wire);
        defer fixture.deinit();
        var adapter = fixture.adapter();
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const result = try adapter.port().exchange(arena.allocator(), fixture.request(.inference));
        try std.testing.expect(result == .failed);
        try fixture.expectJoined();
    }
}

test "concrete HTTP owns request headers and bodies beyond socket buffer sizes" {
    const body = "x" ** 30000;
    const response = try std.fmt.allocPrint(std.testing.allocator, "HTTP/1.1 200 OK\r\nX-Large: {s}\r\nContent-Length: {d}\r\n\r\n{s}", .{ "h" ** 20000, body.len, body });
    defer std.testing.allocator.free(response);
    var fixture: fixture_module.Fixture = undefined;
    fixture.init(response);
    defer fixture.deinit();
    fixture.maximum_read = 257;
    fixture.maximum_write = 1024;
    var adapter = fixture.adapter();
    var request = fixture.request(.inference);
    request.body = body;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const result = try adapter.port().exchange(arena.allocator(), request);
    try std.testing.expectEqualStrings(body, result.received.body);
    try std.testing.expect(std.mem.endsWith(u8, fixture.wire.items, body));
    try fixture.expectJoined();
}

test "concrete HTTP allocation failures join tasks and release connections on every path" {
    for ([_]fixture_module.Fault{ .none, .reset, .cancelled, .deadline }) |fault| {
        try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{fault});
    }
}

fn allocationScenario(allocator: std.mem.Allocator, fault: fixture_module.Fault) !void {
    var fixture: fixture_module.Fixture = undefined;
    fixture.init(good);
    defer fixture.deinit();
    fixture.fault = fault;
    var adapter = fixture.adapter();
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    defer fixture.expectCleaned() catch @panic("transport left a task or connection alive");
    const result = adapter.port().exchange(arena.allocator(), fixture.request(.inference)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Cancelled => {
            try std.testing.expectEqual(.cancelled, fault);
            return;
        },
    };
    switch (fault) {
        .none => try std.testing.expectEqualStrings("hello", result.received.body),
        .reset => try std.testing.expectEqual(.transport_failed, result.failed.cause),
        .deadline => try std.testing.expectEqual(.timeout, result.failed.cause),
        else => return error.TestUnexpectedResult,
    }
}

test "concrete HTTP scheduler failure joins an already active request without resending" {
    for ([_]usize{ 1, 2 }) |spawn| {
        var fixture: fixture_module.Fixture = undefined;
        fixture.init(good);
        defer fixture.deinit();
        fixture.fault = .held;
        fixture.fail_spawn = spawn;
        var adapter = fixture.adapter();
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const result = try adapter.port().exchange(arena.allocator(), fixture.request(.inference));
        try std.testing.expectEqual(.transport_failed, result.failed.cause);
        const delivery: @import("domain/llm_provider_operation.zig").ProviderDeliveryDisposition = if (spawn == 1) .not_sent else .accepted_or_unknown;
        try std.testing.expectEqual(delivery, result.failed.delivery);
        try std.testing.expectEqual(spawn - 1, fixture.connects);
        try std.testing.expectEqual(spawn - 1, fixture.socket_cancellations.load(.acquire));
        try fixture.expectCleaned();
    }
}
