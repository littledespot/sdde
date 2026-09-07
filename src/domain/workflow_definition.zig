const telemetry = @import("telemetry.zig");
const workflow = @import("workflow.zig");

pub const schema_version = "workflow/v1";
pub const max_definitions: usize = 256;
pub const max_definition_bytes: usize = 1_048_576;
pub const max_resource_bytes: usize = 1_048_576;
pub const max_total_resource_bytes: usize = 16_777_216;
pub const max_steps: usize = 256;
pub const max_parameters: usize = 32;
pub const max_resources: usize = 64;
pub const max_subgraphs: usize = 32;
pub const max_yaml_events: usize = 262_144;
pub const max_yaml_tokens: usize = 262_144;
pub const max_yaml_nesting_depth: usize = 16;
pub const max_yaml_scalar_bytes: usize = 128;

pub const Definition = struct {
    source_ordinal: u16,
    workflow_id: workflow.WorkflowId,
    workflow_version: u32,
    shortcode: telemetry.WorkflowShortcode,
    invocation_operation_id: workflow.OperationId,
    policy_profile_id: workflow.RegisteredRef,
    start_step_id: workflow.WorkflowStepId,
    resources: []const workflow.ResourceDeclaration,
    steps: []const workflow.DeclarativeStep,
    calls: []const SubgraphCall = &.{},
    subgraphs: []const Subgraph = &.{},
};

pub const SubgraphId = struct {
    bytes: []const u8,
    pub fn parse(bytes: []const u8) ?SubgraphId {
        _ = workflow.WorkflowStepId.parse(bytes) orelse return null;
        return .{ .bytes = bytes };
    }
};
pub const SubgraphParameter = struct {
    id: workflow.WorkflowParameterId,
    value: union(enum) { literal: workflow.ParameterValue, parameter: workflow.WorkflowParameterId },
};
pub const SubgraphStep = struct {
    id: workflow.WorkflowStepId,
    operation_id: workflow.OperationId,
    parameters: []const SubgraphParameter,
    outcomes: []const workflow.OutcomeTransition,
};
pub const Subgraph = struct { id: SubgraphId, start: workflow.WorkflowStepId, steps: []const SubgraphStep };
pub const SubgraphCall = struct {
    id: workflow.WorkflowStepId,
    subgraph: SubgraphId,
    parameters: []const workflow.ParameterBinding,
    outcomes: []const workflow.OutcomeTransition,
};

pub const RawNode = union(enum) {
    null_value,
    boolean: bool,
    integer: i128,
    float: f64,
    scalar: []const u8,
    sequence: []const *RawNode,
    mapping: []const RawPair,
};
pub const RawPair = struct { key: *RawNode, value: *RawNode };
pub const RawDefinition = struct { ordinal: u16, root: *RawNode };
