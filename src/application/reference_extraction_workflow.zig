const std = @import("std");
const owned = @import("../domain/reference_extraction_value.zig");
const evidence = @import("../domain/reference_evidence.zig");
const evidence_values = @import("reference_evidence_workflow.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const data = @import("../domain/pipeline_data.zig");
const pipeline = @import("../domain/pipeline.zig");

pub const raw_schema = values.schema(.raw_reference_extraction, owned.Value, 1, null);
pub const parsed_schema = values.schema(.parsed_reference_extraction, owned.Value, 1, null);
pub const text_schema = values.schema(.text_validated_reference_extraction, owned.Value, 1, null);
pub const validated_schema = values.schema(.validated_reference_claims, owned.Value, 1, null);
pub const assigned_schema = values.schema(.reference_claim_identities, owned.Value, 1, null);
pub const ledger_schema = values.schema(.reference_extraction_ledger, owned.Value, 1, null);
pub const accounted_schema = values.schema(.accounted_reference_extraction, owned.Value, 1, null);
pub const schemas = [_]data.Schema{ raw_schema, parsed_schema, text_schema, validated_schema, assigned_schema, ledger_schema, accounted_schema };

pub const Parse = struct {
    pub const Action = @import("../actions/reference/parse_reference_extraction_results.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const prior = try read(&input.step.data, raw_schema, .raw);
        const owner = owned.create(self.allocator, null) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .parsed = self.action.execute(owner.arena.allocator(), prior.payload().raw) catch return error.OperationExecutionFailed };
        return publish(self.allocator, parsed_schema, owner, .ok);
    }
};
pub const ValidateText = struct {
    pub const Action = @import("../actions/reference/validate_reference_extraction_text.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = values.read(&input.step.data, evidence_values.inputs_schema, evidence.Inputs) catch return error.OperationExecutionFailed;
        const current = values.read(&input.step.data, @import("toolchain_workflow_values.zig").valid, @import("../domain/toolchain_safety.zig").ValidToolchain) catch return error.OperationExecutionFailed;
        const registry = values.read(&input.step.data, @import("passive_literal_workflow.zig").registry_schema, @import("../domain/passive_literals.zig").Registry) catch return error.OperationExecutionFailed;
        const prior = try read(&input.step.data, parsed_schema, .parsed);
        const owner = owned.create(self.allocator, prior) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .text_validated = self.action.execute(owner.arena.allocator(), registry.*, current, source.*, prior.payload().parsed) catch return error.OperationExecutionFailed };
        return publish(self.allocator, text_schema, owner, .ok);
    }
};
pub const Validate = struct {
    pub const Action = @import("../actions/reference/validate_reference_claims.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = values.read(&input.step.data, evidence_values.inputs_schema, evidence.Inputs) catch return error.OperationExecutionFailed;
        const prior = try read(&input.step.data, text_schema, .text_validated);
        const owner = owned.create(self.allocator, prior) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .validated = self.action.execute(owner.arena.allocator(), source.*, prior.payload().text_validated) catch return error.OperationExecutionFailed };
        return publish(self.allocator, validated_schema, owner, .ok);
    }
};
pub const Assign = struct {
    pub const Action = @import("../actions/reference/assign_reference_claim_identities.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const prior = try read(&input.step.data, validated_schema, .validated);
        const owner = owned.create(self.allocator, prior) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .assigned = self.action.execute(owner.arena.allocator(), prior.payload().validated) catch return error.OperationExecutionFailed };
        return publish(self.allocator, assigned_schema, owner, .ok);
    }
};
pub const Build = struct {
    pub const Action = @import("../actions/reference/build_reference_extraction_ledger.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const prior = try read(&input.step.data, assigned_schema, .assigned);
        const owner = owned.create(self.allocator, prior) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .ledger = self.action.execute(owner.arena.allocator(), prior.payload().assigned) catch return error.OperationExecutionFailed };
        return publish(self.allocator, ledger_schema, owner, .ok);
    }
};
pub const Account = struct {
    pub const Action = @import("../actions/reference/validate_reference_extraction_accounting.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .blocked, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = values.read(&input.step.data, evidence_values.inputs_schema, evidence.Inputs) catch return error.OperationExecutionFailed;
        const prior = try read(&input.step.data, ledger_schema, .ledger);
        const owner = owned.create(self.allocator, prior) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        const result = self.action.execute(source.*, prior.payload().ledger) catch return error.OperationExecutionFailed;
        owner.payload = .{ .accounted = result };
        return publish(self.allocator, accounted_schema, owner, switch (result.outcome) {
            .complete => .ok,
            .blocked => .blocked,
        });
    }
};

pub fn read(view: *const data.View, schema: data.Schema, stage: std.meta.Tag(owned.Payload)) operations.Error!*const owned.Value {
    const value = values.read(view, schema, owned.Value) catch return error.OperationExecutionFailed;
    if (value.payload().* != stage) return error.OperationExecutionFailed;
    return value;
}
/// Transfers ownership only on success, matching pipeline_values.adopt.
pub fn publish(allocator: std.mem.Allocator, schema: data.Schema, owner: *owned.Owner, outcome: @import("../domain/workflow.zig").OutcomeTag) operations.Error!execution.Candidate {
    var delta: pipeline.NodeDelta = .{};
    delta.data_writes[@intFromEnum(schema.key)] = values.adopt(allocator, schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch return error.OperationExecutionFailed;
    return .{ .outcome = outcome, .delta = delta };
}
