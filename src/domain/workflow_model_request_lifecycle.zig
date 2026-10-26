const std = @import("std");
const operation = @import("workflow_operation.zig");
const compilation = @import("workflow_compilation.zig");
const pipeline = @import("pipeline.zig");
const workflow = @import("workflow.zig");
const identity = @import("model_request_identity.zig");

pub const requires = @import("workflow_provider_authorization.zig").requires ++ [_]pipeline.DataKey{.provider_authorization_result};
const closure_requires = [_]pipeline.DataKey{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation };
pub const advisory_protocol_requires = [_]pipeline.DataKey{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt };
pub const advisory_protocol_outcomes = [_]workflow.OutcomeTag{.blocked};
pub const completion_requires = closure_requires ++ [_]pipeline.DataKey{.model_payload_schema_result};
pub const termination_requires = closure_requires ++ [_]pipeline.DataKey{.provider_authorization_result};
pub const completion_outcomes = [_]workflow.OutcomeTag{ .ok, .invalid, .failed, .cancelled };
pub const termination_outcomes = [_]workflow.OutcomeTag{ .failed, .cancelled };
pub const Closure = struct {
    expected_status: identity.RequestStatus,
    reason: identity.TerminalReason,
    outcome: workflow.OutcomeTag,
};
pub const parameter: operation.ParameterDescriptor = .{
    .id = "transition",
    .kind = .enumeration,
    .required = true,
    .workflow_definition_safe = true,
    .allowed_values = &.{"invoked"},
};

// The data contract distinguishes lifecycle replacement from new assignment;
// no operation ID or workflow name activates runner behavior.
pub fn advances(replaces: []const pipeline.DataKey, produces: []const pipeline.DataKey) bool {
    return contains(replaces, .model_request_identity_ledger) and !contains(produces, .assigned_model_request);
}

pub fn completes(inputs: []const pipeline.DataKey) bool {
    return contains(inputs, .terminal_provider_operation) or closesAdvisoryProtocol(inputs);
}

pub fn closesAdvisoryProtocol(inputs: []const pipeline.DataKey) bool {
    return std.mem.eql(pipeline.DataKey, inputs, &advisory_protocol_requires);
}

pub fn terminates(inputs: []const pipeline.DataKey) bool {
    return completes(inputs) and contains(inputs, .provider_authorization_result);
}

pub fn validContract(contract: operation.Contract, capabilities: []const []const u8) bool {
    if (!advances(contract.replaces, contract.produces)) return true;
    if (!validEffects(contract.requires, contract.produces, contract.replaces, contract.optional, contract.invalidates) or
        contract.side_effect != .none or contract.runner_accounting != .none or contract.retry_limit != null or
        capabilities.len != 0) return false;
    if (completes(contract.requires)) return contract.parameters.len == 0 and
        std.mem.eql(workflow.OutcomeTag, contract.outcomes, if (closesAdvisoryProtocol(contract.requires)) &advisory_protocol_outcomes else if (contract.outcome_association == .advisory_request_closure) &.{.more} else if (terminates(contract.requires)) &termination_outcomes else &completion_outcomes);
    if (contract.parameters.len != 1) return false;
    const value = contract.parameters[0];
    return std.mem.eql(u8, value.id, parameter.id) and value.kind == .enumeration and value.required and value.workflow_definition_safe and
        value.allowed_values.len == 1 and std.mem.eql(u8, value.allowed_values[0], "invoked");
}

pub fn validProjection(step: compilation.CompiledStep) bool {
    if (!advances(step.replaces, step.produces)) return true;
    return validEffects(step.requires, step.produces, step.replaces, step.optional, step.invalidates) and
        step.side_effect == .none and step.runner_accounting == .none and step.retry_authority == null and
        step.capabilities.len == 0 and (if (completes(step.requires)) step.parameters.len == 0 and
        std.mem.eql(workflow.OutcomeTag, step.outcomes, if (closesAdvisoryProtocol(step.requires)) &advisory_protocol_outcomes else if (step.outcome_association == .advisory_request_closure) &.{.more} else if (terminates(step.requires)) &termination_outcomes else &completion_outcomes) else transition(step.parameters) != null);
}

pub fn transition(parameters: []const compilation.CompiledParameter) ?@import("model_request_identity.zig").LifecycleTransition {
    if (parameters.len != 1) return null;
    const value = parameters[0];
    if (!std.mem.eql(u8, value.id.bytes, parameter.id) or value.value != .enumeration or !std.mem.eql(u8, value.value.enumeration, "invoked")) return null;
    return .invoked;
}

fn validEffects(inputs: []const pipeline.DataKey, produces: []const pipeline.DataKey, replaces: []const pipeline.DataKey, optional: []const pipeline.DataKey, invalidates: []const pipeline.DataKey) bool {
    const required: []const pipeline.DataKey = if (closesAdvisoryProtocol(inputs)) &advisory_protocol_requires else if (terminates(inputs)) &termination_requires else if (completes(inputs)) &completion_requires else &requires;
    if (completes(inputs) and inputs.len != required.len) return false;
    for (required) |key| if (!contains(inputs, key)) return false;
    return produces.len == 0 and optional.len == 0 and invalidates.len == 0 and
        std.mem.eql(pipeline.DataKey, replaces, &.{.model_request_identity_ledger});
}

fn contains(keys: []const pipeline.DataKey, key: pipeline.DataKey) bool {
    return std.mem.indexOfScalar(pipeline.DataKey, keys, key) != null;
}

/// ADR 0039: a response admission whose `invalid` continues to another step
/// (correction or closure) routes it through a runaway router whose `more`
/// reaches the re-send, and a re-send is reached only from such a router, so
/// no workflow can skip or forge a runaway's one re-send. An admission that
/// ends the execution on `invalid` closes nothing and continues nothing.
pub fn validateRunawayRoutes(authority: compilation.SemanticAuthority) error{WorkflowGraphCompileInvalid}!void {
    for (authority.steps) |step| {
        if (step.outcome_association != .request_admission or std.mem.indexOfScalar(workflow.OutcomeTag, step.outcomes, .invalid) == null) continue;
        const router = switch (route(authority, step.id.bytes, .invalid) orelse return error.WorkflowGraphCompileInvalid) {
            .step => |id| find(authority.steps, id.bytes) orelse return error.WorkflowGraphCompileInvalid,
            .terminal => continue,
        };
        const resend = target(authority, router.id.bytes, .more) orelse return error.WorkflowGraphCompileInvalid;
        if (resend.outcome_association != .request_resend) return error.WorkflowGraphCompileInvalid;
    }
    for (authority.transitions) |edge| {
        const id = switch (edge.target) {
            .step => |value| value.bytes,
            .terminal => continue,
        };
        const reached = find(authority.steps, id) orelse return error.WorkflowGraphCompileInvalid;
        if (reached.outcome_association != .request_resend) continue;
        if (edge.outcome != .more or !admissionTarget(authority, edge.from.bytes)) return error.WorkflowGraphCompileInvalid;
    }
}

fn admissionTarget(authority: compilation.SemanticAuthority, id: []const u8) bool {
    for (authority.transitions) |edge| {
        if (edge.outcome != .invalid or edge.target != .step or !std.mem.eql(u8, edge.target.step.bytes, id)) continue;
        const source = find(authority.steps, edge.from.bytes) orelse return false;
        if (source.outcome_association == .request_admission) return true;
    }
    return false;
}

fn route(authority: compilation.SemanticAuthority, from: []const u8, outcome: workflow.OutcomeTag) ?workflow.TransitionTarget {
    for (authority.transitions) |edge| if (edge.outcome == outcome and std.mem.eql(u8, edge.from.bytes, from)) return edge.target;
    return null;
}

fn target(authority: compilation.SemanticAuthority, from: []const u8, outcome: workflow.OutcomeTag) ?compilation.CompiledStep {
    return switch (route(authority, from, outcome) orelse return null) {
        .step => |id| find(authority.steps, id.bytes),
        .terminal => null,
    };
}

fn find(steps: []const compilation.CompiledStep, id: []const u8) ?compilation.CompiledStep {
    for (steps) |step| if (std.mem.eql(u8, step.id.bytes, id)) return step;
    return null;
}
