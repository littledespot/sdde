const std = @import("std");
const pipeline = @import("pipeline.zig");
const operation = @import("workflow_operation.zig");
const compilation = @import("workflow_compilation.zig");
const capabilities = @import("workflow_capability.zig");

pub const requires = [_]pipeline.DataKey{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .invoked_provider_operation, .provider_authorization_result };
pub const produces = [_]pipeline.DataKey{.provider_invocation_result};
pub const validation_requires = [_]pipeline.DataKey{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .invoked_provider_operation, .provider_invocation_result };
pub const decode_requires = [_]pipeline.DataKey{ .model_request_identity_ledger, .prepared_model_request, .provider_invocation_validation_result };
pub const payload_schema_requires = [_]pipeline.DataKey{ .model_request_identity_ledger, .prepared_model_request, .model_envelope_result };

pub fn validContract(contract: operation.Contract, ports: []const []const u8) bool {
    return valid(contract.requires, contract.produces, contract.optional, contract.replaces, contract.invalidates, contract.side_effect, contract.runner_accounting, contract.parameters.len, contract.retry_limit != null, ports);
}

pub fn validProjection(step: compilation.CompiledStep) bool {
    return valid(step.requires, step.produces, step.optional, step.replaces, step.invalidates, step.side_effect, step.runner_accounting, step.parameters.len, step.retry_authority != null, step.capabilities);
}

fn valid(inputs: []const pipeline.DataKey, outputs: []const pipeline.DataKey, optional: []const pipeline.DataKey, replaces: []const pipeline.DataKey, invalidates: []const pipeline.DataKey, effect: pipeline.SideEffect, accounting: pipeline.RunnerAccountingCapability, parameters: usize, retry: bool, ports: []const []const u8) bool {
    for ([_]pipeline.DataKey{ .provider_invocation_validation_result, .model_envelope_result, .model_payload_schema_result }) |key| {
        if (std.mem.indexOfScalar(pipeline.DataKey, replaces, key) != null) return false;
    }
    const response_inputs: ?[]const pipeline.DataKey = if (validates(outputs)) &validation_requires else if (std.mem.indexOfScalar(pipeline.DataKey, outputs, .model_envelope_result) != null) &decode_requires else if (std.mem.indexOfScalar(pipeline.DataKey, outputs, .model_payload_schema_result) != null) &payload_schema_requires else null;
    if (response_inputs) |required| {
        if (outputs.len != 1 or effect != .none or accounting != .none or ports.len != 0 or
            optional.len != 0 or replaces.len != 0 or invalidates.len != 0 or parameters != 0 or retry) return false;
        for (required) |key| {
            if (std.mem.indexOfScalar(pipeline.DataKey, inputs, key) == null) return false;
        }
    }
    if (std.mem.indexOfScalar(pipeline.DataKey, replaces, .provider_invocation_result) != null) return false;
    const publishes = std.mem.indexOfScalar(pipeline.DataKey, outputs, .provider_invocation_result) != null;
    if (effect != .model_call) return !publishes;
    if (!std.mem.eql(pipeline.DataKey, outputs, &produces) or optional.len != 0 or replaces.len != 0 or invalidates.len != 0 or
        parameters != 0 or retry or accounting != .none or ports.len != 1 or !std.mem.eql(u8, ports[0], capabilities.model_provider)) return false;
    for (requires) |key| if (std.mem.indexOfScalar(pipeline.DataKey, inputs, key) == null) return false;
    return true;
}

pub fn validates(outputs: []const pipeline.DataKey) bool {
    return std.mem.indexOfScalar(pipeline.DataKey, outputs, .provider_invocation_validation_result) != null;
}
