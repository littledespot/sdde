//! Production event projection through the existing logging barrier. No execution or policy decisions.
const std = @import("std");
const t = @import("../domain/telemetry.zig");
const execution = @import("../domain/workflow_execution.zig");
const workflow = @import("../domain/workflow.zig");
const stream = @import("../domain/feature_log_stream.zig");
pub const Model = struct {
    origin: @import("../domain/model_candidate_origin.zig").Origin,
    binding: @import("../domain/llm_provider_binding.zig").ValidatedProviderModelBinding,
};
pub const Capture = struct {
    barrier: @import("../ports/telemetry_barrier.zig").Barrier,
    shortcode: t.WorkflowShortcode,

    pub fn emit(self: Capture, fact: t.TelemetryFact) ?stream.FailureCode {
        return switch (self.barrier.process(.{ .workflow_shortcode = self.shortcode, .fact = fact })) {
            .persisted, .dropped => null,
            .blocked => |failure| failure,
        };
    }
    pub fn action(self: Capture, node: workflow.WorkflowStepId, result: ?execution.Applied) ?stream.FailureCode {
        var code: [96]u8 = undefined;
        return self.emit(.{
            .event_type = if (result) |value| switch (value.status()) {
                .ok, .more, .needs_user => .action_completed,
                .invalid => .action_invalid,
                .failed, .blocked, .cancelled => .action_failed,
            } else .action_started,
            .node_id = t.Identifier.validate(node.bytes) orelse return .LOG_SERIALIZATION_FAILURE,
            .fields = if (result) |value| .{
                .outcome = outcome(value.status()),
                .diagnostic_code = switch (value.status()) {
                    .ok, .more, .needs_user => null,
                    else => diagnostic(&code, if (value == .rejected) value.rejected.diagnostic() else @tagName(value.outcome)) orelse return .LOG_SERIALIZATION_FAILURE,
                },
            } else .{},
        });
    }
    pub fn model(self: Capture, node: workflow.WorkflowStepId, info: Model, event: t.EventType, status: ?workflow.OutcomeTag, reason: ?[]const u8, usage: ?@import("../domain/llm_provider_operation.zig").ProviderUsage) ?stream.FailureCode {
        var correlation: [96]u8 = undefined;
        var code: [96]u8 = undefined;
        const id = @import("../domain/model_call_lineage.zig").callId(&correlation, info.origin) catch return .LOG_SERIALIZATION_FAILURE;
        return self.emit(.{
            .event_type = event,
            .node_id = t.Identifier.validate(node.bytes) orelse return .LOG_SERIALIZATION_FAILURE,
            .correlation_id = .{ .bytes = id },
            .attempt = info.origin.attempt.value,
            .fields = .{
                .model_route_id = t.Identifier.validate(info.binding.operation_id.workflow_step_id.bytes) orelse return .LOG_SERIALIZATION_FAILURE,
                .model_profile_id = t.Identifier.validate(info.binding.slot_id.bytes) orelse return .LOG_SERIALIZATION_FAILURE,
                .outcome = if (status) |value| outcome(value) else null,
                .diagnostic_code = if (reason) |value| diagnostic(&code, value) orelse return .LOG_SERIALIZATION_FAILURE else null,
                .input_tokens = if (usage) |value| value.input_tokens else null,
                .output_tokens = if (usage) |value| value.output_tokens else null,
            },
        });
    }
    pub fn validation(self: Capture, node: workflow.WorkflowStepId, status: workflow.OutcomeTag, reason: ?[]const u8, origin: ?@import("../domain/model_candidate_origin.zig").Origin) ?stream.FailureCode {
        var code: [96]u8 = undefined;
        var correlation: [96]u8 = undefined;
        const id = if (origin) |value| @import("../domain/model_call_lineage.zig").callId(&correlation, value) catch return .LOG_SERIALIZATION_FAILURE else null;
        return self.emit(.{ .event_type = if (reason != null) .validation_failed else .validation_completed, .node_id = .{ .bytes = node.bytes }, .correlation_id = if (id) |value| .{ .bytes = value } else null, .attempt = if (origin) |value| value.attempt.value else null, .fields = .{
            .validator_id = .{ .bytes = node.bytes },
            .outcome = outcome(status),
            .diagnostic_code = if (reason) |value| diagnostic(&code, value) orelse return .LOG_SERIALIZATION_FAILURE else null,
        } });
    }
    pub fn repair(self: Capture, node: workflow.WorkflowStepId, event: t.EventType, status: workflow.OutcomeTag, reason: ?[]const u8) ?stream.FailureCode {
        var code: [96]u8 = undefined;
        return self.emit(.{ .event_type = event, .node_id = .{ .bytes = node.bytes }, .fields = .{
            .outcome = if (event == .repair_requested) null else outcome(status),
            .repair_unit_kind = if (event == .repair_applied) null else .authorized_unit,
            .diagnostic_code = if (reason) |value| diagnostic(&code, value) orelse return .LOG_SERIALIZATION_FAILURE else null,
        } });
    }
    pub fn terminal(self: Capture, value: @import("../domain/run_outcome.zig").Outcome) ?stream.FailureCode {
        const status = value.executionStatus() orelse .failed;
        if (status == .more) return .LOG_SERIALIZATION_FAILURE;
        var code: [96]u8 = undefined;
        return self.emit(.{ .event_type = switch (status) {
            .ok => .run_completed,
            .more => unreachable,
            .needs_user => .stage_clarification_pending,
            .blocked => .run_blocked,
            .cancelled => .run_cancelled,
            .invalid, .failed => .run_failed,
        }, .fields = .{ .outcome = outcome(status), .diagnostic_code = switch (status) {
            .ok, .needs_user, .cancelled => null,
            else => diagnostic(&code, if (value == .execution_rejected) value.execution_rejected.diagnostic() else @tagName(status)) orelse return .LOG_SERIALIZATION_FAILURE,
        } } });
    }
    pub fn retryAttempt(self: Capture, node: workflow.WorkflowStepId, count: u64, exhausted: bool) ?stream.FailureCode {
        return self.emit(.{ .event_type = if (exhausted) .retry_exhausted else .retry_admitted, .node_id = .{ .bytes = node.bytes }, .fields = .{
            .count = count,
            .outcome = if (exhausted) .failed else null,
            .diagnostic_code = if (exhausted) .{ .bytes = "RETRY_LIMIT_EXHAUSTED" } else null,
        } });
    }
};
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
fn diagnostic(buffer: []u8, value: []const u8) ?t.DiagnosticCode {
    if (value.len > buffer.len) return null;
    for (value, buffer[0..value.len]) |byte, *target| target.* = std.ascii.toUpper(byte);
    return t.DiagnosticCode.validate(buffer[0..value.len]);
}
