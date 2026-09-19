const std = @import("std");
const controls = @import("model_controls.zig");
const compilation = @import("workflow_compilation.zig");
const operation = @import("workflow_operation.zig");

pub const Requirements = struct {
    response_mode: controls.ResponseGuidanceMode,
};

// Shared generic model parameters. No workflow name, route, or model identity
// participates in this contract. Temperature is owned by provider capabilities.
pub const parameters = [_]operation.ParameterDescriptor{
    .{ .id = "response-mode", .kind = .enumeration, .required = true, .workflow_definition_safe = true, .allowed_values = &.{ "prompt-only", "native-schema" } },
};

pub fn validProjection(step: compilation.CompiledStep) bool {
    var capability_count: usize = 0;
    for (step.capabilities) |capability| {
        if (std.mem.eql(u8, capability, "model-provider")) capability_count += 1;
    }
    var slot_count: usize = 0;
    for (step.parameters) |parameter| {
        if (parameter.value != .model_slot) continue;
        if (@import("llm_provider_identity.zig").ModelSlotId.parse(parameter.value.model_slot.bytes) == null) return false;
        slot_count += 1;
    }
    if (capability_count > 1 or slot_count > 1 or
        (step.model != null) != (slot_count == 1) or
        (capability_count == 1 and step.model == null and !consumesPreparedRequest(step.requires)) or
        (slot_count != 0 and consumesPreparedRequest(step.requires))) return false;
    if (consumesPreparedRequest(step.requires)) {
        for (step.parameters) |parameter| {
            if (parameter.value == .resource or parameter.value == .model_slot or requestOverride(parameter.id.bytes)) return false;
        }
    }
    const model = step.model orelse return true;
    if (assignsRequest(step.produces, step.replaces) and !validResultSelection(step.parameters)) return false;
    const expected = resolve(step.parameters) orelse return false;
    return std.meta.eql(model, expected);
}

pub fn validDescriptors(descriptors: []const operation.ParameterDescriptor) bool {
    for (descriptors) |descriptor| {
        if (retiredParameter(descriptor.id)) return false;
    }
    for (parameters) |required| {
        var found = false;
        for (descriptors) |descriptor| {
            if (!std.mem.eql(u8, descriptor.id, required.id)) continue;
            if (descriptor.kind != required.kind or descriptor.required != required.required or
                descriptor.integer_min != required.integer_min or descriptor.integer_max != required.integer_max or
                descriptor.allowed_values.len != required.allowed_values.len) return false;
            for (descriptor.allowed_values, required.allowed_values) |a, b| if (!std.mem.eql(u8, a, b)) return false;
            found = true;
        }
        if (!found) return false;
    }
    for (descriptors) |descriptor| if (std.mem.eql(u8, descriptor.id, "composition-part")) {
        if (descriptor.kind != .string or descriptor.required or !descriptor.workflow_definition_safe) return false;
        const result = for (descriptors) |candidate| {
            if (std.mem.eql(u8, candidate.id, "result-schema")) break candidate;
        } else return false;
        if (result.kind != .resource or result.resource_kind != .result_schema or result.required or !result.workflow_definition_safe) return false;
    };
    return true;
}

pub fn assignsRequest(produces: []const @import("pipeline.zig").DataKey, replaces: []const @import("pipeline.zig").DataKey) bool {
    return std.mem.indexOfScalar(@import("pipeline.zig").DataKey, produces, .assigned_model_request) != null and
        std.mem.indexOfScalar(@import("pipeline.zig").DataKey, replaces, .model_request_identity_ledger) != null;
}

/// A request has one result authority: a complete schema resource or a part of
/// the active compiled composition. Part bindings cannot override their inputs.
pub fn validResultSelection(values: []const compilation.CompiledParameter) bool {
    const result = find(values, "result-schema");
    const part = find(values, "composition-part");
    if ((result == null) == (part == null)) return false;
    if (result) |resource| return resource == .resource and @import("workflow.zig").WorkflowResourceId.parse(resource.resource.bytes) != null;
    return part.? == .string and @import("workflow.zig").WorkflowResourceId.parse(part.?.string) != null and
        find(values, "result-selection") == null and find(values, "input") == null;
}

pub fn resolve(
    values: []const compilation.CompiledParameter,
) ?Requirements {
    for (values, 0..) |value, index| {
        if (retiredParameter(value.id.bytes)) return null;
        for (values[0..index]) |prior| if (std.mem.eql(u8, prior.id.bytes, value.id.bytes)) return null;
    }
    const mode = find(values, "response-mode") orelse return null;
    if (mode != .enumeration) return null;
    const response_mode: controls.ResponseGuidanceMode = if (std.mem.eql(u8, mode.enumeration, "prompt-only"))
        .prompt_only
    else if (std.mem.eql(u8, mode.enumeration, "native-schema"))
        .native_schema
    else
        return null;
    return .{ .response_mode = response_mode };
}

pub fn consumesPreparedRequest(keys: []const @import("pipeline.zig").DataKey) bool {
    var request = false;
    var ledger = false;
    for (keys) |key| {
        request = request or key == .prepared_model_request;
        ledger = ledger or key == .model_request_identity_ledger;
    }
    return request and ledger;
}

pub fn validConsumerDescriptors(descriptors: []const operation.ParameterDescriptor) bool {
    for (descriptors) |descriptor| {
        if (descriptor.kind == .model_slot or descriptor.kind == .resource or requestOverride(descriptor.id)) return false;
    }
    return true;
}

fn requestOverride(id: []const u8) bool {
    if (retiredParameter(id)) return true;
    for (parameters) |parameter| if (std.mem.eql(u8, parameter.id, id)) return true;
    return false;
}

fn retiredParameter(id: []const u8) bool {
    inline for (.{ "temperature", "input-bytes", "output-bytes", "input-tokens", "output-tokens" }) |retired| {
        if (std.mem.eql(u8, id, retired)) return true;
    }
    return false;
}

fn find(values: []const compilation.CompiledParameter, id: []const u8) ?compilation.CompiledParameterValue {
    var found: ?compilation.CompiledParameterValue = null;
    for (values) |value| {
        if (!std.mem.eql(u8, value.id.bytes, id)) continue;
        if (found != null) return null;
        found = value.value;
    }
    return found;
}
