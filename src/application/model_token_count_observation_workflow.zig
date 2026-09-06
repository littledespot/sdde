const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const pipeline = @import("../domain/pipeline.zig");
const execution = @import("../domain/workflow_execution.zig");
const provider = @import("../domain/llm_provider_operation.zig");
const validation = @import("../domain/model_token_count_validation.zig");
const raw_result = @import("../domain/model_invocation_result.zig").For(.input_token_count);
const requests = @import("model_request_workflow.zig");
const invocation = @import("model_invocation_workflow.zig");
const data = @import("../domain/pipeline_data.zig");
const values = @import("pipeline_values.zig");

pub const schema = values.schema(.provider_token_count_validation_result, Result, 1, null).captured();
pub const Outcome = union(enum) { validated: validation.Result, rejected: validation.Error, cancelled };

pub const Result = opaque {
    pub fn operationId(self: *const Result) provider.ProviderOperationId {
        return storage(self).operation_id;
    }
    pub fn outcome(self: *const Result) Outcome {
        return storage(self).outcome;
    }
};

pub const Validate = struct {
    pub const Action = @import("../actions/model/validate_model_token_count_observation.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
        .id = Action.contract.id,
        .kind = .step,
        .requires = Action.contract.requires,
        .produces = Action.contract.produces,
        .outcomes = &.{ .ok, .failed, .cancelled },
        .side_effect = .none,
    };
    allocator: std.mem.Allocator,
    action: Action = .{},

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const call = input.step.provider_token_count orelse return error.OperationExecutionFailed;
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        if (request.prepared() != call.request or request.binding() != call.provider_binding) return error.OperationExecutionFailed;
        const response = values.read(&input.step.data, invocation.count_schema, raw_result.Result) catch return error.OperationExecutionFailed;
        const raw = response.outcome() orelse return error.OperationExecutionFailed;
        const outcome: Outcome = if (!response.operationId().eql(call.operation_id))
            .{ .rejected = error.ModelTokenCountAssociationInvalid }
        else switch (raw.*) {
            .observation => |*observed| observed: {
                const evidence = self.action.execute(call, observed) catch |err| break :observed .{ .rejected = err };
                break :observed .{ .validated = evidence };
            },
            .cancelled => .cancelled,
            .allocation_failed => return error.OperationExecutionFailed,
        };
        const owner = self.allocator.create(Owner) catch return error.OperationExecutionFailed;
        errdefer self.allocator.destroy(owner);
        const retained = values.retain(input.step.data.slots[@intFromEnum(requests.prepared_schema.key)].?) catch return error.OperationExecutionFailed;
        errdefer values.destroy(retained);
        owner.* = .{ .allocator = self.allocator, .request = retained, .operation_id = call.operation_id, .outcome = outcome };
        const value = values.adopt(self.allocator, schema, Result, Owner, owner, Owner.view, Owner.destroy, null) catch return error.OperationExecutionFailed;
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(schema.key)] = value;
        return .{ .outcome = status(owner.view()), .delta = delta };
    }
};

pub fn readCurrent(view: *const data.View) operations.Error!*const Result {
    const result = values.read(view, schema, Result) catch return error.OperationExecutionFailed;
    const request = try requests.readCurrent(view, requests.prepared_schema);
    const retained = values.read(&singleRequest(storage(result).request), requests.prepared_schema, @import("../domain/model_request_handoff.zig").Request) catch return error.OperationExecutionFailed;
    if (request != retained or result.operationId().model_request_id != request.id() or result.operationId().kind != .input_token_count) return error.OperationExecutionFailed;
    return result;
}

fn singleRequest(request: *data.Value) data.View {
    var view: data.View = .{ .slots = .{null} ** data.key_count };
    view.slots[@intFromEnum(requests.prepared_schema.key)] = request;
    return view;
}

pub fn status(result: *const Result) @import("../domain/workflow.zig").OutcomeTag {
    return switch (result.outcome()) {
        .validated => |evidence| switch (evidence) {
            .counted => .ok,
            .failed => .failed,
        },
        .rejected => .failed,
        .cancelled => .cancelled,
    };
}

const Owner = struct {
    allocator: std.mem.Allocator,
    request: *data.Value,
    operation_id: provider.ProviderOperationId,
    outcome: Outcome,
    fn view(self: *const Owner) *const Result {
        return @ptrCast(self);
    }
    fn destroy(self: *Owner) void {
        values.destroy(self.request);
        self.allocator.destroy(self);
    }
};
fn storage(result: *const Result) *const Owner {
    return @ptrCast(@alignCast(result));
}
