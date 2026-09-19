//! Pipeline ownership for pure configured composition. Provider lifecycle and
//! admission remain with the existing request owners.
const std = @import("std");
const runtime = @import("../domain/json_composition_runtime.zig");
const pipeline = @import("../domain/pipeline.zig");
const data = @import("../domain/pipeline_data.zig");
const values = @import("pipeline_values.zig");
const requests = @import("model_request_workflow.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const identity = @import("../domain/model_request_identity.zig");
const Payload = union(enum) { state: runtime.State, candidate: runtime.Candidate, validated: *const runtime.Candidate };
pub const Value = opaque {};
pub const state_schema = values.schema(.json_composition, Value, 1, null).captured();
pub const assembled_schema = values.schema(.assembled_json, Value, 1, null).captured();
pub const validated_schema = values.schema(.validated_assembled_json, Value, 1, null).captured();
pub const schemas = [_]data.Schema{ state_schema, assembled_schema, validated_schema };

pub const Initialize = struct {
    pub const Action = @import("../actions/model/initialize_json_composition.zig").Action;
    pub const contract = descriptor(Action.contract, &.{.{ .id = "composition", .kind = .resource, .resource_kind = .json_composition, .required = true, .workflow_definition_safe = true }});
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const selected = requests.resource(input.step, "composition") orelse return error.OperationExecutionFailed;
        if (selected.content != .json_composition) return error.OperationExecutionFailed;
        const packet = values.read(&input.step.data, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet) catch return error.OperationExecutionFailed;
        const ledger = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
        const owner = try Owner.create(self.allocator, &input.step.data, &.{ .model_input_packet, .model_request_identity_ledger });
        errdefer owner.destroy();
        owner.payload = .{ .state = self.action.execute(owner.arena.allocator(), selected.content.json_composition, packet, ledger.stageRunEpochId()) catch return error.OperationExecutionFailed };
        return publish(owner, state_schema, false, &.{});
    }
};

pub const Retain = struct {
    pub const Action = @import("../actions/model/retain_json_part.zig").Action;
    pub const contract = descriptor(Action.contract, &.{});
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = try readState(&input.step.data);
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const part = request.part() orelse return error.OperationExecutionFailed;
        const accepted = try @import("model_candidate_handoff.zig").readAccepted(&input.step.data);
        const ledger = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
        const owner = try Owner.create(self.allocator, &input.step.data, &.{ .json_composition, .model_payload_schema_result });
        errdefer owner.destroy();
        owner.payload = .{ .state = self.action.execute(owner.arena.allocator(), state.*, part, accepted.evidence, accepted.candidate.origin, ledger) catch return error.OperationExecutionFailed };
        return publish(owner, state_schema, true, &.{});
    }
};

pub const Assemble = struct {
    pub const Action = @import("../actions/model/assemble_json.zig").Action;
    pub const contract = descriptor(Action.contract, &.{});
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = try readState(&input.step.data);
        const owner = try Owner.create(self.allocator, &input.step.data, &.{.json_composition});
        errdefer owner.destroy();
        owner.payload = .{ .candidate = self.action.execute(owner.arena.allocator(), state.*) catch return error.OperationExecutionFailed };
        return publish(owner, assembled_schema, false, Action.contract.invalidates);
    }
};

pub const Validate = struct {
    pub const Action = @import("../actions/model/validate_assembled_json.zig").Action;
    pub const contract = descriptor(Action.contract, &.{});
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = try read(&input.step.data, assembled_schema);
        if (source.payload != .candidate) return error.OperationExecutionFailed;
        const candidate = &source.payload.candidate;
        if (self.action.execute(candidate) != null) return error.OperationExecutionFailed;
        const owner = try Owner.create(self.allocator, &input.step.data, &.{.assembled_json});
        errdefer owner.destroy();
        owner.payload = .{ .validated = candidate };
        return publish(owner, validated_schema, false, &.{});
    }
};

pub fn readState(view: *const data.View) operations.Error!*const runtime.State {
    const owner = try read(view, state_schema);
    return if (owner.payload == .state) &owner.payload.state else error.OperationExecutionFailed;
}
pub fn readValidated(view: *const data.View) operations.Error!*const runtime.Candidate {
    const source = try read(view, assembled_schema);
    const checked = try read(view, validated_schema);
    if (source.payload != .candidate or checked.payload != .validated or checked.payload.validated != &source.payload.candidate) return error.OperationExecutionFailed;
    return checked.payload.validated;
}
fn read(view: *const data.View, schema: data.Schema) operations.Error!*const Owner {
    const value = values.read(view, schema, Value) catch return error.OperationExecutionFailed;
    return @ptrCast(@alignCast(value));
}
fn descriptor(action: pipeline.NodeContract, parameters: []const @import("../domain/workflow_operation.zig").ParameterDescriptor) @import("../domain/workflow_operation.zig").Contract {
    return .{ .id = action.id, .kind = .step, .parameters = parameters, .requires = action.requires, .produces = action.produces, .replaces = action.replaces, .invalidates = action.invalidates, .outcomes = &.{ .ok, .failed }, .side_effect = .none };
}
fn publish(owner: *Owner, schema: data.Schema, replacement: bool, invalidates: []const pipeline.DataKey) operations.Error!execution.Candidate {
    const value = values.adopt(owner.allocator, schema, Value, Owner, owner, Owner.view, Owner.destroy, null) catch return error.OperationExecutionFailed;
    var delta: pipeline.NodeDelta = .{};
    if (replacement) delta.data_replacements[@intFromEnum(schema.key)] = value else delta.data_writes[@intFromEnum(schema.key)] = value;
    for (invalidates) |key| delta.data_invalidations.insert(key);
    return .{ .outcome = .ok, .delta = delta };
}
const Owner = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    retained: [2]?*data.Value = @splat(null),
    payload: Payload,
    fn create(allocator: std.mem.Allocator, source: *const data.View, keys: []const pipeline.DataKey) operations.Error!*Owner {
        const owner = allocator.create(Owner) catch return error.OperationExecutionFailed;
        owner.* = .{ .allocator = allocator, .arena = .init(allocator), .payload = undefined };
        errdefer owner.destroy();
        for (keys, 0..) |key, index| owner.retained[index] = values.retain(source.slots[@intFromEnum(key)] orelse return error.OperationExecutionFailed) catch return error.OperationExecutionFailed;
        return owner;
    }
    fn view(self: *const Owner) *const Value {
        return @ptrCast(self);
    }
    fn destroy(self: *Owner) void {
        for (self.retained) |value| if (value) |retained| values.destroy(retained);
        self.arena.deinit();
        self.allocator.destroy(self);
    }
};
