//! Native failure evidence for a closed advisory request. No workflow-name or
//! slot selector can turn required work into an advisory request.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const handoff = @import("../domain/model_request_handoff.zig");
const identity = @import("../domain/model_request_identity.zig");
const advice = @import("../domain/advisory_completion.zig");
const provider = @import("../domain/llm_provider_operation.zig");
const requests = @import("model_request_workflow.zig");
const values = @import("pipeline_values.zig");
const accounting = @import("workflow_model_accounting.zig");
const observation = @import("provider_observation_workflow.zig");
const operations = @import("../ports/workflow_operation_registry.zig");

pub const Facts = struct {
    request: *const handoff.Request,
    reason: advice.Reason,
    operation: provider.ProviderOperationId,
    origin: ?@import("../domain/model_candidate_origin.zig").Origin,
};

pub fn read(view: *const data.View) operations.Error!Facts {
    return phase(view, .terminal);
}

pub fn closing(view: *const data.View) operations.Error!Facts {
    return phase(view, .invoked);
}

fn phase(view: *const data.View, expected: identity.RequestStatus) operations.Error!Facts {
    const request = try requests.readCurrent(view, requests.prepared_schema);
    if (!advice.eligible(request)) return error.OperationExecutionFailed;
    const ledger = try values.read(view, requests.ledger_schema, identity.ModelRequestIdentityLedger);
    const record = ledger.record(request.id()) orelse return error.OperationExecutionFailed;
    if (record.status != expected or (expected == .terminal and record.terminal_reason != .failed)) return error.OperationExecutionFailed;
    if (accounting.readAdvisoryStop(view)) |receipt| {
        const reason = advice.protocolReason(request, receipt) orelse return error.OperationExecutionFailed;
        const operation = request.protocolCorrection() orelse return error.OperationExecutionFailed;
        return .{ .request = request, .reason = reason, .operation = operation, .origin = @import("../domain/model_candidate_origin.zig").Origin.from(ledger, operation) };
    } else |_| {}
    const source = if (view.contains(observation.schema.key)) try observation.readCurrent(view) else (try @import("model_payload_schema_workflow.zig").readCurrent(view)).source().source();
    const attempt = try accounting.readAttempt(view);
    if (attempt.requestId() != request.id() or source.operationId().model_attempt_ordinal.value != attempt.ordinal().value) return error.OperationExecutionFailed;
    const stop = switch (source.outcome()) {
        .advisory_stopped => |stop| stop,
        else => return error.OperationExecutionFailed,
    };
    const operation = source.operationId();
    return .{ .request = request, .reason = stop.reason, .operation = operation, .origin = @import("../domain/model_candidate_origin.zig").Origin.from(ledger, operation) };
}

pub fn permitsAbandonment(view: *const data.View, request: *const handoff.Request) bool {
    const facts = read(view) catch return false;
    return facts.request == request and request.packet() != null and request.packet().?.repairPermit() != null;
}
