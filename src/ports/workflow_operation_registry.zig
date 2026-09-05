const std = @import("std");
const execution = @import("../domain/workflow_execution.zig");
const pipeline = @import("../domain/pipeline.zig");
const workflow = @import("../domain/workflow.zig");
const compilation = @import("../domain/workflow_compilation.zig");
const operation = @import("../domain/workflow_operation.zig");
const provider_binding = @import("../domain/llm_provider_binding.zig");
const workflow_retry = @import("../domain/workflow_retry.zig");
const data = @import("../domain/pipeline_data.zig");
const gate = @import("../domain/workflow_gate.zig");
const capability_contract = @import("../domain/workflow_capability.zig");

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

pub const Binding = struct {
    context: ?*anyopaque = null,
    implementation: *const Implementation,

    pub const Implementation = struct {
        invoke_fn: *const fn (?*anyopaque, Input) Error!execution.Candidate,
        capabilities: []const []const u8,
        context_required: bool,
    };

    pub fn capabilities(self: Binding) []const []const u8 {
        return self.implementation.capabilities;
    }

    pub fn invoke(self: Binding, input: Input) Error!execution.Candidate {
        return self.implementation.invoke_fn(self.context, input);
    }
};

pub const Entry = struct {
    contract: operation.Contract,
    binding: Binding,

    pub fn invoke(self: Entry, input: Input) Error!execution.Candidate {
        return self.binding.invoke(input);
    }
};

pub const Registry = struct {
    operations: []const Entry,
    data_schemas: []const data.Schema = &.{},
    policies: []const operation.PolicyProfile,
    gates: []const gate.Contract,

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

    pub fn resolveGate(self: *const Registry, id: workflow.RegisteredRef) ?*const gate.Contract {
        var found: ?*const gate.Contract = null;
        for (self.gates) |*contract| {
            if (!std.mem.eql(u8, contract.id.bytes, id.bytes)) continue;
            if (found != null) return null;
            found = contract;
        }
        return found;
    }

    pub fn validate(self: *const Registry) bool {
        if (!self.validGates()) return false;
        for (self.data_schemas, 0..) |schema, index| {
            if (!schema.valid()) return false;
            for (self.data_schemas[0..index]) |prior| if (schema.key == prior.key) return false;
        }
        for (self.operations, 0..) |entry, index| {
            if (entry.binding.implementation.context_required and entry.binding.context == null) return false;
            if (workflow.RegisteredRef.parse(entry.contract.id) == null or
                !validContract(entry.contract, entry.binding.capabilities())) return false;
            inline for (.{ entry.contract.requires, entry.contract.optional, entry.contract.produces, entry.contract.replaces, entry.contract.invalidates }) |keys| {
                for (keys) |key| if (data.find(self.data_schemas, key) == null) return false;
            }
            for (self.operations[0..index]) |prior| {
                if (std.mem.eql(u8, prior.contract.id, entry.contract.id)) return false;
            }
            for (entry.contract.gates) |id| if (self.resolveGate(.{ .bytes = id }) == null) return false;
        }
        for (self.policies, 0..) |profile, index| {
            if (workflow.RegisteredRef.parse(profile.id) == null or
                !uniqueStrings(profile.allowed_capabilities) or
                !uniqueOutcomes(profile.allowed_terminal_outcomes) or
                !profile.total_model_token_budget.isValid()) return false;
            for (self.policies[0..index]) |prior| {
                if (std.mem.eql(u8, prior.id, profile.id)) return false;
            }
            for (profile.allowed_capabilities) |capability| if (!capability_contract.known(capability)) return false;
        }
        return true;
    }

    fn validGates(self: *const Registry) bool {
        for (self.gates, 0..) |contract, index| {
            if (workflow.RegisteredRef.parse(contract.id.bytes) == null or
                contract.authority.len == 0 or !uniqueKeys(contract.authority) or
                containsKey(contract.authority, contract.evidence)) return false;
            for (self.gates[0..index]) |prior| {
                if (prior.evidence == contract.evidence or std.mem.eql(u8, prior.id.bytes, contract.id.bytes)) return false;
            }
            const issuer = self.resolveOperation(contract.issuer) orelse return false;
            if (issuer.contract.kind != .step or issuer.binding.capabilities().len != 0 or issuer.contract.side_effect != .none or
                (!containsKey(issuer.contract.produces, contract.evidence) and !containsKey(issuer.contract.replaces, contract.evidence))) return false;
            for (contract.authority) |key| if (!containsKey(issuer.contract.requires, key)) return false;
            const schema = data.find(self.data_schemas, contract.evidence) orelse return false;
            if (schema.version != 1 or !std.mem.eql(u8, schema.type_name, @typeName(gate.Decision))) return false;
            for (self.operations) |entry| {
                if (std.mem.eql(u8, entry.contract.id, contract.issuer.bytes)) continue;
                if (containsKey(entry.contract.produces, contract.evidence) or containsKey(entry.contract.replaces, contract.evidence)) return false;
            }
        }
        return true;
    }
};

fn validContract(contract: operation.Contract, capabilities: []const []const u8) bool {
    if (contract.outcomes.len == 0 or !uniqueOutcomes(contract.outcomes) or
        !uniqueStrings(contract.gates) or !uniqueStrings(capabilities) or
        !validDataContract(contract)) return false;
    for (capabilities) |capability| if (!capability_contract.known(capability)) return false;
    if (contract.kind == .invocation and
        (contract.parameters.len != 0 or contract.requires.len != 0 or contract.optional.len != 0 or contract.replaces.len != 0 or
            contract.invalidates.len != 0 or contract.side_effect != .none or contract.gates.len != 0 or
            capabilities.len != 0 or contract.retry_limit != null or
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
    const model_capable = containsExactlyOnce(capabilities, "model-provider");
    var model_slot_count: usize = 0;
    for (contract.parameters) |descriptor| {
        if (descriptor.kind != .model_slot) continue;
        if (!descriptor.required or descriptor.allowed_values.len != 0 or descriptor.resource_kind != null) return false;
        model_slot_count += 1;
    }
    const requires_model_binding = contract.requiresModelBinding();
    if (model_slot_count > 1) return false;
    if (model_capable and !requires_model_binding) return false;
    if (requires_model_binding and !@import("../domain/workflow_model.zig").validDescriptors(contract.parameters)) return false;
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
