const std = @import("std");
const console_port = @import("../../ports/console_log_sink.zig");
const emergency_port = @import("../../ports/emergency_log_sink.zig");

pub const Adapter = struct {
    io: std.Io,

    pub fn console(self: *Adapter) console_port.Sink {
        return .{ .context = self, .write_fn = writeConsole };
    }
    pub fn emergency(self: *Adapter) emergency_port.Sink {
        return .{ .context = self, .write_fn = writeEmergency };
    }
    fn writeConsole(context: *anyopaque, bytes: []const u8) console_port.Error!void {
        const self: *Adapter = @ptrCast(@alignCast(context));
        std.Io.File.stderr().writeStreamingAll(self.io, bytes) catch return error.ConsoleWriteFailure;
    }
    fn writeEmergency(context: *anyopaque, bytes: []const u8) emergency_port.Error!void {
        const self: *Adapter = @ptrCast(@alignCast(context));
        std.Io.File.stderr().writeStreamingAll(self.io, bytes) catch return error.EmergencyWriteFailure;
    }
};
