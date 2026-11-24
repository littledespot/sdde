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

test "the provider operation clock reads boot time" {
    const io = std.testing.io;
    var adapter: Adapter = .{ .io = io };
    const before = std.Io.Clock.now(.boot, io).toMilliseconds();
    const read = try adapter.clock().now();
    const after = std.Io.Clock.now(.boot, io).toMilliseconds();
    try std.testing.expect(read >= @as(u64, @intCast(before)) and read <= @as(u64, @intCast(after)));
}
