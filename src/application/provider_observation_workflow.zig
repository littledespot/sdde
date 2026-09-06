const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const pipeline = @import("../domain/pipeline.zig");
const execution = @import("../domain/workflow_execution.zig");
const provider = @import("../domain/llm_provider_operation.zig");
const validation = @import("../domain/provider_invocation_validation.zig");
const invocation = @import("../domain/model_invocation_result.zig").For(.inference);
const requests = @import("model_request_workflow.zig");
const model_invocation = @import("model_invocation_workflow.zig");
const data = @import("../domain/pipeline_data.zig");
const values = @import("pipeline_values.zig");

pub const schema = values.schema(.provider_invocation_validation_result, Result, 1, null);
pub const Outcome = union(enum) {
    validated: *const validation.Evidence,
    rejected: validation.ValidationError,
    cancelled,
};

/// Read-only result. Only validated complete evidence exposes a decoder input.
pub const Result = opaque {
    pub fn operationId(self: *const Result) provider.ProviderOperationId {
        return storage(self).operation_id;
    }

    pub fn outcome(self: *const Result) Outcome {
        return switch (storage(self).outcome) {
            .validated => |owned| .{ .validated = owned.evidence },
            .rejected => |reason| .{ .rejected = reason },
            .cancelled => .cancelled,
        };
    }
};

pub const Validate = struct {
    pub const Action = @import("../actions/model/validate_provider_invocation_observation.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
        .id = Action.contract.id,
        .kind = .step,
        .requires = Action.contract.requires,
        .produces = Action.contract.produces,
        .outcomes = &.{ .ok, .failed, .cancelled },
        .side_effect = Action.contract.side_effect,
    };
    allocator: std.mem.Allocator,
    action: Action = .{},

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const call = input.step.provider_invocation orelse return error.OperationExecutionFailed;
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        if (request.prepared() != call.request or request.binding() != call.provider_binding) return error.OperationExecutionFailed;
        const response = values.read(&input.step.data, model_invocation.schema, invocation.Result) catch return error.OperationExecutionFailed;
        const raw = response.outcome() orelse return error.OperationExecutionFailed;
        const owner = self.allocator.create(Owner) catch return error.OperationExecutionFailed;
        errdefer self.allocator.destroy(owner);
        const retained_request = values.retain(input.step.data.slots[@intFromEnum(requests.prepared_schema.key)].?) catch return error.OperationExecutionFailed;
        errdefer values.destroy(retained_request);
        const retained_response = values.retain(input.step.data.slots[@intFromEnum(model_invocation.schema.key)].?) catch return error.OperationExecutionFailed;
        errdefer values.destroy(retained_response);
        owner.* = .{
            .allocator = self.allocator,
            .request = retained_request,
            .response = retained_response,
            .operation_id = call.operation_id,
            .outcome = if (!response.operationId().eql(call.operation_id))
                .{ .rejected = error.ProviderInvocationAssociationInvalid }
            else switch (raw.*) {
                .observation => |*observation| observed: {
                    const evidence = self.action.execute(self.allocator, call, observation) catch |err| break :observed switch (err) {
                        error.OutOfMemory => return error.OperationExecutionFailed,
                        else => |reason| .{ .rejected = reason },
                    };
                    break :observed .{ .validated = evidence };
                },
                .cancelled => .cancelled,
                .allocation_failed => return error.OperationExecutionFailed,
            },
        };
        errdefer owner.releaseEvidence();
        const value = values.adopt(self.allocator, schema, Result, Owner, owner, Owner.view, Owner.destroy, null) catch return error.OperationExecutionFailed;
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(schema.key)] = value;
        return .{ .outcome = status(owner.view()), .delta = delta };
    }
};

/// Bind a consumer to the original sealed result, without repeating provider validation.
pub fn readCurrent(view: *const data.View) operations.Error!*const Result {
    const result = values.read(view, schema, Result) catch return error.OperationExecutionFailed;
    try requireCurrent(view, result);
    return result;
}

/// Also checks a result retained by a downstream owner after its source slot is removed.
pub fn requireCurrent(view: *const data.View, result: *const Result) operations.Error!void {
    const request = try requests.readCurrent(view, requests.prepared_schema);
    if (result.operationId().model_request_id != request.id()) return error.OperationExecutionFailed;
    switch (result.outcome()) {
        .validated => |evidence| if (evidence.request() != request.prepared() or !evidence.operationId().eql(result.operationId())) return error.OperationExecutionFailed,
        .rejected, .cancelled => {},
    }
}

pub fn status(result: *const Result) @import("../domain/workflow.zig").OutcomeTag {
    return switch (result.outcome()) {
        .validated => |evidence| switch (evidence.result()) {
            .complete => .ok,
            .stopped, .failed => .failed,
        },
        .rejected => .failed,
        .cancelled => .cancelled,
    };
}

const Owner = struct {
    allocator: std.mem.Allocator,
    request: *data.Value,
    response: *data.Value,
    operation_id: provider.ProviderOperationId,
    outcome: union(enum) { validated: validation.Owned, rejected: validation.ValidationError, cancelled },

    fn view(self: *const Owner) *const Result {
        return @ptrCast(self);
    }

    fn releaseEvidence(self: *Owner) void {
        switch (self.outcome) {
            .validated => |*owned| owned.deinit(),
            .rejected, .cancelled => {},
        }
    }

    fn destroy(self: *Owner) void {
        self.releaseEvidence();
        values.destroy(self.response);
        values.destroy(self.request);
        self.allocator.destroy(self);
    }
};

fn storage(result: *const Result) *const Owner {
    return @ptrCast(@alignCast(result));
}
