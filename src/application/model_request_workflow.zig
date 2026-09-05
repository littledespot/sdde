const std = @import("std");
const identity = @import("../domain/model_request_identity.zig");
const handoff = @import("../domain/model_request_handoff.zig");
const provider = @import("../domain/llm_provider_operation.zig");
const compilation = @import("../domain/workflow_compilation.zig");
const operation = @import("../domain/workflow_operation.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const pipeline = @import("../domain/pipeline.zig");
const data = @import("../domain/pipeline_data.zig");
const execution = @import("../domain/workflow_execution.zig");
const values = @import("pipeline_values.zig");

// Native sealed owners retain canonical identity and graph references. Their
// payloads have no model-call byte ceiling and are never copied by the envelope.
pub const ledger_schema = values.schema(.model_request_identity_ledger, identity.ModelRequestIdentityLedger, 1, null);
pub const assigned_schema = values.schema(.assigned_model_request, handoff.Request, 1, null);
pub const validated_schema = values.schema(.validated_model_request, handoff.Request, 1, null);
pub const prepared_schema = values.schema(.prepared_model_request, handoff.Request, 1, null);
pub const schemas = [_]data.Schema{ ledger_schema, assigned_schema, validated_schema, prepared_schema };

pub const Initialize = struct {
    pub const Action = @import("../actions/model/build_initial_model_request_identity_ledger.zig").Action;
    pub const contract = descriptor(Action.contract, &.{}, &.{.model_request_identity_ledger}, &.{});
    allocator: std.mem.Allocator,
    action: Action = .{},

    pub fn invoke(context: ?*@This(), _: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const owner = self.action.execute(self.allocator, .{ .initial_generation = true }) catch return error.OperationExecutionFailed;
        errdefer identity.deinitOwner(owner);
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(ledger_schema.key)] = adoptLedger(self.allocator, owner) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }
};

pub const Assign = struct {
    pub const Action = @import("../actions/model/assign_model_request_id.zig").Action;
    pub const contract: operation.Contract = contract: {
        var result = descriptor(Action.contract, &.{.model_request_identity_ledger}, &.{.assigned_model_request}, &.{.model_request_identity_ledger});
        result.parameters = &([_]operation.ParameterDescriptor{
            .{ .id = "slot", .kind = .model_slot, .required = true, .workflow_definition_safe = true },
            .{ .id = "prompt", .kind = .resource, .resource_kind = .prompt, .required = true, .workflow_definition_safe = true },
            .{ .id = "result-schema", .kind = .resource, .resource_kind = .result_schema, .required = true, .workflow_definition_safe = true },
            .{ .id = "input", .kind = .resource, .resource_kind = .data, .required = false, .workflow_definition_safe = true },
        } ++ @import("../domain/workflow_model.zig").parameters);
        break :contract result;
    };
    allocator: std.mem.Allocator,
    action: Action = .{},

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const step = input.step;
        const selected = step.model_binding orelse return error.OperationExecutionFailed;
        const current = values.read(&step.data, ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
        const prompt = resource(step, "prompt") orelse return error.OperationExecutionFailed;
        const result = resource(step, "result-schema") orelse return error.OperationExecutionFailed;
        const assignment = self.action.execute(current, current.revision(), .workflow_step, selected.operation_id, .initial_generation) catch return error.OperationExecutionFailed;
        defer identity.deinitOwner(assignment.owner);
        const request = handoff.assign(self.allocator, assignment.owner, assignment.model_request_id, selected.*, prompt, result, resource(step, "input")) catch return error.OperationExecutionFailed;
        errdefer handoff.destroy(request);
        identity.retainOwner(assignment.owner) catch return error.OperationExecutionFailed;
        const ledger_value = adoptLedger(self.allocator, assignment.owner) catch {
            identity.deinitOwner(assignment.owner);
            return error.OperationExecutionFailed;
        };
        errdefer values.destroy(ledger_value);
        const request_value = adoptRequest(self.allocator, assigned_schema, request) catch return error.OperationExecutionFailed;
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(ledger_schema.key)] = ledger_value;
        delta.data_writes[@intFromEnum(assigned_schema.key)] = request_value;
        return .{ .outcome = .ok, .delta = delta };
    }
};

pub const Validate = struct {
    pub const Action = @import("../actions/model/validate_model_request_binding.zig").Action;
    pub const contract = descriptor(Action.contract, &.{ .model_request_identity_ledger, .assigned_model_request }, &.{.validated_model_request}, &.{});
    allocator: std.mem.Allocator,
    action: Action = .{},

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const request = try readCurrent(&input.step.data, assigned_schema);
        const current = values.read(&input.step.data, ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
        const id = request.id();
        const evidence = self.action.execute(current, current.revision(), id, id.immutable_unit_owner_id, request.binding().operation_id, id.purpose) catch return error.OperationExecutionFailed;
        const next = handoff.validated(request, evidence) catch return error.OperationExecutionFailed;
        return publish(self.allocator, validated_schema, next);
    }
};

pub const Build = struct {
    pub const Action = @import("../actions/model/build_model_request.zig").Action;
    pub const contract = descriptor(Action.contract, &.{ .model_request_identity_ledger, .validated_model_request }, &.{.prepared_model_request}, &.{});
    allocator: std.mem.Allocator,
    action: Action = .{},

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const request = try readCurrent(&input.step.data, validated_schema);
        // These resources were selected once by the originating compiled step.
        var parts: [2]provider.ModelVisibleContent = undefined;
        parts[0] = .{ .guidance = request.prompt() };
        const count: usize = if (request.input()) |bytes| count: {
            parts[1] = .{ .user = bytes };
            break :count 2;
        } else 1;
        var input_id: [32]u8 = undefined;
        const id_bytes = std.fmt.bufPrint(&input_id, "input-{d}", .{request.ledger().revision().value}) catch return error.OperationExecutionFailed;
        const source = request.source(.{ .bytes = id_bytes }) catch return error.OperationExecutionFailed;
        var owned = self.action.execute(self.allocator, source, parts[0..count]) catch return error.OperationExecutionFailed;
        const next = handoff.prepared(request, owned) catch {
            owned.deinit();
            return error.OperationExecutionFailed;
        };
        return publish(self.allocator, prepared_schema, next);
    }
};

pub fn readCurrent(view: *const data.View, schema: data.Schema) operations.Error!*const handoff.Request {
    const current = values.read(view, ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
    const request = values.read(view, schema, handoff.Request) catch return error.OperationExecutionFailed;
    if (!current.containsRequest(request.id()) or !current.stageRunEpochId().eql(request.ledger().stageRunEpochId())) return error.OperationExecutionFailed;
    return request;
}

fn descriptor(action: pipeline.NodeContract, requires: []const pipeline.DataKey, produces: []const pipeline.DataKey, replaces: []const pipeline.DataKey) operation.Contract {
    return .{ .id = action.id, .kind = .step, .requires = requires, .produces = produces, .replaces = replaces, .outcomes = &.{ .ok, .failed }, .side_effect = action.side_effect };
}

fn resource(input: operations.StepInput, parameter_id: []const u8) ?compilation.CompiledResource {
    for (input.step.parameters) |parameter| {
        if (!std.mem.eql(u8, parameter.id.bytes, parameter_id) or parameter.value != .resource) continue;
        for (input.resources) |value| if (std.mem.eql(u8, value.id.bytes, parameter.value.resource.bytes)) return value;
    }
    return null;
}

fn adoptLedger(allocator: std.mem.Allocator, owner: *identity.Owner) values.Error!*data.Value {
    return values.adopt(allocator, ledger_schema, identity.ModelRequestIdentityLedger, identity.Owner, owner, identity.ledger, identity.deinitOwner, null);
}

fn adoptRequest(allocator: std.mem.Allocator, schema: data.Schema, request: *handoff.Request) values.Error!*data.Value {
    return values.adopt(allocator, schema, handoff.Request, handoff.Request, request, handoff.view, handoff.destroy, null);
}

fn publish(allocator: std.mem.Allocator, schema: data.Schema, request: *handoff.Request) operations.Error!execution.Candidate {
    errdefer handoff.destroy(request);
    var delta: pipeline.NodeDelta = .{};
    delta.data_writes[@intFromEnum(schema.key)] = adoptRequest(allocator, schema, request) catch return error.OperationExecutionFailed;
    return .{ .outcome = .ok, .delta = delta };
}
