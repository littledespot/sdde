const std = @import("std");
const execution = @import("../domain/workflow_execution.zig");
const pipeline = @import("../domain/pipeline.zig");
const workflow = @import("../domain/workflow.zig");
const compilation = @import("../domain/workflow_compilation.zig");
const operation = @import("../domain/workflow_operation.zig");
const provider_binding = @import("../domain/llm_provider_binding.zig");
const workflow_retry = @import("../domain/workflow_retry.zig");
const data = @import("../domain/pipeline_data.zig");

pub const Error = error{OperationExecutionFailed};

pub const InvocationInput = struct {
    arguments: []const []const u8,
};

pub const StepInput = struct {
    data: data.View,
    step: *const compilation.CompiledStep,
    resources: []const compilation.CompiledResource,
    model_binding: ?*const provider_binding.ValidatedProviderModelBinding,
    log: pipeline.WorkflowLog,
};

pub const Input = union(enum) {
    invocation: InvocationInput,
    step: StepInput,
};

pub const Entry = struct {
    contract: operation.Contract,
    context: ?*anyopaque = null,
    invoke_fn: *const fn (?*anyopaque, Input) Error!execution.Candidate,

    pub fn invoke(self: Entry, input: Input) Error!execution.Candidate {
        return self.invoke_fn(self.context, input);
    }
};

pub const Registry = struct {
    operations: []const Entry,
    data_schemas: []const data.Schema = &.{},
    policies: []const operation.PolicyProfile,
    gates: []const []const u8,
    capabilities: []const []const u8,

    pub fn resolveOperation(self: *const Registry, id: workflow.RegisteredRef) ?*const Entry {
        var found: ?*const Entry = null;
        for (self.operations) |*entry| {
            if (!std.mem.eql(u8, entry.contract.id, id.bytes)) continue;
            if (found != null) return null;
            found = entry;
        }
        return found;
    }

    pub fn resolvePolicy(self: *const Registry, id: workflow.RegisteredRef) ?*const operation.PolicyProfile {
        var found: ?*const operation.PolicyProfile = null;
        for (self.policies) |*profile| {
            if (!std.mem.eql(u8, profile.id, id.bytes)) continue;
            if (found != null) return null;
            found = profile;
        }
        return found;
    }

    pub fn validate(self: *const Registry) bool {
        if (!uniqueStrings(self.gates) or !uniqueStrings(self.capabilities)) return false;
        for (self.data_schemas, 0..) |schema, index| {
            if (!schema.valid()) return false;
            for (self.data_schemas[0..index]) |prior| if (schema.key == prior.key) return false;
        }
        for (self.operations, 0..) |entry, index| {
            if (workflow.RegisteredRef.parse(entry.contract.id) == null or
                !validContract(entry.contract)) return false;
            inline for (.{ entry.contract.requires, entry.contract.optional, entry.contract.produces, entry.contract.replaces, entry.contract.invalidates }) |keys| {
                for (keys) |key| if (data.find(self.data_schemas, key) == null) return false;
            }
            for (self.operations[0..index]) |prior| {
                if (std.mem.eql(u8, prior.contract.id, entry.contract.id)) return false;
            }
            for (entry.contract.gates) |gate| if (!containsExactlyOnce(self.gates, gate)) return false;
            for (entry.contract.capabilities) |capability| if (!containsExactlyOnce(self.capabilities, capability)) return false;
        }
        for (self.policies, 0..) |profile, index| {
            if (workflow.RegisteredRef.parse(profile.id) == null or
                !uniqueStrings(profile.allowed_capabilities) or
                !uniqueOutcomes(profile.allowed_terminal_outcomes) or
                !profile.total_model_token_budget.isValid()) return false;
            for (self.policies[0..index]) |prior| {
                if (std.mem.eql(u8, prior.id, profile.id)) return false;
            }
            for (profile.allowed_capabilities) |capability| if (!containsExactlyOnce(self.capabilities, capability)) return false;
        }
        return true;
    }
};

fn validContract(contract: operation.Contract) bool {
    if (contract.outcomes.len == 0 or !uniqueOutcomes(contract.outcomes) or
        !uniqueStrings(contract.gates) or !uniqueStrings(contract.capabilities) or
        !validDataContract(contract)) return false;
    if (contract.kind == .invocation and
        (contract.parameters.len != 0 or contract.requires.len != 0 or contract.optional.len != 0 or contract.replaces.len != 0 or
            contract.invalidates.len != 0 or contract.side_effect != .none or contract.gates.len != 0 or
            contract.capabilities.len != 0 or contract.retry_limit != null or
            contract.outcomes.len != 1 or contract.outcomes[0] != .ok)) return false;
    for (contract.parameters, 0..) |descriptor, index| {
        if (workflow.WorkflowParameterId.parse(descriptor.id) == null or
            !descriptor.workflow_definition_safe or descriptor.integer_min > descriptor.integer_max or
            descriptor.string_max_bytes == 0 or descriptor.string_max_bytes > 128 or
            (descriptor.kind == .resource) != (descriptor.resource_kind != null) or
            !uniqueStrings(descriptor.allowed_values)) return false;
        for (contract.parameters[0..index]) |prior| {
            if (std.mem.eql(u8, prior.id, descriptor.id)) return false;
        }
    }
    const model_capable = containsExactlyOnce(contract.capabilities, "model-provider");
    var model_slot_count: usize = 0;
    for (contract.parameters) |descriptor| {
        if (descriptor.kind != .model_slot) continue;
        if (!descriptor.required or descriptor.allowed_values.len != 0 or descriptor.resource_kind != null) return false;
        model_slot_count += 1;
    }
    if (model_capable != (model_slot_count == 1)) return false;
    if (contract.retry_limit) |limit| {
        if (contract.kind != .step or limit.maximum == 0) return false;
        const descriptor = findParameter(contract.parameters, workflow_retry.parameter_id) orelse return false;
        if (descriptor.kind != .integer or !descriptor.required or descriptor.integer_min != 0 or
            descriptor.integer_max > limit.maximum) return false;
    } else if (findParameter(contract.parameters, workflow_retry.parameter_id) != null) {
        return false;
    }
    return true;
}

fn validDataContract(contract: operation.Contract) bool {
    if (!uniqueKeys(contract.requires) or !uniqueKeys(contract.optional) or !uniqueKeys(contract.produces) or
        !uniqueKeys(contract.replaces) or !uniqueKeys(contract.invalidates)) return false;
    for (contract.optional) |key| if (containsKey(contract.requires, key)) return false;
    for (contract.produces) |key| {
        if (containsKey(contract.requires, key) or containsKey(contract.replaces, key) or
            containsKey(contract.invalidates, key)) return false;
    }
    for (contract.replaces) |key| if (containsKey(contract.invalidates, key)) return false;
    return true;
}

fn uniqueKeys(values: []const pipeline.DataKey) bool {
    for (values, 0..) |value, index| {
        for (values[0..index]) |prior| if (prior == value) return false;
    }
    return true;
}

fn containsKey(values: []const pipeline.DataKey, expected: pipeline.DataKey) bool {
    for (values) |value| if (value == expected) return true;
    return false;
}

fn findParameter(parameters: []const operation.ParameterDescriptor, id: []const u8) ?operation.ParameterDescriptor {
    for (parameters) |parameter| if (std.mem.eql(u8, parameter.id, id)) return parameter;
    return null;
}

fn uniqueStrings(values: []const []const u8) bool {
    for (values, 0..) |value, index| {
        if (value.len == 0) return false;
        for (values[0..index]) |prior| if (std.mem.eql(u8, prior, value)) return false;
    }
    return true;
}

fn uniqueOutcomes(values: []const workflow.OutcomeTag) bool {
    for (values, 0..) |value, index| {
        for (values[0..index]) |prior| if (prior == value) return false;
    }
    return true;
}

fn containsExactlyOnce(values: []const []const u8, expected: []const u8) bool {
    var count: usize = 0;
    for (values) |value| {
        if (std.mem.eql(u8, value, expected)) count += 1;
    }
    return count == 1;
}

test "one registry rejects duplicate and structurally invalid operations" {
    try std.testing.expect(!@hasField(operation.PolicyProfile, "retry_limit"));
    try std.testing.expect(!@hasField(operation.PolicyProfile, "attempts"));
    const noop: Entry = .{
        .contract = .{ .id = "core.noop@1", .kind = .step, .outcomes = &.{.ok}, .side_effect = .none },
        .invoke_fn = testInvoke,
    };
    const valid: Registry = .{
        .operations = &.{noop},
        .policies = &.{.{
            .id = "core.safe@1",
            .allowed_capabilities = &.{},
            .allowed_terminal_outcomes = &.{.ok},
            .total_model_token_budget = .{ .value = 1 },
        }},
        .gates = &.{},
        .capabilities = &.{},
    };
    try std.testing.expect(valid.validate());
    var duplicate = valid;
    duplicate.operations = &.{ noop, noop };
    try std.testing.expect(!duplicate.validate());

    const hidden_invocation: Entry = .{
        .contract = .{ .id = "core.hidden@1", .kind = .invocation, .outcomes = &.{ .ok, .failed }, .side_effect = .none },
        .invoke_fn = testInvoke,
    };
    duplicate.operations = &.{hidden_invocation};
    try std.testing.expect(!duplicate.validate());

    const model_without_slot: Entry = .{
        .contract = .{
            .id = "model.invalid@1",
            .kind = .step,
            .outcomes = &.{.ok},
            .side_effect = .none,
            .capabilities = &.{"model-provider"},
        },
        .invoke_fn = testInvoke,
    };
    var invalid_model_registry = valid;
    invalid_model_registry.operations = &.{model_without_slot};
    invalid_model_registry.capabilities = &.{"model-provider"};
    try std.testing.expect(!invalid_model_registry.validate());

    const hidden_slot: Entry = .{
        .contract = .{
            .id = "model.hidden-slot@1",
            .kind = .step,
            .parameters = &.{.{
                .id = "slot",
                .kind = .model_slot,
                .required = true,
                .workflow_definition_safe = true,
            }},
            .outcomes = &.{.ok},
            .side_effect = .none,
        },
        .invoke_fn = testInvoke,
    };
    invalid_model_registry.operations = &.{hidden_slot};
    invalid_model_registry.capabilities = &.{};
    try std.testing.expect(!invalid_model_registry.validate());

    var zero_budget = valid;
    zero_budget.policies = &.{.{
        .id = "core.safe@1",
        .allowed_capabilities = &.{},
        .allowed_terminal_outcomes = &.{.ok},
        .total_model_token_budget = .{ .value = 0 },
    }};
    try std.testing.expect(!zero_budget.validate());

    const hidden_retry: Entry = .{
        .contract = .{
            .id = "core.hidden-retry@1",
            .kind = .step,
            .parameters = &.{.{
                .id = "retry-limit",
                .kind = .integer,
                .required = true,
                .workflow_definition_safe = true,
                .integer_min = 0,
                .integer_max = 2,
            }},
            .outcomes = &.{.ok},
            .side_effect = .none,
        },
        .invoke_fn = testInvoke,
    };
    var invalid_retry_registry = valid;
    invalid_retry_registry.operations = &.{hidden_retry};
    try std.testing.expect(!invalid_retry_registry.validate());

    var declared_retry = hidden_retry;
    declared_retry.contract.retry_limit = .{ .maximum = 2 };
    try std.testing.expect((Registry{
        .operations = &.{declared_retry},
        .policies = valid.policies,
        .gates = &.{},
        .capabilities = &.{},
    }).validate());
    declared_retry.contract.parameters = &.{.{
        .id = "retry-limit",
        .kind = .integer,
        .required = true,
        .workflow_definition_safe = true,
        .integer_min = 0,
        .integer_max = 3,
    }};
    invalid_retry_registry.operations = &.{declared_retry};
    try std.testing.expect(!invalid_retry_registry.validate());
}

fn testInvoke(_: ?*anyopaque, _: Input) Error!execution.Candidate {
    return error.OperationExecutionFailed;
}
