const std = @import("std");
const lease = @import("../../ports/provider_authorization_lease.zig");

pub const Adapter = struct {
    io: std.Io,

    pub fn clock(self: *Adapter) lease.Clock {
        return .{ .context = @ptrCast(self), .now_fn = now };
    }

    fn now(context: *lease.Context) error{ClockUnavailable}!u64 {
        const self: *Adapter = @ptrCast(@alignCast(context));
        const milliseconds = std.Io.Clock.now(.boot, self.io).toMilliseconds();
        return std.math.cast(u64, milliseconds) orelse error.ClockUnavailable;
    }
};

// SPEC01 C49 (decided 20 November 2026): a request deadline is derived from this clock, which reads boot time, and the
// exchange sleeps the remainder on the same clock (`model_http_exchange.zig`), so the time the machine is suspended
// counts toward the deadline. The Threaded `Io` sleeps a relative duration with `clock_nanosleep` where the platform has
// it (Linux, where boot time is `CLOCK_BOOTTIME`), and on macOS with `nanosleep`, which takes no clock; a unit test
// cannot suspend the machine, so this pins each owner's choice by its source text.
test "the provider operation clock reads boot time and the exchange timer sleeps on boot time" {
    const io = std.testing.io;
    var adapter: Adapter = .{ .io = io };
    const before = std.Io.Clock.now(.boot, io).toMilliseconds();
    const read = try adapter.clock().now();
    const after = std.Io.Clock.now(.boot, io).toMilliseconds();
    try std.testing.expect(read >= @as(u64, @intCast(before)) and read <= @as(u64, @intCast(after)));
    // The adapter's choice by its source text, since the two clocks agree on a host that was never suspended; the
    // pattern is split so that this file counts it once, in `now`.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, @embedFile("provider_operation_clock.zig"), "now(.boot, " ++ "self.io)"));
    const exchange = @embedFile("../provider/model_http_exchange.zig");
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, exchange, ".boot)"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, exchange, ".awake"));
}
