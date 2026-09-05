const std = @import("std");
const limits = @import("model_limits.zig");
const controls = @import("model_controls.zig");
const compilation = @import("workflow_compilation.zig");
const operation = @import("workflow_operation.zig");

pub const Requirements = struct {
    capacity: limits.Capacity,
    response_mode: controls.ResponseGuidanceMode,
    controls: controls.InferenceControls,
};

// Shared generic model parameters. No workflow name, route, or model identity
// participates in this contract. Omitted controls mean no control is sent.
pub const parameters = [_]operation.ParameterDescriptor{
    .{ .id = "input-bytes", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 1, .integer_max = std.math.maxInt(u32) },
    .{ .id = "output-bytes", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 1, .integer_max = std.math.maxInt(u32) },
    .{ .id = "input-tokens", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 1 },
    .{ .id = "output-tokens", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 1 },
    .{ .id = "response-mode", .kind = .enumeration, .required = true, .workflow_definition_safe = true, .allowed_values = &.{ "prompt-only", "native-schema" } },
    .{ .id = "temperature", .kind = .integer, .required = false, .workflow_definition_safe = true, .integer_min = 0, .integer_max = 1000 },
};

pub fn validProjection(step: compilation.CompiledStep) bool {
    var capability_count: usize = 0;
    for (step.capabilities) |capability| {
        if (std.mem.eql(u8, capability, "model-provider")) capability_count += 1;
    }
    if (capability_count > 1 or (capability_count == 1) != (step.model != null)) return false;
    const model = step.model orelse return true;
    const expected = resolve(model.capacity, model.capacity, step.parameters) orelse return false;
    return std.meta.eql(model, expected);
}

pub fn validDescriptors(descriptors: []const operation.ParameterDescriptor) bool {
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
    engine_capacity: limits.Capacity,
    operation_capacity: limits.Capacity,
    values: []const compilation.CompiledParameter,
) ?Requirements {
    for (values, 0..) |value, index| {
        for (values[0..index]) |prior| if (std.mem.eql(u8, prior.id.bytes, value.id.bytes)) return null;
    }
    var capacity = limits.Capacity.intersect(engine_capacity, operation_capacity) orelse return null;
    capacity.canonical.maximum_input_bytes = @intCast(@min(capacity.canonical.maximum_input_bytes, integer(values, "input-bytes", std.math.maxInt(u32)) orelse return null));
    capacity.canonical.maximum_output_bytes = @intCast(@min(capacity.canonical.maximum_output_bytes, integer(values, "output-bytes", std.math.maxInt(u32)) orelse return null));
    capacity.canonical.maximum_input_tokens = @min(capacity.canonical.maximum_input_tokens, integer(values, "input-tokens", std.math.maxInt(i64)) orelse return null);
    capacity.canonical.maximum_output_tokens = @min(capacity.canonical.maximum_output_tokens, integer(values, "output-tokens", std.math.maxInt(i64)) orelse return null);
    if (!capacity.isValid()) return null;
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
    return .{ .capacity = capacity, .response_mode = response_mode, .controls = selected };
}

fn integer(values: []const compilation.CompiledParameter, id: []const u8, maximum: u64) ?u64 {
    const value = find(values, id) orelse return null;
    if (value != .integer or value.integer <= 0 or value.integer > maximum) return null;
    return @intCast(value.integer);
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
