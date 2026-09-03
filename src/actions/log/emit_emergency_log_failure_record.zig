const std = @import("std");
const log_limits = @import("../../domain/feature_log_limits.zig");
const log_stream = @import("../../domain/feature_log_stream.zig");
const telemetry = @import("../../domain/telemetry.zig");
const emergency_port = @import("../../ports/emergency_log_sink.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    sink: emergency_port.Sink,
    pub const contract: pipeline.NodeContract = .{
        .id = "emit-emergency-log-failure-record@1",
        .kind = .action,
        .requires = &.{},
        .produces = &.{},
        .side_effect = .filesystem_write,
    };

    pub fn execute(self: Action, shortcode: telemetry.WorkflowShortcode, code: log_stream.FailureCode) void {
        var buffer: [log_limits.emergency_max_ascii_bytes]u8 = undefined;
        const line = std.fmt.bufPrint(
            &buffer,
            "SDDE_LOG_FAILURE workflow={s} level=fatal code={s}\n",
            .{ shortcode.slice(), @tagName(code) },
        ) catch return;
        self.sink.write(line) catch return;
    }
};

test "writes the one bounded canonical emergency record" {
    var capture: Capture = .{};
    (Action{ .sink = capture.sink() }).execute(
        try telemetry.WorkflowShortcode.parse("SPEC"),
        .LOG_SINK_FAILURE,
    );
    try std.testing.expectEqual(@as(usize, 1), capture.calls);
    try std.testing.expectEqualStrings(
        "SDDE_LOG_FAILURE workflow=SPEC level=fatal code=LOG_SINK_FAILURE\n",
        capture.bytes[0..capture.length],
    );
}

const Capture = struct {
    bytes: [log_limits.emergency_max_ascii_bytes]u8 = undefined,
    length: usize = 0,
    calls: usize = 0,

    fn sink(self: *Capture) emergency_port.Sink {
        return .{ .context = self, .write_fn = write };
    }

    fn write(context: *anyopaque, bytes: []const u8) emergency_port.Error!void {
        const self: *Capture = @ptrCast(@alignCast(context));
        self.calls += 1;
        @memcpy(self.bytes[0..bytes.len], bytes);
        self.length = bytes.len;
    }
};
