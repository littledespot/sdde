const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const pipeline = @import("../domain/pipeline.zig");
const execution = @import("../domain/workflow_execution.zig");
const envelope = @import("../domain/model_envelope.zig");
const observation = @import("provider_observation_workflow.zig");
const data = @import("../domain/pipeline_data.zig");
const values = @import("pipeline_values.zig");

pub const schema = values.schema(.model_envelope_result, Result, 1, null);
pub const Outcome = union(enum) {
    decoded: *const envelope.Candidate,
    protocol_rejected: envelope.Rejection,
    not_decoded: *const observation.Result,
};

/// Syntax only. The original observation remains the sole association authority.
pub const Result = opaque {
    pub fn source(self: *const Result) *const observation.Result {
        return storage(self).source;
    }

    pub fn outcome(self: *const Result) Outcome {
        const owner = storage(self);
        return switch (owner.outcome) {
            .decoded => |owned| .{ .decoded = owned.candidate },
            .protocol_rejected => |reason| .{ .protocol_rejected = reason },
            .not_decoded => .{ .not_decoded = owner.source },
        };
    }
};

pub const Decode = struct {
    pub const Action = @import("../actions/model/decode_model_envelope.zig").Action;
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
        const source = try observation.readCurrent(&input.step.data);
        const owner = self.allocator.create(Owner) catch return error.OperationExecutionFailed;
        errdefer self.allocator.destroy(owner);
        const retained = values.retain(input.step.data.slots[@intFromEnum(observation.schema.key)].?) catch return error.OperationExecutionFailed;
        errdefer values.destroy(retained);
        owner.* = .{
            .allocator = self.allocator,
            .retained = retained,
            .source = source,
            .outcome = switch (source.outcome()) {
                .validated => |evidence| switch (evidence.result()) {
                    .complete => |complete| decoded: {
                        const parsed = self.action.execute(self.allocator, complete) catch |err| break :decoded switch (err) {
                            error.OutOfMemory => return error.OperationExecutionFailed,
                            error.InvalidModelEnvelope => .{ .protocol_rejected = error.InvalidModelEnvelope },
                        };
                        break :decoded .{ .decoded = parsed };
                    },
                    .stopped, .failed => .not_decoded,
                },
                .rejected, .cancelled => .not_decoded,
            },
        };
        errdefer owner.releaseTree();
        const value = values.adopt(self.allocator, schema, Result, Owner, owner, Owner.view, Owner.destroy, null) catch return error.OperationExecutionFailed;
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(schema.key)] = value;
        return .{ .outcome = status(owner.view()), .delta = delta };
    }
};

/// The sealed source owns association; consumers do not revalidate provider data.
pub fn readCurrent(view: *const data.View) operations.Error!*const Result {
    const result = values.read(view, schema, Result) catch return error.OperationExecutionFailed;
    try observation.requireCurrent(view, result.source());
    return result;
}

pub fn status(result: *const Result) @import("../domain/workflow.zig").OutcomeTag {
    return switch (result.outcome()) {
        .decoded => .ok,
        .protocol_rejected => .invalid,
        .not_decoded => |source| observation.status(source),
    };
}

const Owner = struct {
    allocator: std.mem.Allocator,
    retained: *data.Value,
    source: *const observation.Result,
    outcome: union(enum) { decoded: envelope.Owned, protocol_rejected: envelope.Rejection, not_decoded },

    fn view(self: *const Owner) *const Result {
        return @ptrCast(self);
    }

    fn releaseTree(self: *Owner) void {
        switch (self.outcome) {
            .decoded => |*owned| owned.deinit(),
            .protocol_rejected, .not_decoded => {},
        }
    }

    fn destroy(self: *Owner) void {
        self.releaseTree();
        values.destroy(self.retained);
        self.allocator.destroy(self);
    }
};

fn storage(result: *const Result) *const Owner {
    return @ptrCast(@alignCast(result));
}
