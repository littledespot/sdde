const logging = @import("../domain/logging.zig");
const feature_log_runner = @import("feature_log_runner.zig");
const finalization = @import("feature_log_finalization_coordinator.zig");
const lifecycle_module = @import("feature_log_runtime_lifecycle.zig");
const transition_coordinator = @import("feature_log_policy_transition_coordinator.zig");
const retention = @import("feature_log_retention_coordinator.zig");
const runtime = @import("../domain/feature_log_runtime.zig");
const telemetry = @import("../domain/telemetry.zig");
const barrier_port = @import("../ports/telemetry_barrier.zig");
const sink_port = @import("../ports/feature_log_sink.zig");

pub const LogService = struct {
    owner: *logging.Owner,
    lifecycle: lifecycle_module.Lifecycle = .{},

    pub fn init(owner: *logging.Owner) LogService {
        return .{ .owner = owner };
    }

    pub fn policy(self: *const LogService) *const logging.CompiledLoggingPolicy {
        return logging.policy(self.owner);
    }

    pub fn barrier(self: *LogService) barrier_port.Barrier {
        return self.lifecycle.barrier();
    }

    pub fn activate(
        self: *LogService,
        active: *feature_log_runner.Runner,
        shortcode: telemetry.WorkflowShortcode,
    ) transition_coordinator.Outcome {
        return self.lifecycle.activate(active, shortcode);
    }

    pub fn transition(
        self: *LogService,
        next: *feature_log_runner.Runner,
        shortcode: telemetry.WorkflowShortcode,
    ) transition_coordinator.Outcome {
        return self.lifecycle.transition(next, shortcode);
    }

    pub fn finalizeActive(
        self: *LogService,
        shortcode: telemetry.WorkflowShortcode,
    ) finalization.Outcome {
        return self.lifecycle.finalizeActive(shortcode);
    }

    pub fn finalizeHistorical(
        self: *LogService,
        historical: *feature_log_runner.Runner,
        shortcode: telemetry.WorkflowShortcode,
    ) finalization.Outcome {
        return self.lifecycle.finalizeHistorical(historical, shortcode);
    }

    pub fn retainHistorical(
        self: *LogService,
        acquirer: sink_port.LockAcquirer,
        pruner: sink_port.SegmentPruner,
        releaser: sink_port.LockReleaser,
        historical: *const runtime.ValidatedFeatureLogBinding,
        authorization: *runtime.RetentionAuthorizationOwner,
        shortcode: telemetry.WorkflowShortcode,
    ) retention.Outcome {
        return self.lifecycle.retainHistorical(acquirer, pruner, releaser, historical, authorization, shortcode);
    }

    pub fn deinit(self: *LogService) void {
        logging.deinitOwner(self.owner);
        self.* = undefined;
    }
};
