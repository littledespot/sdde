const std = @import("std");
const pipeline = @import("pipeline.zig");
const telemetry = @import("telemetry.zig");
const workflow = @import("workflow.zig");
const operation = @import("workflow_operation.zig");

pub const CompiledParameterValue = union(enum) {
    boolean: bool,
    integer: i64,
    string: []const u8,
    enumeration: []const u8,
    registered_ref: workflow.RegisteredRef,
    resource: workflow.WorkflowResourceId,
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
    produces: []const pipeline.DataKey,
    replaces: []const pipeline.DataKey,
    invalidates: []const pipeline.DataKey,
    outcomes: []const workflow.OutcomeTag,
    side_effect: pipeline.SideEffect,
    gates: []const []const u8,
    capabilities: []const []const u8,
    loop_limit: ?u32,
};

pub const SemanticAuthority = struct {
    workflow_id: workflow.WorkflowId,
    workflow_version: u32,
    invocation_operation_id: workflow.RegisteredRef,
    policy_profile_id: workflow.RegisteredRef,
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
    var total_loop_limit: usize = 0;
    for (steps) |step| {
        if (step.loop_limit) |limit| {
            total_loop_limit = std.math.add(usize, total_loop_limit, limit) catch return null;
        }
    }
    const rounds = std.math.add(usize, total_loop_limit, 1) catch return null;
    return std.math.mul(usize, steps.len, rounds) catch return null;
}
