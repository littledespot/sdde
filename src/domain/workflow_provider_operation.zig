const std = @import("std");
const operation = @import("workflow_operation.zig");
const compilation = @import("workflow_compilation.zig");
const provider = @import("llm_provider_operation.zig");
const pipeline = @import("pipeline.zig");

pub const invocation_requires = @import("workflow_provider_authorization.zig").requires ++ [_]pipeline.DataKey{.provider_authorization_result};
pub const completion_requires = [_]pipeline.DataKey{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .invoked_provider_operation, .provider_invocation_validation_result };
pub const invocation_parameter: operation.ParameterDescriptor = .{
    .id = "transition",
    .kind = .enumeration,
    .required = true,
    .workflow_definition_safe = true,
    .allowed_values = &.{"invoked"},
};

pub fn invokes(produces: []const pipeline.DataKey) bool {
    return std.mem.indexOfScalar(pipeline.DataKey, produces, .invoked_provider_operation) != null;
}

pub fn completes(produces: []const pipeline.DataKey) bool {
    return std.mem.indexOfScalar(pipeline.DataKey, produces, .terminal_provider_operation) != null;
}

pub fn validContract(contract: operation.Contract, capabilities: []const []const u8) bool {
    if (contract.runner_accounting != .advance_provider_operation) return true;
    if (completes(contract.produces)) return validCompletionEffects(contract.requires, contract.produces, contract.optional, contract.replaces, contract.invalidates) and
        contract.side_effect == .none and contract.retry_limit == null and capabilities.len == 0 and contract.parameters.len == 0;
    if (!invokes(contract.produces)) return validDescriptors(contract.parameters);
    if (!validInvocationEffects(contract.requires, contract.produces, contract.optional, contract.replaces, contract.invalidates) or
        contract.side_effect != .none or contract.retry_limit != null or capabilities.len != 0 or contract.parameters.len != 1) return false;
    const value = contract.parameters[0];
    return std.mem.eql(u8, value.id, invocation_parameter.id) and value.kind == .enumeration and
        value.required and value.workflow_definition_safe and value.allowed_values.len == 1 and
        std.mem.eql(u8, value.allowed_values[0], "invoked");
}

fn validCompletionEffects(inputs: []const pipeline.DataKey, produces: []const pipeline.DataKey, optional: []const pipeline.DataKey, replaces: []const pipeline.DataKey, invalidates: []const pipeline.DataKey) bool {
    // No lease dependency or hidden data source may gate terminalization.
    if (inputs.len != completion_requires.len) return false;
    for (completion_requires) |key| if (std.mem.indexOfScalar(pipeline.DataKey, inputs, key) == null) return false;
    return std.mem.eql(pipeline.DataKey, produces, &.{.terminal_provider_operation}) and optional.len == 0 and replaces.len == 0 and
        std.mem.eql(pipeline.DataKey, invalidates, &.{.invoked_provider_operation});
}

fn validInvocationEffects(inputs: []const pipeline.DataKey, produces: []const pipeline.DataKey, optional: []const pipeline.DataKey, replaces: []const pipeline.DataKey, invalidates: []const pipeline.DataKey) bool {
    for (invocation_requires) |key| if (std.mem.indexOfScalar(pipeline.DataKey, inputs, key) == null) return false;
    return std.mem.eql(pipeline.DataKey, produces, &.{.invoked_provider_operation}) and optional.len == 0 and replaces.len == 0 and
        std.mem.eql(pipeline.DataKey, invalidates, &.{.assigned_provider_operation});
}

/// Explicit YAML selection only; counting is never an inference prerequisite.
pub const kind_parameter: operation.ParameterDescriptor = .{
    .id = "kind",
    .kind = .enumeration,
    .required = true,
    .workflow_definition_safe = true,
    .allowed_values = &.{ "inference", "input-token-count" },
};

pub fn validDescriptors(parameters: []const operation.ParameterDescriptor) bool {
    if (parameters.len != 1) return false;
    const value = parameters[0];
    if (!std.mem.eql(u8, value.id, kind_parameter.id) or value.kind != .enumeration or
        !value.required or !value.workflow_definition_safe or value.allowed_values.len != kind_parameter.allowed_values.len) return false;
    for (value.allowed_values, kind_parameter.allowed_values) |actual, expected| if (!std.mem.eql(u8, actual, expected)) return false;
    return true;
}

pub fn validProjection(step: compilation.CompiledStep) bool {
    if (step.runner_accounting != .advance_provider_operation) return true;
    if (completes(step.produces)) return validCompletionEffects(step.requires, step.produces, step.optional, step.replaces, step.invalidates) and
        step.side_effect == .none and step.retry_authority == null and step.capabilities.len == 0 and step.parameters.len == 0;
    if (!invokes(step.produces)) return resolve(step.parameters) != null;
    return validInvocationEffects(step.requires, step.produces, step.optional, step.replaces, step.invalidates) and
        step.side_effect == .none and step.retry_authority == null and step.capabilities.len == 0 and invokesTransition(step.parameters);
}

pub fn invokesTransition(parameters: []const compilation.CompiledParameter) bool {
    if (parameters.len != 1) return false;
    const value = parameters[0];
    return std.mem.eql(u8, value.id.bytes, invocation_parameter.id) and value.value == .enumeration and
        std.mem.eql(u8, value.value.enumeration, "invoked");
}

pub fn resolve(parameters: []const compilation.CompiledParameter) ?provider.ProviderOperationKind {
    if (parameters.len != 1) return null;
    const parameter = parameters[0];
    if (!std.mem.eql(u8, parameter.id.bytes, kind_parameter.id) or parameter.value != .enumeration) return null;
    const value = parameter.value.enumeration;
    if (std.mem.eql(u8, value, "inference")) return .inference;
    if (std.mem.eql(u8, value, "input-token-count")) return .input_token_count;
    return null;
}
