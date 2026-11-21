//! Production event projection through the existing logging barrier. No execution or policy decisions.
const std = @import("std");
const t = @import("../domain/telemetry.zig");
const execution = @import("../domain/workflow_execution.zig");
const workflow = @import("../domain/workflow.zig");
const stream = @import("../domain/feature_log_stream.zig");
const ProviderUsage = @import("../domain/llm_provider_operation.zig").ProviderUsage;
const RunOutcome = @import("../domain/run_outcome.zig").Outcome;
pub const Model = struct {
    origin: @import("../domain/model_candidate_origin.zig").Origin,
    binding: @import("../domain/llm_provider_binding.zig").ValidatedProviderModelBinding,
};
/// A refused value: the outcome it ended with and the closed reason that names it.
pub const Rejection = struct {
    status: workflow.OutcomeTag,
    reason: []const u8,
};
/// One event of one model call, holding exactly what its F0002 row takes.
pub const ModelEvent = union(enum) {
    requested,
    completed: struct { status: workflow.OutcomeTag, usage: ?ProviderUsage },
    /// The closed name of the normalization.
    response_normalized: []const u8,
    provider_stopped: struct { status: workflow.OutcomeTag, reason: []const u8, usage: ProviderUsage },
    /// The closed reason of the runaway's stop, and the usage its attempt reported.
    runaway_resent: struct { reason: []const u8, usage: ?ProviderUsage },
    protocol_failed: Rejection,
    schema_failed: Rejection,
};
/// One event of one repair, holding exactly what its F0002 row takes.
pub const RepairEvent = union(enum) {
    requested,
    applied: workflow.OutcomeTag,
    rejected: Rejection,
};
/// An event no safe record can be built for is a logging failure, not a cancellation.
const serialization_failure: stream.Stop = .{ .blocked = .LOG_SERIALIZATION_FAILURE };
pub const Capture = struct {
    barrier: @import("../ports/telemetry_barrier.zig").Barrier,
    shortcode: t.WorkflowShortcode,

    pub fn emit(self: Capture, fact: t.TelemetryFact) ?stream.Stop {
        return self.barrier.process(.{ .workflow_shortcode = self.shortcode, .fact = fact }).stop();
    }
    /// `stage_step` is the internal step a stage action stopped at (ADR 0031); only a failed
    /// action's event records it.
    pub fn action(self: Capture, node: workflow.WorkflowStepId, result: ?execution.Applied, rejection: ?execution.OperationError, stage_step: ?[]const u8) ?stream.Stop {
        return self.actionEvent(node, result, rejection, .{ .stopped_at = stage_step });
    }

    /// One event of one stage of a `request-model` step (ADR 0030): whatever the stage's status,
    /// the event names the stage, so a report can tell where the request was at any time.
    pub fn requestStage(self: Capture, node: workflow.WorkflowStepId, stage: []const u8, result: ?execution.Applied, rejection: ?execution.OperationError) ?stream.Stop {
        return self.actionEvent(node, result, rejection, .{ .stage = stage });
    }

    /// The internal step an action event names.
    const Internal = union(enum) {
        /// A stage action's internal step (ADR 0031): only a failed event records it.
        stopped_at: ?[]const u8,
        /// A stage of a `request-model` step (ADR 0030): every event of the stage records it.
        stage: []const u8,
    };

    fn actionEvent(self: Capture, node: workflow.WorkflowStepId, result: ?execution.Applied, rejection: ?execution.OperationError, internal: Internal) ?stream.Stop {
        var code: [96]u8 = undefined;
        const named: ?t.Identifier = switch (internal) {
            .stage => |name| t.Identifier.validate(name) orelse return serialization_failure,
            .stopped_at => |step| if (result) |value| switch (value.status()) {
                .failed, .blocked, .cancelled => if (step) |name| t.Identifier.validate(name) orelse return serialization_failure else null,
                else => null,
            } else null,
        };
        const node_id = t.Identifier.validate(node.bytes) orelse return serialization_failure;
        const applied = result orelse return self.emit(.{ .action_started = .{ .node_id = node_id, .step_id = named } });
        const status = outcome(applied.status());
        return switch (applied.status()) {
            .ok, .more, .needs_user => self.emit(.{ .action_completed = .{ .node_id = node_id, .outcome = status, .step_id = named } }),
            .invalid => self.emit(.{ .action_invalid = .{
                .node_id = node_id,
                .outcome = status,
                .diagnostic_code = actionCode(&code, applied, rejection) orelse return serialization_failure,
                .step_id = named,
            } }),
            .failed, .blocked, .cancelled => self.emit(.{ .action_failed = .{
                .node_id = node_id,
                .outcome = status,
                .diagnostic_code = actionCode(&code, applied, rejection) orelse return serialization_failure,
                .step_id = named,
            } }),
        };
    }

    /// The diagnostic code of an action that did not complete.
    fn actionCode(buffer: []u8, value: execution.Applied, rejection: ?execution.OperationError) ?t.DiagnosticCode {
        if (value == .rejected) return rejectionCode(buffer, value.rejected);
        return diagnostic(buffer, if (rejection) |cause| @errorName(cause) else @tagName(value.outcome));
    }

    pub fn model(self: Capture, node: workflow.WorkflowStepId, info: Model, event: ModelEvent) ?stream.Stop {
        var correlation: [96]u8 = undefined;
        var code: [96]u8 = undefined;
        const id = @import("../domain/model_call_lineage.zig").callId(&correlation, info.origin) catch return serialization_failure;
        const node_id = t.Identifier.validate(node.bytes) orelse return serialization_failure;
        const route = t.Identifier.validate(info.binding.operation_id.workflow_step_id.bytes) orelse return serialization_failure;
        const profile = t.Identifier.validate(info.binding.slot_id.bytes) orelse return serialization_failure;
        const call_id: t.Identifier = .{ .bytes = id };
        const attempt = info.origin.attempt.value;
        return self.emit(switch (event) {
            .requested => .{ .model_requested = .{
                .node_id = node_id,
                .correlation_id = call_id,
                .attempt = attempt,
                .model_route_id = route,
                .model_profile_id = profile,
            } },
            .completed => |completed| .{ .model_completed = .{
                .node_id = node_id,
                .correlation_id = call_id,
                .attempt = attempt,
                .model_route_id = route,
                .model_profile_id = profile,
                .outcome = outcome(completed.status),
                .input_tokens = if (completed.usage) |usage| usage.input_tokens else null,
                .output_tokens = if (completed.usage) |usage| usage.output_tokens else null,
            } },
            .response_normalized => |reason| .{ .model_response_normalized = .{
                .node_id = node_id,
                .correlation_id = call_id,
                .attempt = attempt,
                .model_route_id = route,
                .model_profile_id = profile,
                .diagnostic_code = diagnostic(&code, reason) orelse return serialization_failure,
            } },
            .provider_stopped => |stopped| .{ .model_provider_stopped = .{
                .node_id = node_id,
                .correlation_id = call_id,
                .attempt = attempt,
                .model_route_id = route,
                .model_profile_id = profile,
                .outcome = outcome(stopped.status),
                .diagnostic_code = diagnostic(&code, stopped.reason) orelse return serialization_failure,
                .input_tokens = stopped.usage.input_tokens,
                .output_tokens = stopped.usage.output_tokens,
            } },
            .runaway_resent => |resent| .{ .model_runaway_resent = .{
                .node_id = node_id,
                .correlation_id = call_id,
                .attempt = attempt,
                .model_route_id = route,
                .model_profile_id = profile,
                .diagnostic_code = diagnostic(&code, resent.reason) orelse return serialization_failure,
                .input_tokens = if (resent.usage) |usage| usage.input_tokens else null,
                .output_tokens = if (resent.usage) |usage| usage.output_tokens else null,
            } },
            .protocol_failed => |rejected| .{ .model_protocol_failed = .{
                .node_id = node_id,
                .correlation_id = call_id,
                .attempt = attempt,
                .model_route_id = route,
                .model_profile_id = profile,
                .outcome = outcome(rejected.status),
                .diagnostic_code = diagnostic(&code, rejected.reason) orelse return serialization_failure,
            } },
            .schema_failed => |rejected| .{ .model_schema_failed = .{
                .node_id = node_id,
                .correlation_id = call_id,
                .attempt = attempt,
                .model_route_id = route,
                .model_profile_id = profile,
                .outcome = outcome(rejected.status),
                .diagnostic_code = diagnostic(&code, rejected.reason) orelse return serialization_failure,
            } },
        });
    }
    pub fn validation(self: Capture, node: workflow.WorkflowStepId, status: workflow.OutcomeTag, reason: ?[]const u8, origin: ?@import("../domain/model_candidate_origin.zig").Origin) ?stream.Stop {
        var code: [96]u8 = undefined;
        var correlation: [96]u8 = undefined;
        const id = if (origin) |value| @import("../domain/model_call_lineage.zig").callId(&correlation, value) catch return serialization_failure else null;
        const correlation_id: ?t.Identifier = if (id) |value| .{ .bytes = value } else null;
        const attempt: ?u64 = if (origin) |value| value.attempt.value else null;
        const validator: t.Identifier = .{ .bytes = node.bytes };
        return self.emit(if (reason) |value| .{ .validation_failed = .{
            .node_id = validator,
            .correlation_id = correlation_id,
            .attempt = attempt,
            .validator_id = validator,
            .outcome = outcome(status),
            .diagnostic_code = diagnostic(&code, value) orelse return serialization_failure,
        } } else .{ .validation_completed = .{
            .node_id = validator,
            .correlation_id = correlation_id,
            .attempt = attempt,
            .validator_id = validator,
            .outcome = outcome(status),
        } });
    }
    pub fn repair(self: Capture, node: workflow.WorkflowStepId, event: RepairEvent) ?stream.Stop {
        var code: [96]u8 = undefined;
        const node_id: t.Identifier = .{ .bytes = node.bytes };
        return self.emit(switch (event) {
            .requested => .{ .repair_requested = .{ .node_id = node_id, .repair_unit_kind = .authorized_unit } },
            .applied => |status| .{ .repair_applied = .{ .node_id = node_id, .repair_unit_kind = .authorized_unit, .outcome = outcome(status) } },
            .rejected => |rejected| .{ .repair_rejected = .{
                .node_id = node_id,
                .repair_unit_kind = .authorized_unit,
                .outcome = outcome(rejected.status),
                .diagnostic_code = diagnostic(&code, rejected.reason) orelse return serialization_failure,
            } },
        });
    }
    pub fn terminal(self: Capture, value: RunOutcome) ?stream.Stop {
        const status = value.executionStatus() orelse .failed;
        if (status == .more) return serialization_failure;
        var code: [96]u8 = undefined;
        var correlation: [96]u8 = undefined;
        const captured = if (value == .execution_rejected and value.execution_rejected == .model_capture) value.execution_rejected.model_capture else null;
        const origin = if (captured) |failure| failure.origin else null;
        const call_id = if (origin) |call| @import("../domain/model_call_lineage.zig").callId(&correlation, call) catch return serialization_failure else null;
        const correlation_id: ?t.Identifier = if (call_id) |id| .{ .bytes = id } else null;
        const attempt: ?u64 = if (origin) |call| call.attempt.value else null;
        const ended = outcome(status);
        return self.emit(switch (status) {
            .ok => .{ .run_completed = .{ .correlation_id = correlation_id, .attempt = attempt, .outcome = ended } },
            .more => unreachable,
            .needs_user => .{ .stage_clarification_pending = .{ .correlation_id = correlation_id, .attempt = attempt, .outcome = ended } },
            .cancelled => .{ .run_cancelled = .{ .correlation_id = correlation_id, .attempt = attempt, .outcome = ended } },
            .blocked => .{ .run_blocked = .{
                .correlation_id = correlation_id,
                .attempt = attempt,
                .outcome = ended,
                .diagnostic_code = terminalCode(&code, value, status) orelse return serialization_failure,
            } },
            .invalid, .failed => .{ .run_failed = .{
                .correlation_id = correlation_id,
                .attempt = attempt,
                .outcome = ended,
                .diagnostic_code = terminalCode(&code, value, status) orelse return serialization_failure,
            } },
        });
    }

    /// The diagnostic code of a run that did not complete.
    fn terminalCode(buffer: []u8, value: RunOutcome, status: workflow.OutcomeTag) ?t.DiagnosticCode {
        if (value == .execution_rejected) return rejectionCode(buffer, value.execution_rejected);
        return diagnostic(buffer, @tagName(status));
    }
    pub fn retryAttempt(self: Capture, node: workflow.WorkflowStepId, count: u64, exhausted: bool) ?stream.Stop {
        const node_id: t.Identifier = .{ .bytes = node.bytes };
        return self.emit(if (exhausted) .{ .retry_exhausted = .{
            .node_id = node_id,
            .count = count,
            .outcome = .failed,
            .diagnostic_code = .{ .bytes = "RETRY_LIMIT_EXHAUSTED" },
        } } else .{ .retry_admitted = .{ .node_id = node_id, .count = count } });
    }
};
fn rejectionCode(buffer: []u8, reason: execution.Rejection) ?t.DiagnosticCode {
    if (reason == .model_capture) {
        const code = reason.model_capture.diagnosticWithCause(buffer) catch return null;
        return t.DiagnosticCode.validate(code);
    }
    return diagnostic(buffer, reason.diagnostic());
}
pub fn outcome(value: workflow.OutcomeTag) t.EventOutcome {
    return switch (value) {
        .ok, .more => .completed,
        .needs_user => .needs_user,
        .invalid => .invalid,
        .blocked => .blocked,
        .failed => .failed,
        .cancelled => .cancelled,
    };
}
/// The diagnostic code an event records for a tag or error name.
pub fn diagnostic(buffer: []u8, value: []const u8) ?t.DiagnosticCode {
    if (value.len > buffer.len) return null;
    for (value, buffer[0..value.len]) |byte, *target| target.* = std.ascii.toUpper(byte);
    return t.DiagnosticCode.validate(buffer[0..value.len]);
}
