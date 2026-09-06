const values = @import("pipeline_values.zig");
const accounting = @import("workflow_model_accounting.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const operation = @import("../domain/workflow_operation.zig");
const selection = @import("../domain/workflow_provider_operation.zig");
const lifecycle = @import("../domain/provider_operation_lifecycle.zig");

/// Propose invocation only. The runner owns the lease deadline and publication.
pub const Advance = struct {
    pub const Action = @import("../actions/model/advance_provider_operation_lifecycle.zig").Action;
    pub const contract: operation.Contract = .{
        .id = Action.contract.id,
        .kind = .step,
        .requires = &selection.invocation_requires,
        .produces = &.{.invoked_provider_operation},
        .invalidates = &.{.assigned_provider_operation},
        .outcomes = &.{ .ok, .failed },
        .side_effect = Action.contract.side_effect,
        .runner_accounting = Action.contract.runner_accounting,
        .parameters = &.{selection.invocation_parameter},
    };
    action: Action = .{},

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        if (!selection.invokesTransition(input.step.step.parameters)) return error.OperationExecutionFailed;
        const assigned = values.read(&input.step.data, accounting.operation_schema, lifecycle.AssignedOperation) catch return error.OperationExecutionFailed;
        const facts = input.step.provider_operation orelse return error.OperationExecutionFailed;
        const invocation = facts.invocation orelse return error.OperationExecutionFailed;
        const record = assigned.record();
        var delta = self.action.execute(facts.ledger, facts.authority, facts.ledger.revision(), record.id, record.revision, .{ .invoke = invocation }) catch return error.OperationExecutionFailed;
        delta.data_invalidations.insert(.assigned_provider_operation);
        return .{ .outcome = .ok, .delta = delta };
    }
};
