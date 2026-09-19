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
        return .{ .context = self, .process_fn = process, .select_prompt_fn = selectPrompt, .process_prompt_fn = processPrompt, .report_failure_fn = reportFailure };
    }

    fn process(context: *anyopaque, fact: telemetry.WorkflowTelemetryFact) @import("../domain/feature_log_stream.zig").Outcome {
        const self: *LogService = @ptrCast(@alignCast(context));
        return self.lifecycle.barrier().process(fact);
    }
    fn selectPrompt(context: *anyopaque, fragment: @import("../domain/sanitized_prompt_log.zig").SanitizedPromptFragment) bool {
        const self: *LogService = @ptrCast(@alignCast(context));
        // Threshold selection precedes activation and allocation. Missing active
        // storage must still fail closed when capture is required.
        return log_policy.promptCaptureEnabled(self.policy().*) and self.lifecycle.barrier().selectPrompt(fragment);
    }
    fn processPrompt(context: *anyopaque, fragment: @import("../domain/sanitized_prompt_log.zig").SanitizedPromptFragment) @import("../domain/feature_log_stream.zig").Outcome {
        const self: *LogService = @ptrCast(@alignCast(context));
        return self.lifecycle.barrier().processPrompt(fragment);
    }
    fn reportFailure(context: *anyopaque, shortcode: telemetry.WorkflowShortcode, failure: @import("../domain/feature_log_stream.zig").FailureCode) void {
        const self: *LogService = @ptrCast(@alignCast(context));
        self.lifecycle.barrier().reportFailure(shortcode, failure);
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

test "production capture selection respects threshold before feature activation" {
    const std = @import("std");
    const fragment: @import("../domain/sanitized_prompt_log.zig").SanitizedPromptFragment = .{
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("TEST"),
        .node_id = .{ .bytes = "invoke" },
        .attempt = 1,
        .request_id = .{ .bytes = "request-1" },
        .route_id = .{ .bytes = "generate" },
        .model_profile_id = .{ .bytes = "generation" },
        .fragment_id = .{ .bytes = "body-0" },
        .direction = .request,
        .body_class = .complete_body,
        .content = "body",
        .retained_bytes = 4,
        .truncated = false,
        .redacted = false,
    };
    for ([_][]const u8{ "info", "debug", "trace" }, 0..) |level, index| {
        const owner = try log_policy.createValidated(std.testing.allocator, .{ .level = level, .console = false }, try log_policy.canonicalizeConfiguredLevel(level));
        var service = LogService.init(owner);
        defer service.deinit();
        const barrier = service.barrier();
        try std.testing.expectEqual(index != 0, barrier.selectPrompt(fragment));
        if (index != 0) try std.testing.expectEqual(.blocked, std.meta.activeTag(barrier.processPrompt(fragment)));
    }
}
