const log_decisions = @import("../domain/feature_log_decisions.zig");
const log_stream = @import("../domain/feature_log_stream.zig");
const prompt_log = @import("../domain/sanitized_prompt_log.zig");
const telemetry = @import("../domain/telemetry.zig");
const barrier_port = @import("../ports/telemetry_barrier.zig");
const close_routine = @import("feature_log_close_routine.zig");
const failure_routine = @import("feature_log_failure_routine.zig");
const persist_routine = @import("feature_log_persist_routine.zig");
const prepare_routine = @import("feature_log_prepare_routine.zig");
const prior_finalization_routine = @import("feature_log_prior_finalization_routine.zig");
const retention_routine = @import("feature_log_retention_routine.zig");
const runner_module = @import("feature_log_runner.zig");

pub const Activation = union(enum) { ok, blocked: log_stream.FailureCode, cancelled, invalid };
pub const Finalization = union(enum) { ok, blocked: log_stream.FailureCode, cancelled, invalid };
pub const Retention = union(enum) { ok, blocked: log_stream.FailureCode, cancelled };
pub const PriorFinalization = union(enum) { ok, blocked: log_stream.FailureCode, cancelled };
/// What one prior run's prune takes, named here so the log service, which may import no routine, can pass it on.
pub const RetentionPorts = retention_routine.Ports;
pub const RetentionInputs = retention_routine.Inputs;
/// What the close of one crashed prior run's open tail takes, named here for the same reason.
pub const PriorFinalizationPorts = prior_finalization_routine.Ports;
pub const PriorFinalizationInputs = prior_finalization_routine.Inputs;

/// Owns the one active logging runner used by the common pipeline, and is the only caller of the feature-logging
/// routines (ADR 0032). Artifact activation constructs the runner; this lifecycle installs it, runs the routines on it
/// and reports each routine's stop once: a logging failure through the emergency line, a cancellation not at all.
pub const Lifecycle = struct {
    active: ?*runner_module.Runner = null,

    pub fn barrier(self: *Lifecycle) barrier_port.Barrier {
        return .{ .context = self, .process_fn = onProcess, .select_prompt_fn = onSelectPrompt, .process_prompt_fn = onProcessPrompt, .report_failure_fn = onReportFailure };
    }

    pub fn activate(
        self: *Lifecycle,
        next: *runner_module.Runner,
        shortcode: telemetry.WorkflowShortcode,
    ) Activation {
        if (self.active != null or next.runtime.retired) return .invalid;
        return switch (prepare(next, shortcode)) {
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
        target: *runner_module.Runner,
        shortcode: telemetry.WorkflowShortcode,
    ) Finalization {
        const current = self.active orelse return .invalid;
        if (target != current) return .invalid;
        const outcome = finalize(target, shortcode);
        if (outcome != .invalid) self.active = null;
        return outcome;
    }

    /// Closes one crashed prior run's open tail of one stream before retention runs (ADR 0026). A stop is reported
    /// once through the active logger, as retention's is.
    pub fn finalizePrior(
        self: *Lifecycle,
        ports: PriorFinalizationPorts,
        inputs: PriorFinalizationInputs,
        shortcode: telemetry.WorkflowShortcode,
    ) PriorFinalization {
        const current = self.active orelse return .{ .blocked = .LOG_SINK_FAILURE };
        var diagnostic: prior_finalization_routine.Diagnostic = .{};
        return switch (prior_finalization_routine.run(ports, inputs, &diagnostic)) {
            .closed => .ok,
            .stopped => |stop| switch (stop) {
                .blocked => |failure| .{ .blocked = report(current, shortcode, failure) },
                .cancelled => .cancelled,
            },
        };
    }

    pub fn retainHistorical(
        self: *Lifecycle,
        ports: RetentionPorts,
        inputs: RetentionInputs,
        shortcode: telemetry.WorkflowShortcode,
    ) Retention {
        const current = self.active orelse return .{ .blocked = .LOG_SINK_FAILURE };
        var diagnostic: retention_routine.Diagnostic = .{};
        return switch (retention_routine.run(ports, inputs, &diagnostic)) {
            .ok => .ok,
            .stopped => |stop| switch (stop) {
                .blocked => |failure| .{ .blocked = report(current, shortcode, failure) },
                .cancelled => .cancelled,
            },
        };
    }

    fn onProcess(context: *anyopaque, fact: telemetry.WorkflowTelemetryFact) log_stream.Outcome {
        const self: *Lifecycle = @ptrCast(@alignCast(context));
        const active = self.active orelse return .{ .blocked = .LOG_SINK_FAILURE };
        return processEvent(active, fact);
    }
    fn onSelectPrompt(context: *anyopaque, _: prompt_log.SanitizedPromptFragment) bool {
        const self: *Lifecycle = @ptrCast(@alignCast(context));
        // An absent required active logger fails at persistence, never silently drops.
        const active = self.active orelse return true;
        return log_decisions.capture(active.policy.*) == .capture;
    }
    fn onProcessPrompt(context: *anyopaque, fragment: prompt_log.SanitizedPromptFragment) log_stream.Outcome {
        const self: *Lifecycle = @ptrCast(@alignCast(context));
        const active = self.active orelse return .{ .blocked = .LOG_SINK_FAILURE };
        return processPrompt(active, fragment);
    }
    fn onReportFailure(context: *anyopaque, shortcode: telemetry.WorkflowShortcode, failure: log_stream.FailureCode) void {
        const self: *Lifecycle = @ptrCast(@alignCast(context));
        if (self.active) |active| _ = report(active, shortcode, failure);
    }
};

/// Persists one fact to the event stream through the persist routine, and reports the stop it ends in.
pub fn processEvent(runner: *runner_module.Runner, fact: telemetry.WorkflowTelemetryFact) log_stream.Outcome {
    var diagnostic: persist_routine.Diagnostic = .{};
    const result = persist_routine.run(persistPorts(runner.ports), .{ .allocator = runner.allocator, .policy = runner.policy, .binding = runner.binding }, &runner.runtime, .{ .event = fact }, &diagnostic);
    return outcomeOf(runner, fact.workflow_shortcode, result);
}

/// Persists one prompt fragment to the prompt stream through the persist routine, and reports the stop it ends in.
pub fn processPrompt(runner: *runner_module.Runner, fragment: prompt_log.SanitizedPromptFragment) log_stream.Outcome {
    var diagnostic: persist_routine.Diagnostic = .{};
    const result = persist_routine.run(persistPorts(runner.ports), .{ .allocator = runner.allocator, .policy = runner.policy, .binding = runner.binding }, &runner.runtime, .{ .prompt = fragment }, &diagnostic);
    return outcomeOf(runner, fragment.workflow_shortcode, result);
}

/// Recovers or initializes every enabled stream before the runner can be published as the active observer. A prompt
/// stream that stops leaves the event stream it opened open, which is closed here instead of being left without a
/// trailer; the prompt stop is the one reported, and a stop of that close is not, as the first stop is kept.
pub fn prepare(runner: *runner_module.Runner, shortcode: telemetry.WorkflowShortcode) log_stream.Outcome {
    var diagnostic: prepare_routine.Diagnostic = .{};
    return switch (prepare_routine.run(preparePorts(runner.ports), .{ .allocator = runner.allocator, .policy = runner.policy, .binding = runner.binding }, &runner.runtime, &diagnostic)) {
        .prepared => .dropped,
        .stopped => |stopped| blk: {
            if (stopped.abandon) |abandoned| {
                var close_diagnostic: close_routine.Diagnostic = .{};
                _ = close_routine.run(closePorts(runner.ports), .{ .allocator = runner.allocator, .binding = runner.binding }, &runner.runtime, .{ .abandon = .{ .stream = abandoned.stream, .reading = abandoned.reading } }, &close_diagnostic);
            }
            break :blk stopOutcome(runner, shortcode, stopped.stop);
        },
    };
}

/// Closes both streams of a prepared run and retires it; only a prepared, live run is finalized.
pub fn finalize(runner: *runner_module.Runner, shortcode: telemetry.WorkflowShortcode) Finalization {
    var diagnostic: close_routine.Diagnostic = .{};
    return switch (close_routine.run(closePorts(runner.ports), .{ .allocator = runner.allocator, .binding = runner.binding }, &runner.runtime, .finalize, &diagnostic)) {
        .closed => .ok,
        .invalid => .invalid,
        .stopped => |stop| switch (stop) {
            .blocked => |failure| .{ .blocked = report(runner, shortcode, failure) },
            .cancelled => .cancelled,
        },
    };
}

/// Reports one logging failure through the failure routine, which writes its emergency line once, and returns it.
pub fn report(runner: *runner_module.Runner, shortcode: telemetry.WorkflowShortcode, failure: log_stream.FailureCode) log_stream.FailureCode {
    var diagnostic: failure_routine.Diagnostic = .{};
    _ = failure_routine.run(.{ .emergency = runner.ports.emergency }, shortcode, failure, &diagnostic);
    return failure;
}

fn outcomeOf(runner: *runner_module.Runner, shortcode: telemetry.WorkflowShortcode, result: log_stream.Result) log_stream.Outcome {
    return switch (result) {
        .dropped => .dropped,
        .persisted => |evidence| .{ .persisted = evidence },
        .stopped => |stop| stopOutcome(runner, shortcode, stop),
    };
}

/// A failure is reported once through the emergency line; a cancellation is no logging failure and emits none.
fn stopOutcome(runner: *runner_module.Runner, shortcode: telemetry.WorkflowShortcode, stop: log_stream.Stop) log_stream.Outcome {
    return switch (stop) {
        .blocked => |failure| .{ .blocked = report(runner, shortcode, failure) },
        .cancelled => .cancelled,
    };
}

fn persistPorts(ports: runner_module.Ports) persist_routine.Ports {
    return .{ .clock = ports.clock, .acquirer = ports.acquirer, .recoverer = ports.recoverer, .creator = ports.creator, .rotator = ports.rotator, .appender = ports.appender, .console = ports.console, .releaser = ports.releaser };
}

fn preparePorts(ports: runner_module.Ports) prepare_routine.Ports {
    return .{ .clock = ports.clock, .acquirer = ports.acquirer, .recoverer = ports.recoverer, .creator = ports.creator, .releaser = ports.releaser };
}

fn closePorts(ports: runner_module.Ports) close_routine.Ports {
    return .{ .clock = ports.clock, .acquirer = ports.acquirer, .recoverer = ports.recoverer, .closer = ports.closer, .releaser = ports.releaser };
}
