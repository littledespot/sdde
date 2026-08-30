const std = @import("std");
const pipeline = @import("pipeline.zig");
const telemetry = @import("telemetry.zig");

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

pub const WorkflowId = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) ?WorkflowId {
        return if (validLocalId(bytes)) .{ .bytes = bytes } else null;
    }
};

pub const WorkflowNodeId = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) ?WorkflowNodeId {
        return if (validLocalId(bytes)) .{ .bytes = bytes } else null;
    }
};

pub const WorkflowParameterId = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) ?WorkflowParameterId {
        return if (validLocalId(bytes)) .{ .bytes = bytes } else null;
    }
};

pub const RegisteredRef = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) ?RegisteredRef {
        if (bytes.len < 3 or bytes.len > 128) return null;
        const at = std.mem.lastIndexOfScalar(u8, bytes, '@') orelse return null;
        if (at == 0 or at + 1 == bytes.len or bytes[0] < 'a' or bytes[0] > 'z' or bytes[at + 1] == '0') return null;
        var separator = false;
        for (bytes[0..at], 0..) |byte, index| {
            const current_separator = byte == '.' or byte == '-';
            if (!(std.ascii.isLower(byte) or std.ascii.isDigit(byte) or current_separator) or
                (current_separator and (index == 0 or separator))) return null;
            separator = current_separator;
        }
        if (separator) return null;
        for (bytes[at + 1 ..]) |byte| if (!std.ascii.isDigit(byte)) return null;
        return .{ .bytes = bytes };
    }
};

fn validLocalId(bytes: []const u8) bool {
    if (bytes.len == 0 or bytes.len > 64 or bytes[0] < 'a' or bytes[0] > 'z') return false;
    var hyphen = false;
    for (bytes, 0..) |byte, index| {
        if (!(std.ascii.isLower(byte) or std.ascii.isDigit(byte) or byte == '-') or
            (byte == '-' and (index == 0 or hyphen))) return false;
        hyphen = byte == '-';
    }
    return !hyphen;
}

pub const OutcomeTag = enum { ok, needs_user, invalid, blocked, failed, cancelled };
pub const ParameterKind = enum { boolean, integer, @"enum", registered_id };
pub const ParameterValue = union(ParameterKind) {
    boolean: bool,
    integer: i64,
    @"enum": WorkflowNodeId,
    registered_id: RegisteredRef,
};
pub const ParameterBinding = struct { id: WorkflowParameterId, value: ParameterValue };
pub const DeclarativeNode = struct {
    id: WorkflowNodeId,
    contract_id: RegisteredRef,
    parameters: []const ParameterBinding,
};
pub const TransitionTarget = union(enum) { node: WorkflowNodeId, terminal: OutcomeTag };
pub const Transition = struct {
    from: WorkflowNodeId,
    outcome: OutcomeTag,
    target: TransitionTarget,
};
pub const Definition = struct {
    source_ordinal: u16,
    workflow_id: WorkflowId,
    workflow_version: u32,
    shortcode: telemetry.WorkflowShortcode,
    invocation_contract_id: RegisteredRef,
    policy_profile_id: RegisteredRef,
    entry_node_id: WorkflowNodeId,
    nodes: []const DeclarativeNode,
    transitions: []const Transition,
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

pub const ParameterDescriptor = struct {
    id: []const u8,
    kind: ParameterKind,
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
    outcomes: []const OutcomeTag,
    side_effect: pipeline.SideEffect,
    gates: []const []const u8 = &.{},
    capabilities: []const []const u8 = &.{},
};
pub const PolicyProfile = struct {
    id: []const u8,
    allowed_capabilities: []const []const u8,
    allowed_terminal_outcomes: []const OutcomeTag,
};
pub const CompilerRegistry = struct {
    invocations: []const InvocationContract,
    nodes: []const NodeContract,
    policies: []const PolicyProfile,
    gates: []const []const u8,
    capabilities: []const []const u8,
};

pub const CompiledNode = struct {
    id: WorkflowNodeId,
    contract_id: RegisteredRef,
    parameters: []const ParameterBinding,
    requires: []const pipeline.DataKey,
    produces: []const pipeline.DataKey,
    replaces: []const pipeline.DataKey,
    invalidates: []const pipeline.DataKey,
    outcomes: []const OutcomeTag,
    side_effect: pipeline.SideEffect,
    gates: []const []const u8,
    capabilities: []const []const u8,
};
pub const SemanticAuthority = struct {
    workflow_id: WorkflowId,
    workflow_version: u32,
    invocation_contract_id: RegisteredRef,
    policy_profile_id: RegisteredRef,
    entry_node_id: WorkflowNodeId,
    invocation_outputs: []const pipeline.DataKey,
    nodes: []const CompiledNode,
    transitions: []const Transition,
};
pub const CompiledWorkflow = struct {
    source_ordinal: u16,
    shortcode: telemetry.WorkflowShortcode,
    authority: SemanticAuthority,
};
pub const ValidatedGraphs = struct { values: []const CompiledWorkflow };

test "workflow and registered identifiers are exact" {
    try std.testing.expect(WorkflowId.parse("custom-flow") != null);
    try std.testing.expect(WorkflowId.parse("Custom") == null);
    try std.testing.expect(RegisteredRef.parse("core.noop@1") != null);
    try std.testing.expect(RegisteredRef.parse("core.noop@01") == null);
    try std.testing.expect(RegisteredRef.parse("core.noop@999999999999999999999999999999") != null);
}
