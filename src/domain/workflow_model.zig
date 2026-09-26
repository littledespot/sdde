const std = @import("std");
const compilation = @import("workflow_compilation.zig");
const operation = @import("workflow_operation.zig");
const identity = @import("llm_provider_identity.zig");

// A projection of the originating parameters, not another selection authority.
pub const Requirements = struct {
    slot: identity.ModelSlotId,

    pub fn eql(self: Requirements, other: Requirements) bool {
        return self.slot.eql(other.slot);
    }
};

pub fn validProjection(step: compilation.CompiledStep) bool {
    var capability_count: usize = 0;
    for (step.capabilities) |capability| {
        if (std.mem.eql(u8, capability, "model-provider")) capability_count += 1;
    }
    const has_slot = for (step.parameters) |parameter| {
        if (parameter.value == .model_slot) break true;
    } else false;
    if (capability_count > 1 or
        (step.model != null) != has_slot or
        (capability_count == 1 and step.model == null and !consumesPreparedRequest(step.requires)) or
        (has_slot and consumesPreparedRequest(step.requires))) return false;
    if (consumesPreparedRequest(step.requires)) {
        for (step.parameters) |parameter| {
            if (parameter.value == .resource or parameter.value == .model_slot or retiredParameter(parameter.id.bytes)) return false;
        }
    }
    const model = step.model orelse return true;
    if (assignsRequest(step.produces, step.replaces) and !validResultSelection(step.parameters)) return false;
    const expected = resolve(step.parameters) orelse return false;
    return model.eql(expected);
}

pub fn validDescriptors(descriptors: []const operation.ParameterDescriptor) bool {
    for (descriptors) |descriptor| {
        if (retiredParameter(descriptor.id)) return false;
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
    var slot: ?identity.ModelSlotId = null;
    for (values, 0..) |value, index| {
        if (retiredParameter(value.id.bytes)) return null;
        for (values[0..index]) |prior| if (std.mem.eql(u8, prior.id.bytes, value.id.bytes)) return null;
        if (value.value == .model_slot) {
            if (slot != null) return null;
            slot = identity.ModelSlotId.parse(value.value.model_slot.bytes) orelse return null;
        }
    }
    return .{ .slot = slot orelse return null };
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
        if (descriptor.kind == .model_slot or descriptor.kind == .resource or retiredParameter(descriptor.id)) return false;
    }
    return true;
}

fn retiredParameter(id: []const u8) bool {
    inline for (.{ "response-mode", "temperature", "input-bytes", "output-bytes", "input-tokens", "output-tokens" }) |retired| {
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
