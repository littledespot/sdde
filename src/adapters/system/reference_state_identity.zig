const std = @import("std");
const port = @import("../../ports/reference_state_identity.zig");

pub const Adapter = struct {
    io: std.Io,

    pub fn source(self: *Adapter) port.Source {
        return .{ .context = self, .next_fn = next };
    }

    fn next(context: *anyopaque) port.Error![16]u8 {
        const self: *Adapter = @ptrCast(@alignCast(context));
        var nonce: [16]u8 = undefined;
        self.io.randomSecure(&nonce) catch return error.IdentityUnavailable;
        return nonce;
    }
};
