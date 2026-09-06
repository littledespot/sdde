const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const pipeline = @import("../domain/pipeline.zig");
const execution = @import("../domain/workflow_execution.zig");
const result = @import("../domain/model_invocation_result.zig");
const lifecycle = @import("../domain/provider_operation_lifecycle.zig");
const identity = @import("../domain/model_request_identity.zig");
const requests = @import("model_request_workflow.zig");
const values = @import("pipeline_values.zig");
const accounting = @import("workflow_model_accounting.zig");
const authorization = @import("provider_authorization_workflow.zig");
const selection = @import("../domain/workflow_model_invocation.zig");

pub const schema = values.schema(.provider_invocation_result, result.Result, 1, null);

pub const Invoke = struct {
    pub const Action = @import("../actions/model/invoke_model.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
        .id = Action.contract.id,
        .kind = .step,
        .requires = &selection.requires,
        .produces = &selection.produces,
        .outcomes = &.{ .ok, .failed, .cancelled },
        .side_effect = Action.contract.side_effect,
    };
    allocator: std.mem.Allocator,
    // A missing adapter fails closed; production never substitutes a fake.
    action: ?Action = null,

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const prepared = request.prepared() orelse return error.OperationExecutionFailed;
        const invoked = (values.read(&input.step.data, accounting.invoked_schema, lifecycle.InvokedOperation) catch return error.OperationExecutionFailed).operation();
        const authorization_result = values.read(&input.step.data, authorization.schema, @import("../domain/provider_authorization_result.zig").Result) catch return error.OperationExecutionFailed;
        const reference = switch (authorization_result.outcome().*) {
            .prepared => |*reference| reference,
            .failed, .cancelled => return error.OperationExecutionFailed,
        };
        const ledger = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
        const owner = result.Owner.init(self.allocator, ledger, invoked.id) catch return error.OperationExecutionFailed;
        const value = values.adopt(self.allocator, schema, result.Result, result.Owner, owner, result.Owner.view, result.Owner.destroy, null) catch {
            owner.destroy();
            return error.OperationExecutionFailed;
        };
        const outcome: result.Outcome = if (self.action) |action| call: {
            const observed = action.execute(request.binding(), prepared, reference, invoked) catch |err| break :call switch (err) {
                error.Cancelled => .cancelled,
                error.OutOfMemory => .allocation_failed,
            };
            break :call .{ .observation = observed };
        } else .{ .observation = .{ .failed = .{ .operation_id = invoked.id, .cause = .authorization_denied, .retry_class = .never, .delivery = .not_sent } } };
        owner.finish(outcome);
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(schema.key)] = value;
        return .{ .outcome = status(outcome), .delta = delta };
    }
};

pub fn status(outcome: result.Outcome) @import("../domain/workflow.zig").OutcomeTag {
    return switch (outcome) {
        .observation => |observation| switch (observation) {
            .completed => |completed| switch (completed.raw_result) {
                .complete => .ok,
                .stopped => .failed,
            },
            .failed => .failed,
        },
        .cancelled => .cancelled,
        .allocation_failed => .failed,
    };
}
