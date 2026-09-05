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
