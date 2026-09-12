const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const pipeline = @import("../domain/pipeline.zig");
const execution = @import("../domain/workflow_execution.zig");
const validation = @import("../domain/model_payload_schema.zig");
const envelope = @import("model_envelope_workflow.zig");
const data = @import("../domain/pipeline_data.zig");
const values = @import("pipeline_values.zig");

pub const schema = values.schema(.model_payload_schema_result, Result, 1, null).captured();
pub const Outcome = union(enum) {
    valid: *const validation.Evidence,
    schema_rejected: validation.Diagnostic,
    not_validated: *const envelope.Result,
};

/// Schema validity only; the retained candidate remains the sole evidence owner.
pub const Result = opaque {
    pub fn source(self: *const Result) *const envelope.Result {
        return storage(self).source;
    }

    pub fn outcome(self: *const Result) Outcome {
        return storage(self).outcome;
    }
};

pub const Validate = struct {
    pub const Action = @import("../actions/model/validate_model_payload_schema.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
        .id = Action.contract.id,
        .kind = .step,
        .requires = Action.contract.requires,
        .produces = Action.contract.produces,
        .outcomes = &.{ .ok, .invalid, .failed, .cancelled },
        .side_effect = Action.contract.side_effect,
    };
    allocator: std.mem.Allocator,
    action: Action = .{},

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = try envelope.readCurrent(&input.step.data);
        const owner = self.allocator.create(Owner) catch return error.OperationExecutionFailed;
        errdefer self.allocator.destroy(owner);
        const retained = values.retain(input.step.data.slots[@intFromEnum(envelope.schema.key)].?) catch return error.OperationExecutionFailed;
        errdefer values.destroy(retained);
        owner.* = .{
            .allocator = self.allocator,
            .retained = retained,
            .source = source,
            .outcome = switch (source.outcome()) {
                .decoded => |candidate| switch (self.action.execute(candidate)) {
                    .valid => |evidence| .{ .valid = evidence },
                    .invalid => |reason| .{ .schema_rejected = reason },
                },
                .protocol_rejected, .not_decoded => .{ .not_validated = source },
            },
        };
        const value = values.adopt(self.allocator, schema, Result, Owner, owner, Owner.view, Owner.destroy, null) catch return error.OperationExecutionFailed;
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(schema.key)] = value;
        return .{ .outcome = status(owner.view()), .delta = delta };
    }
};

pub fn readCurrent(view: *const data.View) operations.Error!*const Result {
    const result = values.read(view, schema, Result) catch return error.OperationExecutionFailed;
    try @import("provider_observation_workflow.zig").requireCurrent(view, result.source().source());
    return result;
}

pub fn status(result: *const Result) @import("../domain/workflow.zig").OutcomeTag {
    return switch (result.outcome()) {
        .valid => .ok,
        .schema_rejected => .invalid,
        .not_validated => |original| envelope.status(original),
    };
}

const Owner = struct {
    allocator: std.mem.Allocator,
    retained: *data.Value,
    source: *const envelope.Result,
    outcome: Outcome,

    fn view(self: *const Owner) *const Result {
        return @ptrCast(self);
    }

    fn destroy(self: *Owner) void {
        values.destroy(self.retained);
        self.allocator.destroy(self);
    }
};

fn storage(result: *const Result) *const Owner {
    return @ptrCast(@alignCast(result));
}
