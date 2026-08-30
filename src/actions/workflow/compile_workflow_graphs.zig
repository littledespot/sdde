const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const workflow = @import("../../domain/workflow.zig");
const workflow_definition = @import("../../domain/workflow_definition.zig");
const compilation = @import("../../domain/workflow_compilation.zig");

pub const Error = error{WorkflowGraphCompileInvalid};

pub const Action = struct {
    registry: *const compilation.CompilerRegistry,

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
        definitions: []const workflow_definition.Definition,
    ) Error![]const compilation.CompiledWorkflow {
        const graphs = allocator.alloc(compilation.CompiledWorkflow, definitions.len) catch return invalid();
        for (definitions, graphs) |definition, *graph| {
            const invocation = uniqueInvocation(self.registry.invocations, definition.invocation_contract_id.bytes) orelse return invalid();
            if (!invocation.capability_free) return invalid();
            const policy = uniquePolicy(self.registry.policies, definition.policy_profile_id.bytes) orelse return invalid();
            if (!hasNode(definition.nodes, definition.entry_node_id.bytes)) return invalid();

            const nodes = allocator.alloc(compilation.CompiledNode, definition.nodes.len) catch return invalid();
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

fn validateParameters(contract: compilation.NodeContract, parameters: []const workflow.ParameterBinding) Error!void {
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
    definition: workflow_definition.Definition,
    nodes: []const compilation.CompiledNode,
    policy: compilation.PolicyProfile,
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

fn uniqueInvocation(values: []const compilation.InvocationContract, id: []const u8) ?compilation.InvocationContract {
    var result: ?compilation.InvocationContract = null;
    for (values) |value| if (std.mem.eql(u8, value.id, id)) {
        if (result != null or workflow.RegisteredRef.parse(value.id) == null) return null;
        result = value;
    };
    return result;
}
fn uniqueNode(values: []const compilation.NodeContract, id: []const u8) ?compilation.NodeContract {
    var result: ?compilation.NodeContract = null;
    for (values) |value| if (std.mem.eql(u8, value.id, id)) {
        if (result != null or workflow.RegisteredRef.parse(value.id) == null) return null;
        result = value;
    };
    return result;
}
fn uniquePolicy(values: []const compilation.PolicyProfile, id: []const u8) ?compilation.PolicyProfile {
    var result: ?compilation.PolicyProfile = null;
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
fn findCompiledNode(values: []const compilation.CompiledNode, expected: []const u8) ?compilation.CompiledNode {
    for (values) |value| if (std.mem.eql(u8, value.id.bytes, expected)) return value;
    return null;
}
fn findParameter(values: []const workflow.ParameterBinding, expected: []const u8) ?workflow.ParameterBinding {
    for (values) |value| if (std.mem.eql(u8, value.id.bytes, expected)) return value;
    return null;
}
fn findDescriptor(values: []const compilation.ParameterDescriptor, expected: []const u8) ?compilation.ParameterDescriptor {
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

const test_registry: compilation.CompilerRegistry = .{
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

fn testDefinition(contract_id: []const u8, transitions: []const workflow.Transition) workflow_definition.Definition {
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
    const valid = [_]workflow_definition.Definition{testDefinition("core.noop@1", &transitions)};
    const graphs = try (Action{ .registry = &test_registry }).execute(arena.allocator(), &valid);
    try std.testing.expectEqualStrings("arbitrary-flow", graphs[0].authority.workflow_id.bytes);

    const unknown = [_]workflow_definition.Definition{testDefinition("core.missing@1", &transitions)};
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        (Action{ .registry = &test_registry }).execute(arena.allocator(), &unknown),
    );
}

test "compiler rejects an incomplete transition table and capability escalation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const incomplete = [_]workflow_definition.Definition{testDefinition("core.noop@1", &.{})};
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        (Action{ .registry = &test_registry }).execute(arena.allocator(), &incomplete),
    );

    const capable_nodes = [_]compilation.NodeContract{.{
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
    const definition = [_]workflow_definition.Definition{testDefinition("core.noop@1", &transitions)};
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        (Action{ .registry = &registry }).execute(arena.allocator(), &definition),
    );

    const allowed_policies = [_]compilation.PolicyProfile{.{
        .id = "core.safe@1",
        .allowed_capabilities = &capabilities,
        .allowed_terminal_outcomes = &.{.ok},
    }};
    registry.policies = &allowed_policies;
    const allowed = try (Action{ .registry = &registry }).execute(arena.allocator(), &definition);
    try std.testing.expectEqualStrings("project-write", allowed[0].authority.nodes[0].capabilities[0]);
    registry.capabilities = &.{};
    try expectCompileInvalid(arena.allocator(), &registry, definition[0]);
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

    var shifted = first;
    shifted.source_ordinal = 2;
    const inserted = try (Action{ .registry = &test_registry }).execute(arena.allocator(), &.{ unrelated, shifted });
    try std.testing.expectEqualDeep(alone[0].authority, inserted[1].authority);
}

test "compiler resolves invocation and policy exactly and requires capability-free invocation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const transitions = [_]workflow.Transition{terminalTransition(.ok)};
    var definition = testDefinition("core.noop@1", &transitions);

    definition.invocation_contract_id = workflow.RegisteredRef.parse("core.missing@1").?;
    try expectCompileInvalid(arena.allocator(), &test_registry, definition);
    definition = testDefinition("core.noop@1", &transitions);
    definition.policy_profile_id = workflow.RegisteredRef.parse("core.missing@1").?;
    try expectCompileInvalid(arena.allocator(), &test_registry, definition);

    const capable_invocations = [_]compilation.InvocationContract{.{
        .id = "core.empty@1",
        .capability_free = false,
        .produces = &.{},
    }};
    var registry = test_registry;
    registry.invocations = &capable_invocations;
    try expectCompileInvalid(arena.allocator(), &registry, testDefinition("core.noop@1", &transitions));

    const ambiguous_invocations = [_]compilation.InvocationContract{
        .{ .id = "core.empty@1", .capability_free = true, .produces = &.{} },
        .{ .id = "core.empty@1", .capability_free = true, .produces = &.{} },
    };
    registry.invocations = &ambiguous_invocations;
    try expectCompileInvalid(arena.allocator(), &registry, testDefinition("core.noop@1", &transitions));

    registry = test_registry;
    const ambiguous_nodes = [_]compilation.NodeContract{ test_registry.nodes[0], test_registry.nodes[0] };
    registry.nodes = &ambiguous_nodes;
    try expectCompileInvalid(arena.allocator(), &registry, testDefinition("core.noop@1", &transitions));

    registry = test_registry;
    const ambiguous_policies = [_]compilation.PolicyProfile{ test_registry.policies[0], test_registry.policies[0] };
    registry.policies = &ambiguous_policies;
    try expectCompileInvalid(arena.allocator(), &registry, testDefinition("core.noop@1", &transitions));
}

test "compiler enforces every definition-safe parameter constraint" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const descriptors = [_]compilation.ParameterDescriptor{
        .{ .id = "flag", .kind = .boolean, .required = true, .workflow_definition_safe = true },
        .{ .id = "count", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 1, .integer_max = 3 },
        .{ .id = "mode", .kind = .@"enum", .required = true, .workflow_definition_safe = true, .enum_members = &.{ "safe", "strict" } },
        .{ .id = "profile", .kind = .registered_id, .required = true, .workflow_definition_safe = true, .registered_values = &.{"core.profile@1"} },
    };
    const contract = compilation.NodeContract{
        .id = "core.parameterized@1",
        .parameters = &descriptors,
        .requires = &.{},
        .produces = &.{},
        .outcomes = &.{.ok},
        .side_effect = .none,
    };
    const bindings = [_]workflow.ParameterBinding{
        parameterBinding("flag", .{ .boolean = true }),
        parameterBinding("count", .{ .integer = 2 }),
        parameterBinding("mode", .{ .@"enum" = workflow.WorkflowNodeId.parse("safe").? }),
        parameterBinding("profile", .{ .registered_id = workflow.RegisteredRef.parse("core.profile@1").? }),
    };
    const node = workflow.DeclarativeNode{
        .id = workflow.WorkflowNodeId.parse("run").?,
        .contract_id = workflow.RegisteredRef.parse("core.parameterized@1").?,
        .parameters = &bindings,
    };
    const transitions = [_]workflow.Transition{terminalTransition(.ok)};
    var definition = testDefinition("core.noop@1", &transitions);
    definition.nodes = &.{node};
    var registry = test_registry;
    registry.nodes = &.{contract};
    _ = try (Action{ .registry = &registry }).execute(arena.allocator(), &.{definition});

    const invalid_bindings = [_][]const workflow.ParameterBinding{
        bindings[0..3],
        &.{ bindings[0], bindings[1], bindings[2], parameterBinding("profile", .{ .registered_id = workflow.RegisteredRef.parse("core.other@1").? }) },
        &.{ bindings[0], parameterBinding("count", .{ .integer = 4 }), bindings[2], bindings[3] },
        &.{ bindings[0], bindings[1], parameterBinding("mode", .{ .@"enum" = workflow.WorkflowNodeId.parse("other").? }), bindings[3] },
        &.{ parameterBinding("flag", .{ .integer = 1 }), bindings[1], bindings[2], bindings[3] },
        &.{ bindings[0], bindings[1], bindings[2], bindings[3], parameterBinding("unknown", .{ .boolean = true }) },
    };
    for (invalid_bindings) |invalid_bindings_value| {
        var invalid_node = node;
        invalid_node.parameters = invalid_bindings_value;
        var invalid_definition = definition;
        invalid_definition.nodes = &.{invalid_node};
        try expectCompileInvalid(arena.allocator(), &registry, invalid_definition);
    }

    var unsafe_descriptors = descriptors;
    unsafe_descriptors[0].workflow_definition_safe = false;
    var unsafe_contract = contract;
    unsafe_contract.parameters = &unsafe_descriptors;
    registry.nodes = &.{unsafe_contract};
    try expectCompileInvalid(arena.allocator(), &registry, definition);
}

test "compiler rejects invalid transition closure and preserves registered gates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gates = [_][]const u8{"predecessor-current@1"};
    const node_contracts = [_]compilation.NodeContract{.{
        .id = "core.noop@1",
        .parameters = &.{},
        .requires = &.{},
        .produces = &.{},
        .outcomes = &.{ .ok, .failed },
        .side_effect = .none,
        .gates = &gates,
    }};
    const policies = [_]compilation.PolicyProfile{.{
        .id = "core.safe@1",
        .allowed_capabilities = &.{},
        .allowed_terminal_outcomes = &.{ .ok, .failed },
    }};
    const transitions = [_]workflow.Transition{ terminalTransition(.ok), terminalTransition(.failed) };
    var definition = testDefinition("core.noop@1", &transitions);
    var registry = test_registry;
    registry.nodes = &node_contracts;
    registry.policies = &policies;
    registry.gates = &gates;
    const graphs = try (Action{ .registry = &registry }).execute(arena.allocator(), &.{definition});
    try std.testing.expectEqualDeep(gates[0..], graphs[0].authority.nodes[0].gates);

    registry.gates = &.{};
    try expectCompileInvalid(arena.allocator(), &registry, definition);
    registry.gates = &gates;

    const duplicate = [_]workflow.Transition{ terminalTransition(.ok), terminalTransition(.ok), terminalTransition(.failed) };
    definition.transitions = &duplicate;
    try expectCompileInvalid(arena.allocator(), &registry, definition);

    const missing = [_]workflow.Transition{terminalTransition(.ok)};
    definition.transitions = &missing;
    try expectCompileInvalid(arena.allocator(), &registry, definition);

    const restrictive_policies = [_]compilation.PolicyProfile{.{
        .id = "core.safe@1",
        .allowed_capabilities = &.{},
        .allowed_terminal_outcomes = &.{.ok},
    }};
    registry.policies = &restrictive_policies;
    definition.transitions = &transitions;
    try expectCompileInvalid(arena.allocator(), &registry, definition);
    registry.policies = &policies;

    const relabelled = [_]workflow.Transition{
        terminalTransition(.ok),
        .{ .from = test_valid_nodes[0].id, .outcome = .failed, .target = .{ .terminal = .ok } },
    };
    definition.transitions = &relabelled;
    try expectCompileInvalid(arena.allocator(), &registry, definition);

    const dangling = [_]workflow.Transition{
        .{ .from = test_valid_nodes[0].id, .outcome = .ok, .target = .{ .node = workflow.WorkflowNodeId.parse("missing").? } },
        terminalTransition(.failed),
    };
    definition.transitions = &dangling;
    try expectCompileInvalid(arena.allocator(), &registry, definition);

    definition = testDefinition("core.noop@1", &transitions);
    definition.entry_node_id = workflow.WorkflowNodeId.parse("missing").?;
    try expectCompileInvalid(arena.allocator(), &registry, definition);
}

fn terminalTransition(outcome: workflow.OutcomeTag) workflow.Transition {
    return .{
        .from = workflow.WorkflowNodeId.parse("run").?,
        .outcome = outcome,
        .target = .{ .terminal = outcome },
    };
}

fn parameterBinding(id: []const u8, value: workflow.ParameterValue) workflow.ParameterBinding {
    return .{ .id = workflow.WorkflowParameterId.parse(id).?, .value = value };
}

fn expectCompileInvalid(allocator: std.mem.Allocator, registry: *const compilation.CompilerRegistry, definition: workflow_definition.Definition) !void {
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        (Action{ .registry = registry }).execute(allocator, &.{definition}),
    );
}
