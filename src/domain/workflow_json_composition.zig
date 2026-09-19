//! Composition facts used by the existing compiled-graph data-flow validator.
//! This owner has no request execution, validation, retry or accounting capability.
const std = @import("std");
const pipeline = @import("pipeline.zig");
const workflow = @import("workflow.zig");
const compilation = @import("workflow_compilation.zig");
const composition = @import("json_composition.zig");
const request_lifecycle = @import("workflow_model_request_lifecycle.zig");
const model = @import("workflow_model.zig");

pub const Error = error{InvalidWorkflowComposition};
pub const State = struct {
    plan: ?*const composition.Plan = null,
    completed: std.StaticBitSet(@import("model_result_schema.zig").max_properties) = .initEmpty(),
    request_part: ?usize = null,
    request_completed: bool = false,

    pub fn eql(left: State, right: State) bool {
        return left.plan == right.plan and left.request_part == right.request_part and
            left.request_completed == right.request_completed and left.completed.eql(right.completed);
    }
};

pub fn apply(input: State, step: compilation.CompiledStep, resources: []const compilation.CompiledResource, outcome: workflow.OutcomeTag) Error!State {
    var state = input;
    if (contains(step.produces, .json_composition)) {
        if (state.plan != null) return invalid();
        const selected = parameter(step.parameters, "composition") orelse return invalid();
        if (selected != .resource) return invalid();
        const plan = for (resources) |resource| {
            if (std.mem.eql(u8, resource.id.bytes, selected.resource.bytes)) {
                if (resource.content != .json_composition) return invalid();
                break resource.content.json_composition;
            }
        } else return invalid();
        state = .{ .plan = plan };
    }
    const starts_request = model.assignsRequest(step.produces, step.replaces);
    if (starts_request) {
        const selected = parameter(step.parameters, "composition-part");
        if (selected) |part| {
            const plan = state.plan orelse return invalid();
            if (!model.validResultSelection(step.parameters) or state.request_part != null) return invalid();
            const index = plan.part(.{ .bytes = part.string }) orelse return invalid();
            if (state.completed.isSet(index)) return invalid();
            for (plan.parts()[index].requires) |required| if (!state.completed.isSet(required)) return invalid();
            state.request_part = index;
            state.request_completed = false;
        } else if (state.plan != null) return invalid();
    } else if (parameter(step.parameters, "composition-part") != null) return invalid();

    if (state.request_part != null and request_lifecycle.advances(step.replaces, step.produces) and request_lifecycle.completes(step.requires)) {
        state.request_completed = outcome == .ok and !request_lifecycle.terminates(step.requires) and !request_lifecycle.closesCount(step.requires);
    }
    if (contains(step.replaces, .json_composition)) {
        if (state.plan == null or state.request_part == null or !state.request_completed or
            !contains(step.requires, .prepared_model_request) or !contains(step.requires, .model_payload_schema_result)) return invalid();
        // Repeating the same successful placement is idempotent. Starting a new
        // request for that part above rejects instead of replacing its producer.
        state.completed.set(state.request_part.?);
    }
    if (contains(step.invalidates, .json_composition)) {
        const plan = state.plan orelse return invalid();
        if (!contains(step.produces, .assembled_json)) return invalid();
        for (plan.parts(), 0..) |_, index| if (!state.completed.isSet(index)) return invalid();
        state = .{};
    }
    if (contains(step.invalidates, .assigned_model_request) or contains(step.invalidates, .prepared_model_request)) {
        state.request_part = null;
        state.request_completed = false;
    }
    return state;
}

fn parameter(parameters: []const compilation.CompiledParameter, name: []const u8) ?compilation.CompiledParameterValue {
    for (parameters) |entry| if (std.mem.eql(u8, entry.id.bytes, name)) return entry.value;
    return null;
}

fn contains(keys: []const pipeline.DataKey, key: pipeline.DataKey) bool {
    return std.mem.indexOfScalar(pipeline.DataKey, keys, key) != null;
}

fn invalid() Error {
    return error.InvalidWorkflowComposition;
}
