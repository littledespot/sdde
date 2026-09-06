const std = @import("std");
const operation = @import("workflow_operation.zig");
const compilation = @import("workflow_compilation.zig");
const pipeline = @import("pipeline.zig");
const capability = @import("workflow_capability.zig");

pub const requires = [_]pipeline.DataKey{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .assigned_provider_operation };
pub const parameter: operation.ParameterDescriptor = .{
    .id = "timeout-ms",
    .kind = .integer,
    .required = true,
    .workflow_definition_safe = true,
    .integer_min = 1,
};

pub fn prepares(produces: []const pipeline.DataKey) bool {
    return std.mem.indexOfScalar(pipeline.DataKey, produces, .provider_authorization_result) != null;
}

pub fn hasInputs(keys: []const pipeline.DataKey) bool {
    for (requires) |key| if (std.mem.indexOfScalar(pipeline.DataKey, keys, key) == null) return false;
    return true;
}

fn hasConsumerInputs(keys: []const pipeline.DataKey) bool {
    for (requires) |key| {
        if (key == .assigned_provider_operation) continue;
        if (std.mem.indexOfScalar(pipeline.DataKey, keys, key) == null) return false;
    }
    return (std.mem.indexOfScalar(pipeline.DataKey, keys, .assigned_provider_operation) != null) !=
        (std.mem.indexOfScalar(pipeline.DataKey, keys, .invoked_provider_operation) != null);
}

pub fn validContract(contract: operation.Contract, capabilities: []const []const u8) bool {
    if (std.mem.indexOfScalar(pipeline.DataKey, contract.replaces, .provider_authorization_result) != null) return false;
    if ((std.mem.indexOfScalar(pipeline.DataKey, contract.requires, .provider_authorization_result) != null or
        std.mem.indexOfScalar(pipeline.DataKey, contract.optional, .provider_authorization_result) != null) and !hasConsumerInputs(contract.requires)) return false;
    if (!prepares(contract.produces)) return !containsCapability(capabilities);
    if (!hasInputs(contract.requires) or !std.mem.eql(pipeline.DataKey, contract.produces, &.{.provider_authorization_result}) or
        contract.runner_accounting != .none or contract.side_effect != .none or contract.retry_limit != null or
        !containsCapability(capabilities) or contract.parameters.len != 1) return false;
    const value = contract.parameters[0];
    return std.mem.eql(u8, value.id, parameter.id) and value.kind == .integer and value.required and
        value.workflow_definition_safe and value.integer_min == parameter.integer_min and value.integer_max == parameter.integer_max;
}

pub fn validProjection(step: compilation.CompiledStep) bool {
    if (!prepares(step.produces)) return !containsCapability(step.capabilities);
    return hasInputs(step.requires) and std.mem.eql(pipeline.DataKey, step.produces, &.{.provider_authorization_result}) and
        step.side_effect == .none and step.runner_accounting == .none and
        step.retry_authority == null and containsCapability(step.capabilities) and timeout(step.parameters) != null;
}

pub fn timeout(parameters: []const compilation.CompiledParameter) ?u64 {
    if (parameters.len != 1) return null;
    const value = parameters[0];
    if (!std.mem.eql(u8, value.id.bytes, parameter.id) or value.value != .integer or value.value.integer <= 0) return null;
    return @intCast(value.value.integer);
}

fn containsCapability(capabilities: []const []const u8) bool {
    for (capabilities) |value| if (std.mem.eql(u8, value, capability.provider_authorization)) return true;
    return false;
}
