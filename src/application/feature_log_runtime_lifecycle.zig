const feature_log_bindings = @import("feature_log_child_bindings.zig");
const feature_log_candidate = @import("feature_log_candidate.zig");
const feature_log_orchestrator = @import("feature_log_orchestrator.zig");
const policy_transition = @import("feature_log_policy_transition_coordinator.zig");
const policy_transition_bindings = @import("feature_log_policy_transition_child_bindings.zig");
const finalization = @import("feature_log_finalization_coordinator.zig");
const finalization_bindings = @import("feature_log_finalization_child_bindings.zig");
const retention = @import("feature_log_retention_coordinator.zig");
const retention_bindings = @import("feature_log_retention_child_bindings.zig");
const telemetry = @import("../domain/telemetry.zig");
const execution = @import("../domain/workflow_execution.zig");
const barrier_port = @import("../ports/telemetry_barrier.zig");

/// Owns the one active logging-runner binding used by the common pipeline.
/// Artifact activation constructs runners; this coordinator only installs,
/// transitions, and uses that already-validated binding.
pub const Lifecycle = struct {
    active: ?feature_log_bindings.ChildBindings = null,

    pub fn barrier(self: *Lifecycle) barrier_port.Barrier {
        return .{ .context = self, .process_fn = process };
    }

    pub fn activate(
        self: *Lifecycle,
        next: feature_log_bindings.ChildBindings,
        shortcode: telemetry.WorkflowShortcode,
    ) policy_transition.Outcome {
        if (self.active != null or next.retired()) return .invalid;
        return switch (next.invokePrepare(shortcode)) {
            .dropped, .persisted => blk: {
                self.active = next;
                break :blk .ok;
            },
            .blocked => |failure| .{ .blocked = failure },
        };
    }

    pub fn transition(
        self: *Lifecycle,
        children: policy_transition_bindings.ChildBindings,
    ) policy_transition.Outcome {
        const current = self.active orelse return .invalid;
        const participants = children.participants();
        if (participants.current_identity != current.identity()) return .invalid;
        const outcome = policy_transition.run(children);
        self.active = if (outcome == .ok) participants.next else if (outcome == .invalid) current else null;
        return outcome;
    }

    pub fn finalizeActive(
        self: *Lifecycle,
        children: finalization_bindings.ChildBindings,
    ) finalization.Outcome {
        const current = self.active orelse return .invalid;
        const target = children.target();
        if (target.mode != .active or target.identity != current.identity()) return .invalid;
        const outcome = finalization.run(children);
        if (outcome != .invalid) self.active = null;
        return outcome;
    }

    pub fn finalizeHistorical(
        self: *Lifecycle,
        children: finalization_bindings.ChildBindings,
    ) finalization.Outcome {
        if (self.active != null) return .invalid;
        if (children.target().mode != .historical) return .invalid;
        return finalization.run(children);
    }

    pub fn retainHistorical(
        self: *Lifecycle,
        children: retention_bindings.ChildBindings,
        shortcode: telemetry.WorkflowShortcode,
    ) retention.Outcome {
        const current = self.active orelse return .{ .blocked = .LOG_SINK_FAILURE };
        return switch (retention.run(children)) {
            .ok => .ok,
            .blocked => |failure| .{ .blocked = current.invokeReportFailure(shortcode, failure) },
        };
    }

    fn process(context: *anyopaque, fact: telemetry.WorkflowTelemetryFact) execution.Candidate {
        const self: *Lifecycle = @ptrCast(@alignCast(context));
        const active = self.active orelse return .{ .outcome = .blocked, .delta = .{} };
        return feature_log_candidate.fromResult(feature_log_orchestrator.processEvent(active, fact));
    }
};
