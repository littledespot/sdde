const console_port = @import("../../ports/console_log_sink.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{ConsoleLogWriteFailure};

pub const Action = struct {
    sink: console_port.Sink,
    pub const contract: pipeline.NodeContract = .{
        .id = "write-console-log-record@1",
        .kind = .action,
        .requires = &.{.serialized_log_record},
        .produces = &.{},
        .side_effect = .filesystem_write,
    };

    pub fn execute(self: Action, bytes: []const u8) Error!void {
        self.sink.write(bytes) catch return error.ConsoleLogWriteFailure;
    }
};
