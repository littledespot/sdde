const feature_log_bindings = @import("feature_log_child_bindings.zig");
const feature_log_orchestrator = @import("feature_log_orchestrator.zig");
const finalization = @import("feature_log_finalization_coordinator.zig");
const finalization_bindings = @import("feature_log_finalization_child_bindings.zig");
const retention = @import("feature_log_retention_coordinator.zig");
const retention_bindings = @import("feature_log_retention_child_bindings.zig");
const telemetry = @import("../domain/telemetry.zig");
const log_stream = @import("../domain/feature_log_stream.zig");
const barrier_port = @import("../ports/telemetry_barrier.zig");

pub const Activation = union(enum) { ok, blocked: log_stream.FailureCode, cancelled, invalid };

/// Owns the one active logging-runner binding used by the common pipeline.
/// Artifact activation constructs runners; this coordinator only installs and
/// uses that already-validated binding.
pub const Lifecycle = struct {
    active: ?feature_log_bindings.ChildBindings = null,

    pub fn barrier(self: *Lifecycle) barrier_port.Barrier {
        return .{ .context = self, .process_fn = process, .select_prompt_fn = selectPrompt, .process_prompt_fn = processPrompt, .report_failure_fn = reportFailure };
    }

    pub fn activate(
        self: *Lifecycle,
        next: feature_log_bindings.ChildBindings,
        shortcode: telemetry.WorkflowShortcode,
    ) Activation {
        if (self.active != null or next.retired()) return .invalid;
        return switch (next.invokePrepare(shortcode)) {
            .dropped, .persisted => blk: {
                self.active = next;
                break :blk .ok;
            },
            .blocked => |failure| .{ .blocked = failure },
            .cancelled => .cancelled,
        };
    }

    pub fn finalizeActive(
        self: *Lifecycle,
        children: finalization_bindings.ChildBindings,
    ) finalization.Outcome {
        const current = self.active orelse return .invalid;
        const target = children.target();
        if (target.identity != current.identity()) return .invalid;
        const outcome = finalization.run(children);
        if (outcome != .invalid) self.active = null;
        return outcome;
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
            .cancelled => .cancelled,
        };
    }

    fn process(context: *anyopaque, fact: telemetry.WorkflowTelemetryFact) log_stream.Outcome {
        const self: *Lifecycle = @ptrCast(@alignCast(context));
        const active = self.active orelse return .{ .blocked = .LOG_SINK_FAILURE };
        return feature_log_orchestrator.processEvent(active, fact);
    }
    fn selectPrompt(context: *anyopaque, fragment: @import("../domain/sanitized_prompt_log.zig").SanitizedPromptFragment) bool {
        const self: *Lifecycle = @ptrCast(@alignCast(context));
        // An absent required active logger fails at persistence, never silently drops.
        const active = self.active orelse return true;
        return active.invokeEvaluatePrompt(fragment) == .emit;
    }
    fn processPrompt(context: *anyopaque, fragment: @import("../domain/sanitized_prompt_log.zig").SanitizedPromptFragment) log_stream.Outcome {
        const self: *Lifecycle = @ptrCast(@alignCast(context));
        const active = self.active orelse return .{ .blocked = .LOG_SINK_FAILURE };
        return feature_log_orchestrator.processPrompt(active, fragment);
    }
    fn reportFailure(context: *anyopaque, shortcode: telemetry.WorkflowShortcode, failure: log_stream.FailureCode) void {
        const self: *Lifecycle = @ptrCast(@alignCast(context));
        if (self.active) |active| _ = active.invokeReportFailure(shortcode, failure);
    }
};
