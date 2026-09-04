const std = @import("std");
const pipeline = @import("pipeline.zig");
const telemetry = @import("telemetry.zig");
const workflow = @import("workflow.zig");
const operation = @import("workflow_operation.zig");
const provider_identity = @import("llm_provider_identity.zig");
const workflow_retry = @import("workflow_retry.zig");
const workflow_token_budget = @import("workflow_token_budget.zig");

pub const CompiledParameterValue = union(enum) {
    boolean: bool,
    integer: i64,
    string: []const u8,
    enumeration: []const u8,
    registered_ref: workflow.RegisteredRef,
    resource: workflow.WorkflowResourceId,
    model_slot: provider_identity.ModelSlotId,
};

pub const CompiledParameter = struct {
    id: workflow.WorkflowParameterId,
    value: CompiledParameterValue,
};

pub const CompiledResource = struct {
    id: workflow.WorkflowResourceId,
    kind: operation.ResourceKind,
    bytes: []const u8,
};

pub const CompiledStep = struct {
    id: workflow.WorkflowStepId,
    operation_id: workflow.RegisteredRef,
    parameters: []const CompiledParameter,
    requires: []const pipeline.DataKey,
    optional: []const pipeline.DataKey = &.{},
    produces: []const pipeline.DataKey,
    replaces: []const pipeline.DataKey,
    invalidates: []const pipeline.DataKey,
    outcomes: []const workflow.OutcomeTag,
    side_effect: pipeline.SideEffect,
    gates: []const []const u8,
    capabilities: []const []const u8,
    retry_authority: ?workflow_retry.CompiledAuthority,
};

pub const SemanticAuthority = struct {
    data_schemas: []const @import("pipeline_data.zig").Schema = &.{},
    workflow_id: workflow.WorkflowId,
    workflow_version: u32,
    invocation_operation_id: workflow.RegisteredRef,
    policy_profile_id: workflow.RegisteredRef,
    total_model_token_budget: workflow_token_budget.TotalTokenBudget,
    start_step_id: workflow.WorkflowStepId,
    invocation_outputs: []const pipeline.DataKey,
    resources: []const CompiledResource,
    steps: []const CompiledStep,
    transitions: []const workflow.Transition,
    maximum_step_executions: usize,
};

pub const CompiledWorkflow = struct {
    source_ordinal: u16,
    shortcode: telemetry.WorkflowShortcode,
    authority: SemanticAuthority,
};

pub const ValidatedGraphs = struct { values: []const CompiledWorkflow };

pub fn calculateExecutionLimit(steps: []const CompiledStep) ?usize {
    if (steps.len == 0) return null;
    var total_retry_limit: usize = 0;
    for (steps) |step| {
        if (step.retry_authority) |authority| {
            total_retry_limit = std.math.add(usize, total_retry_limit, authority.limit.value) catch return null;
        }
    }
    const rounds = std.math.add(usize, total_retry_limit, 1) catch return null;
    return std.math.mul(usize, steps.len, rounds) catch return null;
}
