const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const pipeline = @import("../domain/pipeline.zig");
const execution = @import("../domain/workflow_execution.zig");
const results = @import("../domain/model_invocation_result.zig");
const data = @import("../domain/pipeline_data.zig");
const lifecycle = @import("../domain/provider_operation_lifecycle.zig");
const identity = @import("../domain/model_request_identity.zig");
const requests = @import("model_request_workflow.zig");
const values = @import("pipeline_values.zig");
const accounting = @import("workflow_model_accounting.zig");
const authorization = @import("provider_authorization_workflow.zig");
const selection = @import("../domain/workflow_model_invocation.zig");

pub const schema = values.schema(.provider_invocation_result, results.Result, 1, null).captured();

pub const Invoke = struct {
    pub const Action = @import("../actions/model/invoke_model.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
        .id = Action.contract.id,
        .kind = .step,
        .requires = &selection.requires,
        .produces = &selection.produces,
        .outcomes = &.{ .ok, .failed, .cancelled },
        .side_effect = Action.contract.side_effect,
        .outcome_association = .{ .observe = .{ .kind = .request, .subject = .prepared_model_request, .evidence = schema.key } },
    };
    allocator: std.mem.Allocator,
    // A missing adapter fails closed; production never substitutes a fake.
    action: ?Action = null,

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const prepared = request.prepared() orelse return error.OperationExecutionFailed;
        const invoked = (values.read(&input.step.data, accounting.invoked_schema, lifecycle.InvokedOperation) catch |operation_error| return operation_error).operation();
        const authorization_result = values.read(&input.step.data, authorization.schema, @import("../domain/provider_authorization_result.zig").Result) catch |operation_error| return operation_error;
        const reference = switch (authorization_result.outcome().*) {
            .prepared => |*reference| reference,
            .failed, .cancelled => return error.OperationExecutionFailed,
        };
        const ledger = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch |operation_error| return operation_error;
        const owner = self.allocator.create(Owner) catch |operation_error| return operation_error;
        errdefer self.allocator.destroy(owner);
        const retained = values.retain(input.step.data.slots[@intFromEnum(requests.prepared_schema.key)].?) catch |operation_error| return operation_error;
        errdefer values.destroy(retained);
        owner.* = .{ .allocator = self.allocator, .request = retained, .response = results.Owner.init(self.allocator, ledger, invoked.id) catch |operation_error| return operation_error };
        const value = values.adopt(self.allocator, schema, results.Result, Owner, owner, Owner.view, Owner.destroy, null) catch |native_failure| {
            owner.response.destroy();
            return native_failure;
        };
        const outcome: results.Outcome = if (self.action) |action| call: {
            const observed = action.execute(request.binding(), prepared, reference, invoked) catch |err| break :call switch (err) {
                error.Cancelled => .cancelled,
                error.OutOfMemory => .allocation_failed,
                error.ModelLoggingBlocked => .logging_blocked_before_send,
            };
            break :call .{ .observation = observed };
        } else .{ .observation = .{ .failed = .{ .operation_id = invoked.id, .cause = .authorization_denied, .retry_class = .never, .delivery = .not_sent } } };
        owner.response.finish(outcome);
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(schema.key)] = value;
        return .{ .outcome = status(outcome), .delta = delta };
    }
    const Owner = struct {
        allocator: std.mem.Allocator,
        request: *data.Value,
        response: *results.Owner,
        fn view(self: *const Owner) *const results.Result {
            return self.response.view();
        }
        fn destroy(self: *Owner) void {
            self.response.destroy();
            values.destroy(self.request);
            self.allocator.destroy(self);
        }
    };
};

pub fn status(outcome: results.Outcome) @import("../domain/workflow.zig").OutcomeTag {
    return switch (outcome) {
        .observation => |observation| switch (observation) {
            .completed => |completed| switch (completed.raw_result) {
                .complete => .ok,
                .stopped, .rejected => .failed,
            },
            .failed => .failed,
        },
        .cancelled => .cancelled,
        .allocation_failed, .logging_blocked_before_send => .failed,
    };
}
