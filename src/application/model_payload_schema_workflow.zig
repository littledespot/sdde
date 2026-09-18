const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const pipeline = @import("../domain/pipeline.zig");
const execution = @import("../domain/workflow_execution.zig");
const validation = @import("../domain/model_payload_schema.zig");
const envelope = @import("model_envelope_workflow.zig");
const decoding = @import("../domain/model_envelope.zig");
const observation = @import("provider_observation_workflow.zig");
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
        const checked: ?validation.Result = switch (source.outcome()) {
            .decoded => |candidate| self.action.execute(candidate),
            .protocol_rejected, .not_decoded => null,
        };
        const value = try capture(self.allocator, &input.step.data, checked);
        errdefer values.destroy(value);
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(schema.key)] = value;
        const result = values.read(&.{ .slots = delta.data_writes }, schema, Result) catch return error.OperationExecutionFailed;
        return .{ .outcome = status(result), .delta = delta };
    }
};

pub const Admit = struct {
    pub const Action = @import("../actions/model/admit_model_response.zig").Action;
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
        var diagnostic: ?decoding.Diagnostic = null;
        var checked: ?validation.Result = null;
        const decoded: ?decoding.Error!decoding.Owned = if (envelope.complete(source)) |candidate| result: {
            const admitted = self.action.execute(self.allocator, candidate, &diagnostic) catch |err| break :result err;
            checked = admitted.validated;
            break :result admitted.decoded;
        } else null;
        const envelope_value = try envelope.capture(self.allocator, &input.step.data, decoded, diagnostic);
        errdefer values.destroy(envelope_value);
        var view = input.step.data;
        view.slots[@intFromEnum(envelope.schema.key)] = envelope_value;
        const payload_value = try capture(self.allocator, &view, checked);
        errdefer values.destroy(payload_value);
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(envelope.schema.key)] = envelope_value;
        delta.data_writes[@intFromEnum(schema.key)] = payload_value;
        const result = values.read(&.{ .slots = delta.data_writes }, schema, Result) catch return error.OperationExecutionFailed;
        return .{ .outcome = status(result), .delta = delta };
    }
};

/// Retains the exact envelope; schema evidence borrows its parsed candidate.
fn capture(allocator: std.mem.Allocator, view: *const data.View, checked: ?validation.Result) operations.Error!*data.Value {
    const source = try envelope.readCurrent(view);
    if ((source.outcome() == .decoded) != (checked != null)) return error.OperationExecutionFailed;
    if (checked) |result| if (result == .valid and result.valid.candidate() != source.outcome().decoded) return error.OperationExecutionFailed;
    const owner = allocator.create(Owner) catch return error.OperationExecutionFailed;
    errdefer allocator.destroy(owner);
    const retained = values.retain(view.slots[@intFromEnum(envelope.schema.key)].?) catch return error.OperationExecutionFailed;
    errdefer values.destroy(retained);
    owner.* = .{
        .allocator = allocator,
        .retained = retained,
        .source = source,
        .outcome = if (checked) |result| switch (result) {
            .valid => |evidence| .{ .valid = evidence },
            .invalid => |reason| .{ .schema_rejected = reason },
        } else .{ .not_validated = source },
    };
    return values.adopt(allocator, schema, Result, Owner, owner, Owner.view, Owner.destroy, null) catch error.OperationExecutionFailed;
}

pub fn readCurrent(view: *const data.View) operations.Error!*const Result {
    const result = values.read(view, schema, Result) catch return error.OperationExecutionFailed;
    try observation.requireCurrent(view, result.source().source());
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
