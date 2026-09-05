const std = @import("std");
const requests = @import("model_request_workflow.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const operation = @import("../domain/workflow_operation.zig");

/// A single pure action call. The runner supplies immutable accounting inputs
/// and publishes the applied attempt; this binding cannot mutate either ledger.
pub const Advance = struct {
    pub const Action = @import("../actions/model/advance_model_attempt_accounting.zig").Action;
    pub const contract: operation.Contract = .{
        .id = Action.contract.id,
        .kind = .step,
        .requires = &.{ .model_request_identity_ledger, .prepared_model_request },
        .produces = &.{.accounted_model_attempt},
        .outcomes = &.{ .ok, .failed },
        .side_effect = Action.contract.side_effect,
        .runner_accounting = Action.contract.runner_accounting,
        .parameters = &.{.{ .id = "retry-limit", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 0, .integer_max = std.math.maxInt(u32) }},
        .retry_limit = .{ .maximum = std.math.maxInt(u32) },
    };
    action: Action = .{},

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const current = @import("pipeline_values.zig").read(&input.step.data, requests.ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
        const facts = input.step.model_attempt orelse return error.OperationExecutionFailed;
        const delta = self.action.execute(facts.accounting, facts.accounting.revision(), current, facts.operations, current.revision(), request.id(), facts.attempt) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }
};
