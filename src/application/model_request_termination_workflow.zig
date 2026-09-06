const std = @import("std");
const requests = @import("model_request_workflow.zig");
const values = @import("pipeline_values.zig");
const identity = @import("../domain/model_request_identity.zig");
const selection = @import("../domain/workflow_model_request_lifecycle.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const lifecycle = @import("../domain/provider_operation_lifecycle.zig");

/// Close a request from pre-call rejection, never from YAML assertions.
pub const Terminate = struct {
    pub const Action = @import("../actions/model/advance_model_request_lifecycle.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
        .id = "terminate-model-request",
        .kind = .step,
        .requires = &selection.termination_requires,
        .replaces = Action.contract.replaces,
        .outcomes = &selection.termination_outcomes,
        .side_effect = Action.contract.side_effect,
    };
    allocator: std.mem.Allocator,
    action: Action = .{},

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!@import("../domain/workflow_execution.zig").Candidate {
        const self = context.?;
        const facts = try readCurrent(&input.step.data);
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const current = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
        const operation_ledger = input.step.model_request_lifecycle orelse return error.OperationExecutionFailed;
        const owner = self.action.execute(current, operation_ledger, current.revision(), request.id(), facts.expected_status, .{ .terminal = facts.reason }) catch return error.OperationExecutionFailed;
        errdefer identity.deinitOwner(owner);
        var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
        delta.data_replacements[@intFromEnum(requests.ledger_schema.key)] = requests.adoptLedger(self.allocator, owner) catch return error.OperationExecutionFailed;
        return .{ .outcome = facts.outcome, .delta = delta };
    }
};

pub fn readCurrent(view: *const @import("../domain/pipeline_data.zig").View) operations.Error!selection.Closure {
    const request = try requests.readCurrent(view, requests.prepared_schema);
    const current = values.read(view, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
    const record = current.record(request.id()) orelse return error.OperationExecutionFailed;
    if (record.status == .terminal) return error.OperationExecutionFailed;
    const terminal = values.read(view, @import("workflow_model_accounting.zig").terminal_schema, lifecycle.TerminalOperation) catch return error.OperationExecutionFailed;
    if (terminal.record().id.model_request_id != request.id()) return error.OperationExecutionFailed;
    const source = values.read(view, @import("provider_authorization_workflow.zig").schema, @import("../domain/provider_authorization_result.zig").Result) catch return error.OperationExecutionFailed;
    const outcome = @import("workflow_provider_authorization.zig").validateTerminal(source, terminal.record()) catch return error.OperationExecutionFailed;
    return .{
        .expected_status = record.status,
        .reason = switch (outcome) {
            .failed => if (record.status == .assigned) .not_invoked_authorization_failure else .failed,
            .cancelled => .cancelled,
            .ok, .more, .invalid, .needs_user, .blocked => return error.OperationExecutionFailed,
        },
        .outcome = outcome,
    };
}
