const log_policy = @import("../domain/log_policy.zig");
const feature_log_bindings = @import("feature_log_child_bindings.zig");
const finalization = @import("feature_log_finalization_coordinator.zig");
const lifecycle_module = @import("feature_log_runtime_lifecycle.zig");
const transition_coordinator = @import("feature_log_policy_transition_coordinator.zig");
const transition_bindings = @import("feature_log_policy_transition_child_bindings.zig");
const retention = @import("feature_log_retention_coordinator.zig");
const retention_bindings = @import("feature_log_retention_child_bindings.zig");
const finalization_bindings = @import("feature_log_finalization_child_bindings.zig");
const telemetry = @import("../domain/telemetry.zig");
const barrier_port = @import("../ports/telemetry_barrier.zig");

pub const LogService = struct {
    owner: *log_policy.Owner,
    lifecycle: lifecycle_module.Lifecycle = .{},

    pub fn init(owner: *log_policy.Owner) LogService {
        return .{ .owner = owner };
    }

    pub fn policy(self: *const LogService) *const log_policy.CompiledLoggingPolicy {
        return log_policy.policy(self.owner);
    }

    pub fn barrier(self: *LogService) barrier_port.Barrier {
        return self.lifecycle.barrier();
    }

    pub fn activate(
        self: *LogService,
        active: feature_log_bindings.ChildBindings,
        shortcode: telemetry.WorkflowShortcode,
    ) transition_coordinator.Outcome {
        return self.lifecycle.activate(active, shortcode);
    }

    pub fn transition(
        self: *LogService,
        children: transition_bindings.ChildBindings,
    ) transition_coordinator.Outcome {
        return self.lifecycle.transition(children);
    }

    pub fn finalizeActive(
        self: *LogService,
        children: finalization_bindings.ChildBindings,
    ) finalization.Outcome {
        return self.lifecycle.finalizeActive(children);
    }

    pub fn finalizeHistorical(
        self: *LogService,
        children: finalization_bindings.ChildBindings,
    ) finalization.Outcome {
        return self.lifecycle.finalizeHistorical(children);
    }

    pub fn retainHistorical(
        self: *LogService,
        children: retention_bindings.ChildBindings,
        shortcode: telemetry.WorkflowShortcode,
    ) retention.Outcome {
        return self.lifecycle.retainHistorical(children, shortcode);
    }

    pub fn deinit(self: *LogService) void {
        log_policy.deinitOwner(self.owner);
        self.* = undefined;
    }
};
