const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const pipeline = @import("../domain/pipeline.zig");
const execution = @import("../domain/workflow_execution.zig");
const envelope = @import("../domain/model_envelope.zig");
const observation = @import("provider_observation_workflow.zig");
const data = @import("../domain/pipeline_data.zig");
const values = @import("pipeline_values.zig");

pub const schema = values.schema(.model_envelope_result, Result, 1, null).captured();
pub const Rejection = struct {
    reason: envelope.Rejection,
    diagnostic: envelope.Diagnostic,
};
pub const Outcome = union(enum) {
    decoded: *const envelope.Candidate,
    protocol_rejected: Rejection,
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
        var diagnostic: ?envelope.Diagnostic = null;
        const decoded: ?envelope.Error!envelope.Owned = if (complete(source)) |candidate| self.action.execute(self.allocator, candidate, &diagnostic) else null;
        const value = try capture(self.allocator, &input.step.data, decoded, diagnostic);
        errdefer values.destroy(value);
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(schema.key)] = value;
        const result = values.read(&.{ .slots = delta.data_writes }, schema, Result) catch return error.OperationExecutionFailed;
        return .{ .outcome = status(result), .delta = delta };
    }
};

pub fn complete(source: *const observation.Result) ?*const @import("../domain/provider_invocation_validation.zig").CompleteCandidate {
    return switch (source.outcome()) {
        .validated => |evidence| switch (evidence.result()) {
            .complete => |candidate| candidate,
            .stopped, .failed => null,
        },
        .rejected, .cancelled => null,
    };
}

/// Consumes the decoder tree/diagnostic on every path and retains its observation.
/// Detailed and consolidated admission publish the same sealed result type.
pub fn capture(allocator: std.mem.Allocator, view: *const data.View, decoded: ?envelope.Error!envelope.Owned, diagnostic: ?envelope.Diagnostic) operations.Error!*data.Value {
    var outcome: Decoded = if (decoded) |result| decoded_result: {
        const owned = result catch |err| break :decoded_result switch (err) {
            error.OutOfMemory => return error.OperationExecutionFailed,
            error.InvalidModelEnvelope => .{ .protocol_rejected = .{ .reason = error.InvalidModelEnvelope, .diagnostic = diagnostic orelse return error.OperationExecutionFailed } },
        };
        break :decoded_result .{ .decoded = owned };
    } else .not_decoded;
    errdefer release(allocator, &outcome);
    const source = try observation.readCurrent(view);
    if ((complete(source) != null) != (decoded != null)) return error.OperationExecutionFailed;
    if (outcome == .decoded and outcome.decoded.candidate.association() != complete(source).?.association()) return error.OperationExecutionFailed;
    const owner = allocator.create(Owner) catch return error.OperationExecutionFailed;
    errdefer allocator.destroy(owner);
    const retained = values.retain(view.slots[@intFromEnum(observation.schema.key)].?) catch return error.OperationExecutionFailed;
    errdefer values.destroy(retained);
    owner.* = .{ .allocator = allocator, .retained = retained, .source = source, .outcome = outcome };
    return values.adopt(allocator, schema, Result, Owner, owner, Owner.view, Owner.destroy, null) catch error.OperationExecutionFailed;
}

const Decoded = union(enum) { decoded: envelope.Owned, protocol_rejected: Rejection, not_decoded };

fn release(allocator: std.mem.Allocator, outcome: *Decoded) void {
    switch (outcome.*) {
        .decoded => |*owned| owned.deinit(),
        .protocol_rejected => |rejected| rejected.diagnostic.deinit(allocator),
        .not_decoded => {},
    }
}

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
    outcome: Decoded,

    fn view(self: *const Owner) *const Result {
        return @ptrCast(self);
    }

    fn destroy(self: *Owner) void {
        release(self.allocator, &self.outcome);
        values.destroy(self.retained);
        self.allocator.destroy(self);
    }
};

fn storage(result: *const Result) *const Owner {
    return @ptrCast(@alignCast(result));
}
