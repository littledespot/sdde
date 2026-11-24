const std = @import("std");
const routine = @import("application/feature_log_failure_routine.zig");
const log_limits = @import("domain/feature_log_limits.zig");
const log_stream = @import("domain/feature_log_stream.zig");
const telemetry = @import("domain/telemetry.zig");
const emergency_port = @import("ports/emergency_log_sink.zig");

/// A fake emergency sink that records every write and fails where told.
const Capture = struct {
    bytes: [log_limits.emergency_max_ascii_bytes]u8 = undefined,
    length: usize = 0,
    calls: usize = 0,
    fails: bool = false,

    fn ports(self: *Capture) routine.Ports {
        return .{ .emergency = .{ .context = self, .write_fn = write } };
    }

    fn write(context: *anyopaque, bytes: []const u8) emergency_port.Error!void {
        const self: *Capture = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (self.fails) return error.EmergencyWriteFailure;
        @memcpy(self.bytes[0..bytes.len], bytes);
        self.length = bytes.len;
    }
};

test "a failure writes the one bounded canonical emergency record, once" {
    var capture: Capture = .{};
    var diagnostic: routine.Diagnostic = .{};
    const outcome = routine.run(capture.ports(), try telemetry.WorkflowShortcode.parse("SPEC"), .LOG_SINK_FAILURE, &diagnostic);
    try std.testing.expectEqual(routine.Outcome.written, outcome);
    try std.testing.expectEqual(@as(usize, 1), capture.calls);
    try std.testing.expectEqualStrings("SDDE_LOG_FAILURE workflow=SPEC level=fatal code=LOG_SINK_FAILURE\n", capture.bytes[0..capture.length]);
    try std.testing.expectEqual(@as(?routine.Step, null), diagnostic.step);
}

test "every failure code fits the bound, so the line is never lost to its size" {
    for (std.enums.values(log_stream.FailureCode)) |code| {
        var capture: Capture = .{};
        var diagnostic: routine.Diagnostic = .{};
        const outcome = routine.run(capture.ports(), try telemetry.WorkflowShortcode.parse("IMPL"), code, &diagnostic);
        try std.testing.expectEqual(routine.Outcome.written, outcome);
        try std.testing.expect(capture.length <= log_limits.emergency_max_ascii_bytes);
        try std.testing.expect(std.mem.endsWith(u8, capture.bytes[0..capture.length], "\n"));
        try std.testing.expect(std.mem.indexOf(u8, capture.bytes[0..capture.length], @tagName(code)) != null);
    }
}

test "a sink that cannot take the line loses it without a second write or a report of its own" {
    var capture: Capture = .{ .fails = true };
    var diagnostic: routine.Diagnostic = .{};
    const outcome = routine.run(capture.ports(), try telemetry.WorkflowShortcode.parse("SPEC"), .LOG_FLUSH_FAILURE, &diagnostic);
    try std.testing.expectEqual(routine.Outcome.lost, outcome);
    // One attempt, and the step it stopped at is recorded for the caller, which reads nothing.
    try std.testing.expectEqual(@as(usize, 1), capture.calls);
    try std.testing.expectEqual(@as(?routine.Step, .write), diagnostic.step);
}

test "the write step reports whether the sink took the line, and reaches only the one port" {
    var accepting: Capture = .{};
    try std.testing.expect(routine.steps.write(accepting.ports().emergency, "line\n"));
    try std.testing.expectEqualStrings("line\n", accepting.bytes[0..accepting.length]);
    // A sink that cannot take the line is the end of the report, never a failure to report: the step says so and writes
    // nothing else.
    var refusing: Capture = .{ .fails = true };
    try std.testing.expect(!routine.steps.write(refusing.ports().emergency, "line\n"));
    try std.testing.expectEqual(@as(usize, 1), refusing.calls);
    try std.testing.expectEqual(@as(usize, 0), refusing.length);
}

test "formatting is the domain's pure function and writes nothing" {
    var buffer: [log_limits.emergency_max_ascii_bytes]u8 = undefined;
    const line = routine.steps.format(&buffer, try telemetry.WorkflowShortcode.parse("TEST"), .LOG_RELEASE_FAILURE).?;
    try std.testing.expectEqualStrings("SDDE_LOG_FAILURE workflow=TEST level=fatal code=LOG_RELEASE_FAILURE\n", line);
}
