const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const lifecycle = @import("../domain/provider_operation_lifecycle.zig");
const data = @import("../domain/pipeline_data.zig");
const values = @import("pipeline_values.zig");
const accounting = @import("workflow_model_accounting.zig");
const observation = @import("provider_observation_workflow.zig");

pub const Complete = struct {
    pub const Action = @import("../actions/model/advance_provider_operation_lifecycle.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
        .id = "complete-provider-operation",
        .kind = .step,
        .requires = &@import("../domain/workflow_provider_operation.zig").completion_requires,
        .produces = &.{.terminal_provider_operation},
        .invalidates = &.{.invoked_provider_operation},
        .outcomes = &.{ .ok, .failed, .cancelled },
        .side_effect = Action.contract.side_effect,
        .runner_accounting = Action.contract.runner_accounting,
    };
    action: Action = .{},

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const facts = try readCurrent(&input.step.data);
        const authority = input.step.provider_operation orelse return error.OperationExecutionFailed;
        const record = authority.ledger.record(facts.source.id()) orelse return error.OperationExecutionFailed;
        var delta = self.action.execute(authority.ledger, authority.authority, authority.ledger.revision(), record.id, record.revision, .{ .terminate = facts.terminal }) catch return error.OperationExecutionFailed;
        delta.data_invalidations.insert(.invoked_provider_operation);
        return .{ .outcome = facts.outcome, .delta = delta };
    }
};

/// Derived from the sealed observation, never parameters or model claims.
pub fn readCurrent(view: *const data.View) operations.Error!accounting.Completion {
    const source = try observation.readCurrent(view);
    const invoked = (values.read(view, accounting.invoked_schema, lifecycle.InvokedOperation) catch return error.OperationExecutionFailed).operation();
    if (!source.operationId().eql(invoked.id) or invoked.id.kind != .inference) return error.OperationExecutionFailed;
    const terminal: lifecycle.Terminal = switch (source.outcome()) {
        .validated => |evidence| switch (evidence.result()) {
            .complete => .completed,
            .stopped => |reason| .{ .stopped = reason },
            .failed => |failure| .{ .failed = failure },
        },
        // Cancellation carries no proof of non-delivery or a received response.
        .cancelled => .{ .cancelled = .accepted_or_unknown },
        .rejected => return error.OperationExecutionFailed,
    };
    return .{ .source = .{ .invoked = invoked }, .terminal = terminal, .outcome = observation.status(source) };
}
