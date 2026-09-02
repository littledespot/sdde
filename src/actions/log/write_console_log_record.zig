const console_port = @import("../../ports/console_log_sink.zig");

pub const Error = error{ConsoleLogWriteFailure};

pub const Action = struct {
    sink: console_port.Sink,
    pub fn execute(self: Action, bytes: []const u8) Error!void {
        self.sink.write(bytes) catch return error.ConsoleLogWriteFailure;
    }
};
