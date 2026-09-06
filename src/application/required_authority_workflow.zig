//! One action per binding. YAML, not this module, chooses their sequence.
const std = @import("std");
const a = @import("../domain/required_authority.zig");
const owned = @import("required_authority_values.zig");
const values = @import("pipeline_values.zig");
const data = @import("../domain/pipeline_data.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const gate = @import("../domain/workflow_gate.zig");
pub const inputs_schema = values.schema(.required_authority_inputs, owned.Value, 1, null);
pub const ledger_schema = values.schema(.required_authority_ledger, owned.Value, 1, null);
pub const raw_schema = values.schema(.raw_required_authority_observations, owned.Value, 1, null);
pub const observations_schema = values.schema(.required_authority_observations, owned.Value, 1, null);
pub const result_schema = values.schema(.required_authority_result, owned.Value, 1, null);
pub const content_schema = values.schema(.identified_specification_content, owned.Value, 1, null);
pub const gate_schema = values.schema(.required_authority_gate, gate.Decision, 1, @sizeOf(gate.Decision));
pub const schemas = [_]data.Schema{ inputs_schema, ledger_schema, raw_schema, observations_schema, result_schema, content_schema, gate_schema };
pub const gate_contract: gate.Contract = .{ .id = .{ .bytes = "required-authority@1" }, .issuer = .{ .bytes = "validate-required-authority-reconciliation" }, .evidence = .required_authority_gate, .authority = &.{ .required_authority_inputs, .required_authority_observations, .required_authority_result } };
const operation_outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .needs_user, .blocked };
const structural_outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .blocked };

pub const ProjectSpecification = struct {
    pub const Action = @import("../actions/authority/build_specification_authority_requirements.zig").Action;
    pub const outcomes = structural_outcomes;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const feature = values.read(&input.step.data, @import("feature_directory_workflow.zig").selector, @import("../domain/feature_directory.zig").Selector) catch return error.OperationExecutionFailed;
        const references = @import("reference_extraction_workflow.zig").read(&input.step.data, @import("reference_reconciliation_workflow.zig").accounted_schema, .reconciliation_accounted) catch return error.OperationExecutionFailed;
        const content = if (input.step.data.contains(.identified_specification_content)) owned.read(&input.step.data, content_schema, .content) catch return error.OperationExecutionFailed else null;
        const current = if (input.step.data.contains(.specification_generation_session)) try @import("specification_workflow.zig").readSession(&input.step.data) else null;
        const brief = if (current) |value| if (value.units[0]) |checked| checked.response.content.brief else null else null;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .inputs = self.action.execute(owner.arena.allocator(), feature.feature_id, references.payload().reconciliation_accounted, content, brief) catch |err| return reject(self.allocator, inputs_schema, owner, err) };
        return owned.publish(self.allocator, inputs_schema, owner, .ok) catch return error.OperationExecutionFailed;
    }
};
pub const BuildObservations = struct {
    pub const Action = @import("../actions/authority/build_required_authority_observations.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const ledger = owned.read(&input.step.data, ledger_schema, .ledger) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .observations = self.action.execute(owner.arena.allocator(), ledger) catch return error.OperationExecutionFailed };
        return owned.publish(self.allocator, observations_schema, owner, .ok) catch error.OperationExecutionFailed;
    }
};
pub const Retire = struct {
    pub const Action = @import("../actions/authority/retire_required_authority_projection.zig").Action;
    action: Action = .{},
    pub fn invoke(context: ?*@This(), _: operations.Input) operations.Error!execution.Candidate {
        return .{ .outcome = .ok, .delta = context.?.action.execute() };
    }
};

pub const Build = struct {
    pub const Action = @import("../actions/authority/build_required_authority_ledger.zig").Action;
    pub const outcomes = structural_outcomes;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = owned.read(&input.step.data, inputs_schema, .inputs) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .ledger = self.action.execute(owner.arena.allocator(), source) catch |err| return reject(self.allocator, ledger_schema, owner, err) };
        return owned.publish(self.allocator, ledger_schema, owner, .ok) catch return error.OperationExecutionFailed;
    }
};
pub const Parse = struct {
    pub const Action = @import("../actions/authority/parse_required_authority_observations.zig").Action;
    pub const outcomes = structural_outcomes;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const raw = owned.read(&input.step.data, raw_schema, .raw) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .observations = self.action.execute(owner.arena.allocator(), raw) catch |err| return reject(self.allocator, observations_schema, owner, err) };
        return owned.publish(self.allocator, observations_schema, owner, .ok) catch return error.OperationExecutionFailed;
    }
};
pub const Reconcile = struct {
    pub const Action = @import("../actions/authority/reconcile_required_authorities.zig").Action;
    pub const outcomes = operation_outcomes;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const ledger = owned.read(&input.step.data, ledger_schema, .ledger) catch return error.OperationExecutionFailed;
        const observations = owned.read(&input.step.data, observations_schema, .observations) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        const result = self.action.execute(owner.arena.allocator(), ledger, observations) catch |err| return reject(self.allocator, result_schema, owner, err);
        owner.payload = .{ .result = result };
        return owned.publish(self.allocator, result_schema, owner, status(result)) catch return error.OperationExecutionFailed;
    }
};
pub const Validate = struct {
    pub const Action = @import("../actions/authority/validate_required_authority_reconciliation.zig").Action;
    pub const outcomes = operation_outcomes;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = owned.read(&input.step.data, inputs_schema, .inputs) catch return error.OperationExecutionFailed;
        const observations = owned.read(&input.step.data, observations_schema, .observations) catch return error.OperationExecutionFailed;
        const result = owned.read(&input.step.data, result_schema, .result) catch return error.OperationExecutionFailed;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const outcome: @import("../domain/workflow.zig").OutcomeTag = checked: {
            const accepted = self.action.execute(arena.allocator(), source, observations, result) catch |err| switch (err) {
                error.OutOfMemory => return error.OperationExecutionFailed,
                error.InvalidRequiredAuthority => break :checked .blocked,
            };
            break :checked if (accepted) .ok else if (result.continuation == .needs_user) .needs_user else .blocked;
        };
        var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
        delta.data_writes[@intFromEnum(gate_schema.key)] = values.create(self.allocator, gate_schema, gate.Decision, if (outcome == .ok) .accepted else .rejected) catch return error.OperationExecutionFailed;
        return .{ .outcome = outcome, .delta = delta };
    }
};
fn reject(allocator: std.mem.Allocator, schema: data.Schema, owner: *owned.Owner, err: a.Error) operations.Error!execution.Candidate {
    if (err == error.OutOfMemory) return error.OperationExecutionFailed;
    owner.payload = .{ .rejected = .invalid_contract };
    return owned.publish(allocator, schema, owner, .blocked) catch return error.OperationExecutionFailed;
}
fn status(result: a.Result) @import("../domain/workflow.zig").OutcomeTag {
    return switch (result.continuation) {
        .all_resolved => .ok,
        .needs_user => .needs_user,
        .blocked => .blocked,
    };
}
