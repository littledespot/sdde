const std = @import("std");
const requests = @import("model_request_workflow.zig");
const values = @import("pipeline_values.zig");
const identity = @import("../domain/model_request_identity.zig");
const selection = @import("../domain/workflow_model_request_lifecycle.zig");
const operations = @import("../ports/workflow_operation_registry.zig");

/// One explicit logical-request transition; no operation invocation or retry.
pub const Advance = struct {
    pub const Action = @import("../actions/model/advance_model_request_lifecycle.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
        .id = Action.contract.id,
        .kind = .step,
        .requires = &selection.requires,
        .replaces = Action.contract.replaces,
        .outcomes = &.{ .ok, .failed },
        .side_effect = .none,
        .parameters = &.{selection.parameter},
    };
    allocator: std.mem.Allocator,
    action: Action = .{},

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!@import("../domain/workflow_execution.zig").Candidate {
        const self = context.?;
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const current = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
        const operation_ledger = input.step.model_request_lifecycle orelse return error.OperationExecutionFailed;
        const selected = selection.transition(input.step.step.parameters) orelse return error.OperationExecutionFailed;
        const owner = self.action.execute(current, operation_ledger, current.revision(), request.id(), .assigned, selected) catch return error.OperationExecutionFailed;
        errdefer identity.deinitOwner(owner);
        var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
        delta.data_replacements[@intFromEnum(requests.ledger_schema.key)] = requests.adoptLedger(self.allocator, owner) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }
};
