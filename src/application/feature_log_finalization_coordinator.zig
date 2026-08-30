const feature_log_runner = @import("feature_log_runner.zig");
const runtime = @import("../domain/feature_log_runtime.zig");
const telemetry = @import("../domain/telemetry.zig");

pub const Outcome = union(enum) { ok, blocked: runtime.FailureCode, invalid };

/// Closes one prepared active binding and makes its open segment durable.
pub fn active(
    runner: *feature_log_runner.Runner,
    shortcode: telemetry.WorkflowShortcode,
) Outcome {
    if (runner.retired or !runner.prepared) return .invalid;
    return switch (runner.close(shortcode)) {
        .dropped, .persisted => .ok,
        .blocked => |failure| .{ .blocked = failure },
    };
}

/// Recovers and finalizes one already-authorized historical binding. Startup
/// owns inventory order and supplies a runner assembled for that exact binding.
pub fn historical(
    runner: *feature_log_runner.Runner,
    shortcode: telemetry.WorkflowShortcode,
) Outcome {
    if (runner.retired) return .invalid;
    switch (runner.prepare(shortcode)) {
        .dropped, .persisted => {},
        .blocked => |failure| return .{ .blocked = failure },
    }
    return active(runner, shortcode);
}
