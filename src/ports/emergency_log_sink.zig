pub const Error = error{EmergencyWriteFailure};
pub const Sink = struct {
    context: *anyopaque,
    write_fn: *const fn (*anyopaque, []const u8) Error!void,

    pub fn write(self: Sink, bytes: []const u8) Error!void {
        return self.write_fn(self.context, bytes);
    }
};
