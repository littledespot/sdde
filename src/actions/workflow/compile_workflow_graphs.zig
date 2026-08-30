const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const workflow = @import("../../domain/workflow_registry.zig");

pub const Error = error{WorkflowGraphCompileInvalid};

pub const Action = struct {
    registry: *const workflow.CompilerRegistry,

    pub const contract: pipeline.NodeContract = .{
        .id = "compile-workflow-graphs@1",
        .kind = .action,
        .requires = &.{.declarative_workflow_definitions},
        .produces = &.{.compiled_workflow_graphs},
        .side_effect = .none,
    };

    pub fn execute(
        self: Action,
        allocator: std.mem.Allocator,
        definitions: []const workflow.Definition,
    ) Error![]const workflow.CompiledWorkflow {
        const graphs = allocator.alloc(workflow.CompiledWorkflow, definitions.len) catch return invalid();
        for (definitions, graphs) |definition, *graph| {
            const invocation = uniqueInvocation(self.registry.invocations, definition.invocation_contract_id.bytes) orelse return invalid();
            if (!invocation.capability_free) return invalid();
            const policy = uniquePolicy(self.registry.policies, definition.policy_profile_id.bytes) orelse return invalid();
            if (!hasNode(definition.nodes, definition.entry_node_id.bytes)) return invalid();

            const nodes = allocator.alloc(workflow.CompiledNode, definition.nodes.len) catch return invalid();
            for (definition.nodes, nodes) |source, *node| {
                const node_contract = uniqueNode(self.registry.nodes, source.contract_id.bytes) orelse return invalid();
                try validateParameters(node_contract, source.parameters);
                for (node_contract.gates) |gate| if (!uniqueString(self.registry.gates, gate)) return invalid();
                for (node_contract.capabilities) |capability| {
                    if (!uniqueString(self.registry.capabilities, capability) or
                        !containsString(policy.allowed_capabilities, capability)) return invalid();
                }
                node.* = .{
                    .id = source.id,
                    .contract_id = source.contract_id,
                    .parameters = source.parameters,
                    .requires = node_contract.requires,
                    .produces = node_contract.produces,
                    .replaces = node_contract.replaces,
                    .invalidates = node_contract.invalidates,
                    .outcomes = node_contract.outcomes,
                    .side_effect = node_contract.side_effect,
                    .gates = node_contract.gates,
                    .capabilities = node_contract.capabilities,
                };
            }
            try validateTransitions(definition, nodes, policy);
            graph.* = .{
                .source_ordinal = definition.source_ordinal,
                .shortcode = definition.shortcode,
                .authority = .{
                    .workflow_id = definition.workflow_id,
                    .workflow_version = definition.workflow_version,
                    .invocation_contract_id = definition.invocation_contract_id,
                    .policy_profile_id = definition.policy_profile_id,
                    .entry_node_id = definition.entry_node_id,
                    .invocation_outputs = invocation.produces,
                    .nodes = nodes,
                    .transitions = definition.transitions,
                },
            };
        }
        return graphs;
    }
};

fn validateParameters(contract: workflow.NodeContract, parameters: []const workflow.ParameterBinding) Error!void {
    if (parameters.len > contract.parameters.len) return invalid();
    for (contract.parameters, 0..) |descriptor, index| {
        if (workflow.WorkflowParameterId.parse(descriptor.id) == null or !descriptor.workflow_definition_safe) {
            return invalid();
        }
        for (contract.parameters[0..index]) |previous| {
            if (std.mem.eql(u8, previous.id, descriptor.id)) return invalid();
        }
        const binding = findParameter(parameters, descriptor.id);
        if (descriptor.required and binding == null) return invalid();
        if (binding) |value| {
            if (std.meta.activeTag(value.value) != descriptor.kind) return invalid();
            switch (value.value) {
                .boolean => {},
                .integer => |integer| if (integer < descriptor.integer_min or integer > descriptor.integer_max) return invalid(),
                .@"enum" => |member| if (!containsString(descriptor.enum_members, member.bytes)) return invalid(),
                .registered_id => |registered| if (!containsString(descriptor.registered_values, registered.bytes)) return invalid(),
            }
        }
    }
    for (parameters) |parameter| {
        if (findDescriptor(contract.parameters, parameter.id.bytes) == null) return invalid();
    }
}

fn validateTransitions(
    definition: workflow.Definition,
    nodes: []const workflow.CompiledNode,
    policy: workflow.PolicyProfile,
) Error!void {
    for (definition.transitions, 0..) |transition, index| {
        const source = findCompiledNode(nodes, transition.from.bytes) orelse return invalid();
        if (!containsOutcome(source.outcomes, transition.outcome)) return invalid();
        for (definition.transitions[0..index]) |previous| {
            if (std.mem.eql(u8, previous.from.bytes, transition.from.bytes) and previous.outcome == transition.outcome) {
                return invalid();
            }
        }
        switch (transition.target) {
            .node => |target| if (findCompiledNode(nodes, target.bytes) == null) return invalid(),
            .terminal => |terminal| {
                if (terminal != transition.outcome or !containsOutcome(policy.allowed_terminal_outcomes, terminal)) {
                    return invalid();
                }
            },
        }
    }
    for (nodes) |node| {
        for (node.outcomes) |outcome| {
            if (findTransition(definition.transitions, node.id.bytes, outcome) == null) return invalid();
        }
        for (definition.transitions) |transition| {
            if (std.mem.eql(u8, transition.from.bytes, node.id.bytes) and
                !containsOutcome(node.outcomes, transition.outcome)) return invalid();
        }
    }
}

fn uniqueInvocation(values: []const workflow.InvocationContract, id: []const u8) ?workflow.InvocationContract {
    var result: ?workflow.InvocationContract = null;
    for (values) |value| if (std.mem.eql(u8, value.id, id)) {
        if (result != null or workflow.RegisteredRef.parse(value.id) == null) return null;
        result = value;
    };
    return result;
}
fn uniqueNode(values: []const workflow.NodeContract, id: []const u8) ?workflow.NodeContract {
    var result: ?workflow.NodeContract = null;
    for (values) |value| if (std.mem.eql(u8, value.id, id)) {
        if (result != null or workflow.RegisteredRef.parse(value.id) == null) return null;
        result = value;
    };
    return result;
}
fn uniquePolicy(values: []const workflow.PolicyProfile, id: []const u8) ?workflow.PolicyProfile {
    var result: ?workflow.PolicyProfile = null;
    for (values) |value| if (std.mem.eql(u8, value.id, id)) {
        if (result != null or workflow.RegisteredRef.parse(value.id) == null) return null;
        result = value;
    };
    return result;
}
fn uniqueString(values: []const []const u8, expected: []const u8) bool {
    var count: usize = 0;
    for (values) |value| {
        if (std.mem.eql(u8, value, expected)) count += 1;
    }
    return count == 1;
}
fn containsString(values: []const []const u8, expected: []const u8) bool {
    for (values) |value| if (std.mem.eql(u8, value, expected)) return true;
    return false;
}
fn containsOutcome(values: []const workflow.OutcomeTag, expected: workflow.OutcomeTag) bool {
    for (values) |value| if (value == expected) return true;
    return false;
}
fn hasNode(values: []const workflow.DeclarativeNode, expected: []const u8) bool {
    for (values) |value| if (std.mem.eql(u8, value.id.bytes, expected)) return true;
    return false;
}
fn findCompiledNode(values: []const workflow.CompiledNode, expected: []const u8) ?workflow.CompiledNode {
    for (values) |value| if (std.mem.eql(u8, value.id.bytes, expected)) return value;
    return null;
}
fn findParameter(values: []const workflow.ParameterBinding, expected: []const u8) ?workflow.ParameterBinding {
    for (values) |value| if (std.mem.eql(u8, value.id.bytes, expected)) return value;
    return null;
}
fn findDescriptor(values: []const workflow.ParameterDescriptor, expected: []const u8) ?workflow.ParameterDescriptor {
    for (values) |value| if (std.mem.eql(u8, value.id, expected)) return value;
    return null;
}
fn findTransition(values: []const workflow.Transition, from: []const u8, outcome: workflow.OutcomeTag) ?workflow.Transition {
    for (values) |value| if (value.outcome == outcome and std.mem.eql(u8, value.from.bytes, from)) return value;
    return null;
}
fn invalid() Error {
    return error.WorkflowGraphCompileInvalid;
}

const test_registry: workflow.CompilerRegistry = .{
    .invocations = &.{.{ .id = "core.empty@1", .capability_free = true, .produces = &.{} }},
    .nodes = &.{.{
        .id = "core.noop@1",
        .parameters = &.{},
        .requires = &.{},
        .produces = &.{},
        .outcomes = &.{.ok},
        .side_effect = .none,
    }},
    .policies = &.{.{
        .id = "core.safe@1",
        .allowed_capabilities = &.{},
        .allowed_terminal_outcomes = &.{.ok},
    }},
    .gates = &.{},
    .capabilities = &.{},
};

const test_valid_nodes = [_]workflow.DeclarativeNode{.{
    .id = workflow.WorkflowNodeId.parse("run").?,
    .contract_id = workflow.RegisteredRef.parse("core.noop@1").?,
    .parameters = &.{},
}};
const test_missing_nodes = [_]workflow.DeclarativeNode{.{
    .id = workflow.WorkflowNodeId.parse("run").?,
    .contract_id = workflow.RegisteredRef.parse("core.missing@1").?,
    .parameters = &.{},
}};

fn testDefinition(contract_id: []const u8, transitions: []const workflow.Transition) workflow.Definition {
    return .{
        .source_ordinal = 1,
        .workflow_id = workflow.WorkflowId.parse("arbitrary-flow").?,
        .workflow_version = 1,
        .shortcode = telemetryForTest(),
        .invocation_contract_id = workflow.RegisteredRef.parse("core.empty@1").?,
        .policy_profile_id = workflow.RegisteredRef.parse("core.safe@1").?,
        .entry_node_id = workflow.WorkflowNodeId.parse("run").?,
        .nodes = if (std.mem.eql(u8, contract_id, "core.noop@1")) &test_valid_nodes else &test_missing_nodes,
        .transitions = transitions,
    };
}

fn telemetryForTest() @import("../../domain/telemetry.zig").WorkflowShortcode {
    return @import("../../domain/telemetry.zig").WorkflowShortcode.parse("ARBT") catch unreachable;
}

test "compiler accepts an arbitrary registered workflow and rejects unknown nodes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const transitions = [_]workflow.Transition{.{
        .from = workflow.WorkflowNodeId.parse("run").?,
        .outcome = .ok,
        .target = .{ .terminal = .ok },
    }};
    const valid = [_]workflow.Definition{testDefinition("core.noop@1", &transitions)};
    const graphs = try (Action{ .registry = &test_registry }).execute(arena.allocator(), &valid);
    try std.testing.expectEqualStrings("arbitrary-flow", graphs[0].authority.workflow_id.bytes);

    const unknown = [_]workflow.Definition{testDefinition("core.missing@1", &transitions)};
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        (Action{ .registry = &test_registry }).execute(arena.allocator(), &unknown),
    );
}

test "compiler rejects an incomplete transition table and capability escalation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const incomplete = [_]workflow.Definition{testDefinition("core.noop@1", &.{})};
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        (Action{ .registry = &test_registry }).execute(arena.allocator(), &incomplete),
    );

    const capable_nodes = [_]workflow.NodeContract{.{
        .id = "core.noop@1",
        .parameters = &.{},
        .requires = &.{},
        .produces = &.{},
        .outcomes = &.{.ok},
        .side_effect = .none,
        .capabilities = &.{"project-write"},
    }};
    const capabilities = [_][]const u8{"project-write"};
    var registry = test_registry;
    registry.nodes = &capable_nodes;
    registry.capabilities = &capabilities;
    const transitions = [_]workflow.Transition{.{
        .from = workflow.WorkflowNodeId.parse("run").?,
        .outcome = .ok,
        .target = .{ .terminal = .ok },
    }};
    const definition = [_]workflow.Definition{testDefinition("core.noop@1", &transitions)};
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        (Action{ .registry = &registry }).execute(arena.allocator(), &definition),
    );
}

test "adding an unrelated definition does not change compiled semantic authority" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const transitions = [_]workflow.Transition{.{
        .from = workflow.WorkflowNodeId.parse("run").?,
        .outcome = .ok,
        .target = .{ .terminal = .ok },
    }};
    const first = testDefinition("core.noop@1", &transitions);
    const alone = try (Action{ .registry = &test_registry }).execute(arena.allocator(), &.{first});
    var unrelated = first;
    unrelated.source_ordinal = 2;
    unrelated.workflow_id = workflow.WorkflowId.parse("unrelated").?;
    const together = try (Action{ .registry = &test_registry }).execute(arena.allocator(), &.{ first, unrelated });
    try std.testing.expectEqualStrings(alone[0].authority.workflow_id.bytes, together[0].authority.workflow_id.bytes);
    try std.testing.expectEqualStrings(alone[0].authority.nodes[0].contract_id.bytes, together[0].authority.nodes[0].contract_id.bytes);
    try std.testing.expectEqualDeep(alone[0].authority.transitions, together[0].authority.transitions);
}
