const telemetry = @import("telemetry.zig");
const workflow = @import("workflow.zig");

pub const schema_version = "1.0";
pub const max_definitions: usize = 256;
pub const max_definition_bytes: usize = 1_048_576;
pub const max_nodes: usize = 256;
pub const max_parameters: usize = 32;
pub const max_transitions: usize = 1536;
pub const max_yaml_events: usize = 262_144;
pub const max_yaml_tokens: usize = 262_144;
pub const max_yaml_nesting_depth: usize = 16;
pub const max_yaml_scalar_bytes: usize = 128;

pub const Definition = struct {
    source_ordinal: u16,
    workflow_id: workflow.WorkflowId,
    workflow_version: u32,
    shortcode: telemetry.WorkflowShortcode,
    invocation_contract_id: workflow.RegisteredRef,
    policy_profile_id: workflow.RegisteredRef,
    entry_node_id: workflow.WorkflowNodeId,
    nodes: []const workflow.DeclarativeNode,
    transitions: []const workflow.Transition,
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
