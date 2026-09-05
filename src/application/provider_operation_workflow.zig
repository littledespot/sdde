const requests = @import("model_request_workflow.zig");
const values = @import("pipeline_values.zig");
const accounting = @import("workflow_model_accounting.zig");
const attempts = @import("../domain/model_attempt_accounting.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const operation = @import("../domain/workflow_operation.zig");
const selection = @import("../domain/workflow_provider_operation.zig");
const lifecycle = @import("../domain/provider_operation_lifecycle.zig");

/// Assignment only. The existing lifecycle action proposes the transition;
/// the runner applies it before publishing any assigned-operation evidence.
pub const Assign = struct {
    pub const Action = @import("../actions/model/advance_provider_operation_lifecycle.zig").Action;
    pub const contract: operation.Contract = .{
        .id = "assign-provider-operation@1",
        .kind = .step,
        .requires = &.{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt },
        .produces = &.{.assigned_provider_operation},
        .outcomes = &.{ .ok, .failed },
        .side_effect = Action.contract.side_effect,
        .runner_accounting = Action.contract.runner_accounting,
        .parameters = &.{selection.kind_parameter},
    };
    action: Action = .{},

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const prepared = request.prepared() orelse return error.OperationExecutionFailed;
        const attempt = values.read(&input.step.data, accounting.schema, attempts.AccountedAttempt) catch return error.OperationExecutionFailed;
        const kind = selection.resolve(input.step.step.parameters) orelse return error.OperationExecutionFailed;
        const facts = input.step.provider_operation orelse return error.OperationExecutionFailed;
        const assignment: lifecycle.Assignment = .{ .binding_id = prepared.binding_id, .model_visible_input_id = prepared.model_visible_input_id };
        const delta = self.action.execute(facts.ledger, facts.authority, facts.ledger.revision(), .{
            .model_request_id = request.id(),
            .model_attempt_ordinal = attempt.ordinal(),
            .kind = kind,
        }, null, switch (kind) {
            .inference => .{ .assign_inference = assignment },
            .input_token_count => .{ .assign_count = assignment },
        }) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }
};
