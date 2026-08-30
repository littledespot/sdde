const std = @import("std");
const pipeline = @import("pipeline.zig");
const telemetry = @import("telemetry.zig");
const workflow = @import("workflow.zig");

pub const ParameterDescriptor = struct {
    id: []const u8,
    kind: workflow.ParameterKind,
    required: bool,
    workflow_definition_safe: bool,
    integer_min: i64 = std.math.minInt(i64),
    integer_max: i64 = std.math.maxInt(i64),
    enum_members: []const []const u8 = &.{},
    registered_values: []const []const u8 = &.{},
};
pub const InvocationContract = struct {
    id: []const u8,
    capability_free: bool,
    produces: []const pipeline.DataKey,
};
pub const NodeContract = struct {
    id: []const u8,
    parameters: []const ParameterDescriptor,
    requires: []const pipeline.DataKey,
    produces: []const pipeline.DataKey,
    replaces: []const pipeline.DataKey = &.{},
    invalidates: []const pipeline.DataKey = &.{},
    outcomes: []const workflow.OutcomeTag,
    side_effect: pipeline.SideEffect,
    gates: []const []const u8 = &.{},
    capabilities: []const []const u8 = &.{},
};
pub const PolicyProfile = struct {
    id: []const u8,
    allowed_capabilities: []const []const u8,
    allowed_terminal_outcomes: []const workflow.OutcomeTag,
};
pub const CompilerRegistry = struct {
    invocations: []const InvocationContract,
    nodes: []const NodeContract,
    policies: []const PolicyProfile,
    gates: []const []const u8,
    capabilities: []const []const u8,
};

pub const CompiledNode = struct {
    id: workflow.WorkflowNodeId,
    contract_id: workflow.RegisteredRef,
    parameters: []const workflow.ParameterBinding,
    requires: []const pipeline.DataKey,
    produces: []const pipeline.DataKey,
    replaces: []const pipeline.DataKey,
    invalidates: []const pipeline.DataKey,
    outcomes: []const workflow.OutcomeTag,
    side_effect: pipeline.SideEffect,
    gates: []const []const u8,
    capabilities: []const []const u8,
};
pub const SemanticAuthority = struct {
    workflow_id: workflow.WorkflowId,
    workflow_version: u32,
    invocation_contract_id: workflow.RegisteredRef,
    policy_profile_id: workflow.RegisteredRef,
    entry_node_id: workflow.WorkflowNodeId,
    invocation_outputs: []const pipeline.DataKey,
    nodes: []const CompiledNode,
    transitions: []const workflow.Transition,
};
pub const CompiledWorkflow = struct {
    source_ordinal: u16,
    shortcode: telemetry.WorkflowShortcode,
    authority: SemanticAuthority,
};
pub const ValidatedGraphs = struct { values: []const CompiledWorkflow };
