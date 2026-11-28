const std = @import("std");
const operation = @import("workflow_operation.zig");
const compilation = @import("workflow_compilation.zig");
const pipeline = @import("pipeline.zig");
const capability = @import("workflow_capability.zig");

pub const requires = [_]pipeline.DataKey{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .assigned_provider_operation };
// Authorization declares no parameter: the provider-operation deadline is the
// bound catalogue entry's `requestTimeoutMs`, never a workflow value (ADR 0030).

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
    var phases: usize = 0;
    for ([_]pipeline.DataKey{ .assigned_provider_operation, .invoked_provider_operation, .terminal_provider_operation }) |key| {
        if (std.mem.indexOfScalar(pipeline.DataKey, keys, key) != null) phases += 1;
    }
    return phases == 1;
}

pub fn validContract(contract: operation.Contract, capabilities: []const capability.Capability) bool {
    if (std.mem.indexOfScalar(pipeline.DataKey, contract.replaces, .provider_authorization_result) != null) return false;
    if ((std.mem.indexOfScalar(pipeline.DataKey, contract.requires, .provider_authorization_result) != null or
        std.mem.indexOfScalar(pipeline.DataKey, contract.optional, .provider_authorization_result) != null) and !hasConsumerInputs(contract.requires)) return false;
    if (!prepares(contract.produces)) return !capability.contains(capabilities, .provider_authorization);
    return hasInputs(contract.requires) and std.mem.eql(pipeline.DataKey, contract.produces, &.{.provider_authorization_result}) and
        contract.runner_accounting == .none and contract.side_effect == .none and contract.retry_limit == null and
        capability.contains(capabilities, .provider_authorization) and contract.parameters.len == 0;
}

pub fn validProjection(step: compilation.CompiledStep) bool {
    if ((std.mem.indexOfScalar(pipeline.DataKey, step.requires, .provider_authorization_result) != null or
        std.mem.indexOfScalar(pipeline.DataKey, step.optional, .provider_authorization_result) != null) and !hasConsumerInputs(step.requires)) return false;
    if (!prepares(step.produces)) return !capability.contains(step.capabilities, .provider_authorization);
    return hasInputs(step.requires) and std.mem.eql(pipeline.DataKey, step.produces, &.{.provider_authorization_result}) and
        step.side_effect == .none and step.runner_accounting == .none and
        step.retry_authority == null and capability.contains(step.capabilities, .provider_authorization) and step.parameters.len == 0;
}
