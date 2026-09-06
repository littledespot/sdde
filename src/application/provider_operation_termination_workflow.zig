const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const lifecycle = @import("../domain/provider_operation_lifecycle.zig");
const data = @import("../domain/pipeline_data.zig");
const values = @import("pipeline_values.zig");
const accounting = @import("workflow_model_accounting.zig");
const authorization = @import("provider_authorization_workflow.zig");
const result = @import("../domain/provider_authorization_result.zig");
const selection = @import("../domain/workflow_provider_operation.zig");

/// Terminate an uninvoked operation from retained authorization rejection only.
pub const Terminate = struct {
    pub const Action = @import("../actions/model/advance_provider_operation_lifecycle.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
        .id = "terminate-provider-operation",
        .kind = .step,
        .requires = &selection.termination_requires,
        .produces = &.{.terminal_provider_operation},
        .invalidates = &.{.assigned_provider_operation},
        .outcomes = &selection.termination_outcomes,
        .side_effect = Action.contract.side_effect,
        .runner_accounting = Action.contract.runner_accounting,
    };
    action: Action = .{},

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const facts = try readCurrent(&input.step.data);
        const authority = input.step.provider_operation orelse return error.OperationExecutionFailed;
        const record = facts.source.assigned.record();
        var delta = self.action.execute(authority.ledger, authority.authority, authority.ledger.revision(), record.id, record.revision, .{ .terminate = facts.terminal }) catch return error.OperationExecutionFailed;
        delta.data_invalidations.insert(.assigned_provider_operation);
        return .{ .outcome = facts.outcome, .delta = delta };
    }
};

pub fn readCurrent(view: *const data.View) operations.Error!accounting.Completion {
    const assigned = values.read(view, accounting.operation_schema, lifecycle.AssignedOperation) catch return error.OperationExecutionFailed;
    const source = values.read(view, authorization.schema, result.Result) catch return error.OperationExecutionFailed;
    const id = assigned.record().id;
    return switch (source.outcome().*) {
        .failed => |failure| failed: {
            @import("workflow_provider_authorization.zig").validateFailure(failure, id) catch return error.OperationExecutionFailed;
            break :failed .{ .source = .{ .assigned = assigned }, .terminal = .{ .preparation_failed = failure }, .outcome = .failed };
        },
        .cancelled => |cancelled| if (cancelled.eql(id))
            .{ .source = .{ .assigned = assigned }, .terminal = .{ .cancelled = .not_sent }, .outcome = .cancelled }
        else
            error.OperationExecutionFailed,
        .prepared => error.OperationExecutionFailed,
    };
}
