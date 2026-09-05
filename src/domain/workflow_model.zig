const std = @import("std");
const controls = @import("model_controls.zig");
const compilation = @import("workflow_compilation.zig");
const operation = @import("workflow_operation.zig");

pub const Requirements = struct {
    response_mode: controls.ResponseGuidanceMode,
    controls: controls.InferenceControls,
};

// Shared generic model parameters. No workflow name, route, or model identity
// participates in this contract. Omitted controls mean no control is sent.
pub const parameters = [_]operation.ParameterDescriptor{
    .{ .id = "response-mode", .kind = .enumeration, .required = true, .workflow_definition_safe = true, .allowed_values = &.{ "prompt-only", "native-schema" } },
    .{ .id = "temperature", .kind = .integer, .required = false, .workflow_definition_safe = true, .integer_min = 0, .integer_max = 1000 },
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
    const expected = resolve(step.parameters) orelse return false;
    return std.meta.eql(model, expected);
}

pub fn validDescriptors(descriptors: []const operation.ParameterDescriptor) bool {
    for (descriptors) |descriptor| {
        if (retiredSizeParameter(descriptor.id)) return false;
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
    return true;
}

pub fn resolve(
    values: []const compilation.CompiledParameter,
) ?Requirements {
    for (values, 0..) |value, index| {
        if (retiredSizeParameter(value.id.bytes)) return null;
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
    var selected: controls.InferenceControls = .{};
    if (find(values, "temperature")) |temperature| {
        if (temperature != .integer or temperature.integer < 0 or temperature.integer > 1000) return null;
        selected.temperature = controls.TemperaturePermille.init(@intCast(temperature.integer)) orelse return null;
    }
    return .{ .response_mode = response_mode, .controls = selected };
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
    if (retiredSizeParameter(id)) return true;
    for (parameters) |parameter| if (std.mem.eql(u8, parameter.id, id)) return true;
    return false;
}

fn retiredSizeParameter(id: []const u8) bool {
    inline for (.{ "input-bytes", "output-bytes", "input-tokens", "output-tokens" }) |retired| {
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
