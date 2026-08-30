const feature_log_runner = @import("feature_log_runner.zig");
const policy_transition = @import("feature_log_policy_transition_coordinator.zig");
const finalization = @import("feature_log_finalization_coordinator.zig");
const retention = @import("feature_log_retention_coordinator.zig");
const runtime = @import("../domain/feature_log_runtime.zig");
const telemetry = @import("../domain/telemetry.zig");
const barrier_port = @import("../ports/telemetry_barrier.zig");
const sink_port = @import("../ports/feature_log_sink.zig");

/// Owns the one active logging-runner binding used by the common pipeline.
/// Artifact activation constructs runners; this coordinator only installs,
/// transitions, and uses that already-validated binding.
pub const Lifecycle = struct {
    active: ?*feature_log_runner.Runner = null,

    pub fn barrier(self: *Lifecycle) barrier_port.Barrier {
        return .{ .context = self, .process_fn = process };
    }

    pub fn activate(
        self: *Lifecycle,
        next: *feature_log_runner.Runner,
        shortcode: telemetry.WorkflowShortcode,
    ) policy_transition.Outcome {
        if (self.active != null or next.retired) return .invalid;
        return switch (next.prepare(shortcode)) {
            .dropped, .persisted => blk: {
                self.active = next;
                break :blk .ok;
            },
            .blocked => |failure| .{ .blocked = failure },
        };
    }

    pub fn transition(
        self: *Lifecycle,
        next: *feature_log_runner.Runner,
        shortcode: telemetry.WorkflowShortcode,
    ) policy_transition.Outcome {
        const current = self.active orelse return .invalid;
        if (next.retired) return .invalid;
        const outcome = policy_transition.run(current, next, shortcode);
        self.active = if (outcome == .ok) next else if (outcome == .invalid) current else null;
        return outcome;
    }

    pub fn finalizeActive(
        self: *Lifecycle,
        shortcode: telemetry.WorkflowShortcode,
    ) finalization.Outcome {
        const current = self.active orelse return .invalid;
        const outcome = finalization.active(current, shortcode);
        if (outcome != .invalid) self.active = null;
        return outcome;
    }

    pub fn finalizeHistorical(
        self: *Lifecycle,
        historical: *feature_log_runner.Runner,
        shortcode: telemetry.WorkflowShortcode,
    ) finalization.Outcome {
        if (self.active != null) return .invalid;
        return finalization.historical(historical, shortcode);
    }

    pub fn retainHistorical(
        self: *Lifecycle,
        sink: sink_port.Sink,
        historical: *const runtime.ValidatedFeatureLogBinding,
        authorization: *runtime.RetentionAuthorizationOwner,
        shortcode: telemetry.WorkflowShortcode,
    ) retention.Outcome {
        const current = self.active orelse return .{ .blocked = .LOG_SINK_FAILURE };
        return switch (retention.run(sink, current.binding, historical, authorization)) {
            .ok => .ok,
            .blocked => |failure| .{ .blocked = current.reportFailure(shortcode, failure) },
        };
    }

    fn process(context: *anyopaque, fact: telemetry.WorkflowTelemetryFact) runtime.BarrierOutcome {
        const self: *Lifecycle = @ptrCast(@alignCast(context));
        const active = self.active orelse return .{ .blocked = .LOG_SINK_FAILURE };
        return active.process(fact);
    }
};
