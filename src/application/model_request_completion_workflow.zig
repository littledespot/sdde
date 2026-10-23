const std = @import("std");
const requests = @import("model_request_workflow.zig");
const values = @import("pipeline_values.zig");
const identity = @import("../domain/model_request_identity.zig");
const selection = @import("../domain/workflow_model_request_lifecycle.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const payload = @import("model_payload_schema_workflow.zig");
const lifecycle = @import("../domain/provider_operation_lifecycle.zig");

/// Close this request only. The candidate retains no semantic or commit authority.
pub const Complete = struct {
    pub const Action = @import("../actions/model/advance_model_request_lifecycle.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
        .id = "complete-model-request",
        .kind = .step,
        .requires = &selection.completion_requires,
        .replaces = Action.contract.replaces,
        .outcomes = &selection.completion_outcomes,
        .side_effect = Action.contract.side_effect,
        .outcome_association = .{ .request_closure = .{ .kind = .request, .subject = .prepared_model_request, .evidence = .model_payload_schema_result } },
    };
    allocator: std.mem.Allocator,
    action: Action = .{},

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!@import("../domain/workflow_execution.zig").Candidate {
        const self = context.?;
        const facts = try readCurrent(&input.step.data);
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const current = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch |operation_error| return operation_error;
        const operation_ledger = input.step.model_request_lifecycle orelse return error.OperationExecutionFailed;
        const owner = self.action.execute(current, operation_ledger, current.revision(), request.id(), facts.expected_status, .{ .terminal = facts.reason }) catch |operation_error| return operation_error;
        errdefer identity.deinitOwner(owner);
        var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
        delta.data_replacements[@intFromEnum(requests.ledger_schema.key)] = requests.adoptLedger(self.allocator, owner) catch |operation_error| return operation_error;
        return .{ .outcome = facts.outcome, .delta = delta };
    }
};

/// Sealed result association only; no second parsing, validation or token charge.
pub fn readCurrent(view: *const @import("../domain/pipeline_data.zig").View) operations.Error!selection.Closure {
    if (@import("workflow_model_accounting.zig").readAdvisoryStop(view)) |receipt| {
        return @import("advisory_protocol_request_completion_workflow.zig").readCurrent(view, receipt);
    } else |_| {}
    const result = try payload.readCurrent(view);
    const source = result.source().source();
    const terminal = values.read(view, @import("workflow_model_accounting.zig").terminal_schema, lifecycle.TerminalOperation) catch |operation_error| return operation_error;
    if (!terminal.record().id.eql(source.operationId()) or source.outcome() == .rejected) return error.OperationExecutionFailed;
    const current = values.read(view, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch |operation_error| return operation_error;
    const record = current.record(source.operationId().model_request_id) orelse return error.OperationExecutionFailed;
    if (record.status != .invoked) return error.OperationExecutionFailed;
    const outcome = payload.status(result);
    return .{
        .expected_status = .invoked,
        .reason = switch (outcome) {
            .ok => .accepted,
            // Explicit closure abandons invalid content; it does not assert retry exhaustion.
            .invalid, .failed => .failed,
            .more => deferred: {
                _ = try @import("advisory_request_completion_workflow.zig").closing(view);
                break :deferred .failed;
            },
            .cancelled => .cancelled,
            .needs_user, .blocked => return error.OperationExecutionFailed,
        },
        .outcome = outcome,
    };
}
