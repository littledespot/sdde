const feature_log_runner = @import("feature_log_runner.zig");
const logging = @import("../domain/logging.zig");
const runtime = @import("../domain/feature_log_runtime.zig");
const telemetry = @import("../domain/telemetry.zig");

pub const Outcome = union(enum) { ok, blocked: runtime.FailureCode, invalid };

pub fn run(
    active: *feature_log_runner.Runner,
    next: *feature_log_runner.Runner,
    shortcode: telemetry.WorkflowShortcode,
) Outcome {
    if (!sameRun(active.binding, next.binding) or
        @import("std").mem.eql(u8, active.binding.bindingId().bytes, next.binding.bindingId().bytes) or
        @import("std").mem.eql(u8, active.binding.logPolicyId().bytes, next.binding.logPolicyId().bytes) or
        !logging.transitionCompatible(active.policy.*, next.policy.*))
    {
        return .invalid;
    }
    switch (active.close(shortcode)) {
        .dropped, .persisted => {},
        .blocked => |failure| return .{ .blocked = failure },
    }
    return switch (next.prepare(shortcode)) {
        .dropped, .persisted => .ok,
        .blocked => |failure| .{ .blocked = failure },
    };
}

fn sameRun(left: *const runtime.ValidatedFeatureLogBinding, right: *const runtime.ValidatedFeatureLogBinding) bool {
    return @import("std").mem.eql(u8, left.featureId().bytes, right.featureId().bytes) and
        @import("std").mem.eql(u8, left.runId().bytes, right.runId().bytes);
}
