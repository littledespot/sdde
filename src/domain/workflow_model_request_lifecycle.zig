const std = @import("std");
const operation = @import("workflow_operation.zig");
const compilation = @import("workflow_compilation.zig");
const pipeline = @import("pipeline.zig");

pub const requires = @import("workflow_provider_authorization.zig").requires ++ [_]pipeline.DataKey{.provider_authorization_result};
pub const completion_requires = [_]pipeline.DataKey{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .model_payload_schema_result };
pub const completion_outcomes = [_]@import("workflow.zig").OutcomeTag{ .ok, .invalid, .failed, .cancelled };
pub const parameter: operation.ParameterDescriptor = .{
    .id = "transition",
    .kind = .enumeration,
    .required = true,
    .workflow_definition_safe = true,
    .allowed_values = &.{"invoked"},
};

// The data contract distinguishes lifecycle replacement from new assignment;
// no operation ID or workflow name activates runner behavior.
pub fn advances(replaces: []const pipeline.DataKey, produces: []const pipeline.DataKey) bool {
    return contains(replaces, .model_request_identity_ledger) and !contains(produces, .assigned_model_request);
}

pub fn completes(inputs: []const pipeline.DataKey) bool {
    return contains(inputs, .terminal_provider_operation);
}

pub fn validContract(contract: operation.Contract, capabilities: []const []const u8) bool {
    if (!advances(contract.replaces, contract.produces)) return true;
    if (!validEffects(contract.requires, contract.produces, contract.replaces, contract.optional, contract.invalidates) or
        contract.side_effect != .none or contract.runner_accounting != .none or contract.retry_limit != null or
        capabilities.len != 0) return false;
    if (completes(contract.requires)) return contract.parameters.len == 0 and
        std.mem.eql(@import("workflow.zig").OutcomeTag, contract.outcomes, &completion_outcomes);
    if (contract.parameters.len != 1) return false;
    const value = contract.parameters[0];
    return std.mem.eql(u8, value.id, parameter.id) and value.kind == .enumeration and value.required and value.workflow_definition_safe and
        value.allowed_values.len == 1 and std.mem.eql(u8, value.allowed_values[0], "invoked");
}

pub fn validProjection(step: compilation.CompiledStep) bool {
    if (!advances(step.replaces, step.produces)) return true;
    return validEffects(step.requires, step.produces, step.replaces, step.optional, step.invalidates) and
        step.side_effect == .none and step.runner_accounting == .none and step.retry_authority == null and
        step.capabilities.len == 0 and (if (completes(step.requires)) step.parameters.len == 0 and
        std.mem.eql(@import("workflow.zig").OutcomeTag, step.outcomes, &completion_outcomes) else transition(step.parameters) != null);
}

pub fn transition(parameters: []const compilation.CompiledParameter) ?@import("model_request_identity.zig").LifecycleTransition {
    if (parameters.len != 1) return null;
    const value = parameters[0];
    if (!std.mem.eql(u8, value.id.bytes, parameter.id) or value.value != .enumeration or !std.mem.eql(u8, value.value.enumeration, "invoked")) return null;
    return .invoked;
}

fn validEffects(inputs: []const pipeline.DataKey, produces: []const pipeline.DataKey, replaces: []const pipeline.DataKey, optional: []const pipeline.DataKey, invalidates: []const pipeline.DataKey) bool {
    const required: []const pipeline.DataKey = if (completes(inputs)) &completion_requires else &requires;
    if (completes(inputs) and inputs.len != required.len) return false;
    for (required) |key| if (!contains(inputs, key)) return false;
    return produces.len == 0 and optional.len == 0 and invalidates.len == 0 and
        std.mem.eql(pipeline.DataKey, replaces, &.{.model_request_identity_ledger});
}

fn contains(keys: []const pipeline.DataKey, key: pipeline.DataKey) bool {
    return std.mem.indexOfScalar(pipeline.DataKey, keys, key) != null;
}
