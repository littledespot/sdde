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
const packets = @import("../domain/model_input_packet.zig");
const compositions = @import("json_composition_workflow.zig");
pub const packet_schema = values.schema(.model_input_packet, packets.Packet, 1, null).captured();

// Native sealed owners retain canonical identity and graph references. Their
// payloads have no model-call byte ceiling and are never copied by the envelope.
pub const ledger_schema = values.schema(.model_request_identity_ledger, identity.ModelRequestIdentityLedger, 1, null).executionControl();
pub const assigned_schema = values.schema(.assigned_model_request, handoff.Request, 1, null).captured();
pub const validated_schema = values.schema(.validated_model_request, handoff.Request, 1, null).captured();
pub const prepared_schema = values.schema(.prepared_model_request, handoff.Request, 1, null).captured();
pub const schemas = [_]data.Schema{ ledger_schema, assigned_schema, validated_schema, prepared_schema, packet_schema };

const preparation_parameters = [_]operation.ParameterDescriptor{
    .{ .id = "slot", .kind = .model_slot, .required = true, .workflow_definition_safe = true },
    .{ .id = "prompt", .kind = .resource, .resource_kind = .prompt, .required = true, .workflow_definition_safe = true },
    .{ .id = "protocol-prompt", .kind = .resource, .resource_kind = .prompt, .required = false, .workflow_definition_safe = true },
    .{ .id = "result-schema", .kind = .resource, .resource_kind = .result_schema, .required = false, .workflow_definition_safe = true },
    .{ .id = "composition-part", .kind = .string, .required = false, .workflow_definition_safe = true },
    .{ .id = "result-selection", .kind = .enumeration, .required = false, .allowed_values = &.{ "resource", "input" }, .workflow_definition_safe = true },
    .{ .id = "input", .kind = .resource, .resource_kind = .data, .required = false, .workflow_definition_safe = true },
};

pub const Initialize = struct {
    pub const Action = @import("../actions/model/build_initial_model_request_identity_ledger.zig").Action;
    pub const contract = descriptor(Action.contract, &.{}, &.{.model_request_identity_ledger}, &.{});
    allocator: std.mem.Allocator,
    action: Action = .{},

    pub fn invoke(context: ?*@This(), _: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const owner = self.action.execute(self.allocator, .{ .initial_generation = true, .semantic_review = true, .atomic_repair = true }) catch return error.OperationExecutionFailed;
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
        result.optional = &.{ .model_input_packet, .json_composition };
        result.parameters = &preparation_parameters;
        break :contract result;
    };
    allocator: std.mem.Allocator,
    action: Action = .{},

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const step = input.step;
        const current = values.read(&step.data, ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const selection = try selections(self.allocator, arena.allocator(), step);
        defer selection.deinit();
        const selected = selection.value;
        const assignment = self.action.execute(current, current.revision(), selected.unit(), selected.binding.operation_id, selected.purpose()) catch return error.OperationExecutionFailed;
        defer identity.deinitOwner(assignment.owner);
        const request = selected.bind(self.allocator, assignment) catch return error.OperationExecutionFailed;
        return publishAssignment(self.allocator, assignment.owner, &.{request});
    }
};

pub const Prepare = struct {
    pub const Action = @import("../actions/model/prepare_model_request.zig").Action;
    pub const contract: operation.Contract = contract: {
        var result = descriptor(Action.contract, Action.contract.requires, Action.contract.produces, Action.contract.replaces);
        result.optional = Action.contract.optional;
        result.parameters = &preparation_parameters;
        break :contract result;
    };
    allocator: std.mem.Allocator,
    action: Action = .{},

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = values.read(&input.step.data, ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const selection = try selections(self.allocator, arena.allocator(), input.step);
        defer selection.deinit();
        const prepared = self.action.execute(self.allocator, current, current.revision(), selection.value) catch return error.OperationExecutionFailed;
        defer identity.deinitOwner(prepared.owner);
        return publishAssignment(self.allocator, prepared.owner, &.{ prepared.assigned, prepared.validated, prepared.request });
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
        var input_id: [32]u8 = undefined;
        const source = request.buildSource(&input_id) catch return error.OperationExecutionFailed;
        var owned = self.action.execute(self.allocator, source, request.content(&parts)) catch return error.OperationExecutionFailed;
        const next = handoff.prepared(request, owned, null) catch {
            owned.deinit();
            return error.OperationExecutionFailed;
        };
        return publish(self.allocator, prepared_schema, next);
    }
};

const Selection = struct {
    value: handoff.Selection,
    owned_packet: ?*packets.Packet = null,
    fn deinit(self: Selection) void {
        if (self.owned_packet) |packet| packets.release(packet);
    }
};

fn selections(allocator: std.mem.Allocator, scratch: std.mem.Allocator, step: operations.StepInput) operations.Error!Selection {
    if (!@import("../domain/workflow_model.zig").validResultSelection(step.step.parameters)) return error.OperationExecutionFailed;
    const selected = step.model_binding orelse return error.OperationExecutionFailed;
    const packet = if (step.data.contains(.model_input_packet)) values.read(&step.data, packet_schema, packets.Packet) catch return error.OperationExecutionFailed else null;
    const static_input = resource(step, "input");
    if (packet != null and static_input != null) return error.OperationExecutionFailed;
    var selection: handoff.ResultSelection = .resource;
    for (step.step.parameters) |parameter| if (std.mem.eql(u8, parameter.id.bytes, "result-selection")) {
        if (parameter.value != .enumeration) return error.OperationExecutionFailed;
        selection = std.meta.stringToEnum(handoff.ResultSelection, parameter.value.enumeration) orelse return error.OperationExecutionFailed;
    };
    var result: handoff.Selection = .{
        .binding = selected.*,
        .prompt = resource(step, "prompt") orelse return error.OperationExecutionFailed,
        .result = undefined,
        .input = if (packet) |value| .{ .packet = value } else if (static_input) |value| .{ .resource = value } else null,
        .protocol_prompt = resource(step, "protocol-prompt"),
        .result_selection = selection,
    };
    const part_id = parameterString(step, "composition-part");
    if (part_id) |id| {
        const state = try compositions.readState(&step.data);
        if (state.base != packet) return error.OperationExecutionFailed;
        const part = state.plan.part(@import("../domain/workflow.zig").WorkflowResourceId.parse(id) orelse return error.OperationExecutionFailed) orelse return error.OperationExecutionFailed;
        const binding = state.select(scratch, part) catch return error.OperationExecutionFailed;
        result.composition = binding;
        result.result = .{ .id = state.plan.resultAlias(), .content = .{ .result_schema = state.plan.resultSchema() } };
        if (binding.prerequisites.len != 0) {
            const context = state.inputs(scratch, binding) catch return error.OperationExecutionFailed;
            const derived = packets.withJsonContext(allocator, state.base, "prerequisites", context) catch return error.OperationExecutionFailed;
            result.input = .{ .packet = derived };
            return .{ .value = result, .owned_packet = derived };
        }
    } else {
        if (step.data.contains(.json_composition)) return error.OperationExecutionFailed;
        result.result = resource(step, "result-schema") orelse return error.OperationExecutionFailed;
    }
    return .{ .value = result };
}

fn parameterString(step: operations.StepInput, id: []const u8) ?[]const u8 {
    for (step.step.parameters) |parameter| if (std.mem.eql(u8, parameter.id.bytes, id) and parameter.value == .string) return parameter.value.string;
    return null;
}

/// Consumes each request; the ledger owner is borrowed. Partial allocation never
/// publishes a delta, and detailed/consolidated preparation share this transfer.
fn publishAssignment(allocator: std.mem.Allocator, owner: *identity.Owner, requests: []const *handoff.Request) operations.Error!execution.Candidate {
    const request_schemas = [_]data.Schema{ assigned_schema, validated_schema, prepared_schema };
    var transferred: usize = 0;
    defer for (requests[transferred..]) |request| handoff.destroy(request);
    var delta: pipeline.NodeDelta = .{};
    errdefer {
        for (delta.data_writes) |value| if (value) |owned| values.destroy(owned);
        if (delta.data_replacements[@intFromEnum(ledger_schema.key)]) |owned| values.destroy(owned);
    }
    identity.retainOwner(owner) catch return error.OperationExecutionFailed;
    delta.data_replacements[@intFromEnum(ledger_schema.key)] = adoptLedger(allocator, owner) catch {
        identity.deinitOwner(owner);
        return error.OperationExecutionFailed;
    };
    for (requests, request_schemas[0..requests.len]) |request, schema| {
        delta.data_writes[@intFromEnum(schema.key)] = adoptRequest(allocator, schema, request) catch return error.OperationExecutionFailed;
        transferred += 1;
    }
    return .{ .outcome = .ok, .delta = delta };
}

pub fn readCurrent(view: *const data.View, schema: data.Schema) operations.Error!*const handoff.Request {
    const current = values.read(view, ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
    const request = values.read(view, schema, handoff.Request) catch return error.OperationExecutionFailed;
    if (!current.containsRequest(request.id()) or !current.stageRunEpochId().eql(request.ledger().stageRunEpochId())) return error.OperationExecutionFailed;
    return request;
}

fn descriptor(action: pipeline.NodeContract, requires: []const pipeline.DataKey, produces: []const pipeline.DataKey, replaces: []const pipeline.DataKey) operation.Contract {
    return .{ .id = action.id, .kind = .step, .requires = requires, .produces = produces, .replaces = replaces, .outcomes = &.{ .ok, .failed }, .side_effect = action.side_effect };
}

pub fn resource(input: operations.StepInput, parameter_id: []const u8) ?compilation.CompiledResource {
    for (input.step.parameters) |parameter| {
        if (!std.mem.eql(u8, parameter.id.bytes, parameter_id) or parameter.value != .resource) continue;
        for (input.resources) |value| if (std.mem.eql(u8, value.id.bytes, parameter.value.resource.bytes)) return value;
    }
    return null;
}

pub fn adoptLedger(allocator: std.mem.Allocator, owner: *identity.Owner) values.Error!*data.Value {
    return values.adopt(allocator, ledger_schema, identity.ModelRequestIdentityLedger, identity.Owner, owner, identity.ledger, identity.deinitOwner, null);
}

pub fn adoptPacket(allocator: std.mem.Allocator, packet: *packets.Packet) values.Error!*data.Value {
    return values.adopt(allocator, packet_schema, packets.Packet, packets.Packet, packet, packets.view, packets.release, null);
}

pub fn publishPacket(allocator: std.mem.Allocator, packet: *packets.Packet) operations.Error!execution.Candidate {
    errdefer packets.release(packet);
    var delta: pipeline.NodeDelta = .{};
    delta.data_writes[@intFromEnum(packet_schema.key)] = adoptPacket(allocator, packet) catch return error.OperationExecutionFailed;
    return .{ .outcome = .ok, .delta = delta };
}

pub fn adoptRequest(allocator: std.mem.Allocator, schema: data.Schema, request: *handoff.Request) values.Error!*data.Value {
    return values.adopt(allocator, schema, handoff.Request, handoff.Request, request, handoff.view, handoff.destroy, null);
}

fn publish(allocator: std.mem.Allocator, schema: data.Schema, request: *handoff.Request) operations.Error!execution.Candidate {
    errdefer handoff.destroy(request);
    var delta: pipeline.NodeDelta = .{};
    delta.data_writes[@intFromEnum(schema.key)] = adoptRequest(allocator, schema, request) catch return error.OperationExecutionFailed;
    return .{ .outcome = .ok, .delta = delta };
}
