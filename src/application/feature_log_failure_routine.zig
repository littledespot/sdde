const std = @import("std");
const log_format = @import("../domain/feature_log_format.zig");
const log_limits = @import("../domain/feature_log_limits.zig");
const log_stream = @import("../domain/feature_log_stream.zig");
const telemetry = @import("../domain/telemetry.zig");
const emergency_port = @import("../ports/emergency_log_sink.zig");

// ADR 0032, ADR 0018: reporting one logging failure as one engine routine. It formats the bounded canonical emergency
// record of the failure's closed code, then writes it once. It is no pipeline node, writes no log row and never reports
// its own failure: an emergency line that cannot be formatted or written is lost, because a report of that would be a
// second report of one failure, so it returns where it stopped and nothing reads it. A cancellation is no logging
// failure and reaches this routine never.

/// The closed set of steps, in execution order. A stop records the step it belongs to in the caller's `Diagnostic`.
pub const Step = enum { format, write };

/// What a run that wrote nothing leaves beside its outcome: the step. No report reads it.
pub const Diagnostic = struct {
    step: ?Step = null,
};

/// The port the routine's write step reaches. No step receives this set; each takes the one port it uses.
pub const Ports = struct {
    emergency: emergency_port.Sink,
};

pub const Outcome = enum { written, lost };

/// The entry function only sequences the steps and passes each port on.
pub fn run(ports: Ports, shortcode: telemetry.WorkflowShortcode, failure: log_stream.FailureCode, diagnostic: *Diagnostic) Outcome {
    var buffer: [log_limits.emergency_max_ascii_bytes]u8 = undefined;
    const line = steps.format(&buffer, shortcode, failure) orelse return lost(diagnostic, .format);
    if (!steps.write(ports.emergency, line)) return lost(diagnostic, .write);
    return .written;
}

fn lost(diagnostic: *Diagnostic, step: Step) Outcome {
    diagnostic.step = step;
    return .lost;
}

/// The two steps. Each is one typed function; the write step takes exactly the one port it uses.
pub const steps = struct {
    pub fn format(buffer: *[log_limits.emergency_max_ascii_bytes]u8, shortcode: telemetry.WorkflowShortcode, failure: log_stream.FailureCode) ?[]const u8 {
        return log_format.emergencyLine(buffer, shortcode, failure);
    }

    /// Whether the line was written. A sink that cannot take it is the end of the report, never a failure to report.
    pub fn write(emergency: emergency_port.Sink, line: []const u8) bool {
        emergency.write(line) catch return false;
        return true;
    }
};
