const std = @import("std");
const operation = @import("workflow_operation.zig");
const compilation = @import("workflow_compilation.zig");
const provider = @import("llm_provider_operation.zig");

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
    return step.runner_accounting != .advance_provider_operation or resolve(step.parameters) != null;
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
