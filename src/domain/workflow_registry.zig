const std = @import("std");
const pipeline = @import("pipeline.zig");
const telemetry = @import("telemetry.zig");
const workflow = @import("workflow.zig");
const workflow_definition = @import("workflow_definition.zig");
const compilation = @import("workflow_compilation.zig");
const inventory = @import("workflow_inventory.zig");

pub const RegistryCandidate = struct {
    inventory: inventory.Inventory,
    captures: []const inventory.Capture,
    definitions: []const workflow_definition.Definition,
    graphs: []const compilation.CompiledWorkflow,
};

pub const ValidatedWorkflowDefinitionRegistry = opaque {
    pub fn count(self: *const ValidatedWorkflowDefinitionRegistry) usize {
        return registryStorage(self).entries.len;
    }

    pub fn resolve(
        self: *const ValidatedWorkflowDefinitionRegistry,
        id: workflow.WorkflowId,
    ) ?*const compilation.CompiledWorkflow {
        for (registryStorage(self).entries) |*entry| {
            if (std.mem.eql(u8, entry.authority.workflow_id.bytes, id.bytes)) return entry;
        }
        return null;
    }
};

pub const Owner = opaque {};
const RegistryStorage = struct { entries: []const compilation.CompiledWorkflow };
const OwnerStorage = struct {
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    registry: RegistryStorage,
};
pub const Error = error{InvalidWorkflowRegistry};

pub fn createValidated(allocator: std.mem.Allocator, candidate: RegistryCandidate) Error!*Owner {
    try validateCandidate(candidate);
    const owner = allocator.create(OwnerStorage) catch return error.InvalidWorkflowRegistry;
    errdefer allocator.destroy(owner);
    owner.* = .{ .backing_allocator = allocator, .arena = .init(allocator), .registry = undefined };
    errdefer owner.arena.deinit();
    const entries = owner.arena.allocator().alloc(compilation.CompiledWorkflow, candidate.graphs.len) catch {
        return error.InvalidWorkflowRegistry;
    };
    for (entries, candidate.graphs) |*destination, source| {
        destination.* = cloneGraph(owner.arena.allocator(), source) catch return error.InvalidWorkflowRegistry;
    }
    owner.registry = .{ .entries = entries };
    return @ptrCast(owner);
}

pub fn registry(owner: *const Owner) *const ValidatedWorkflowDefinitionRegistry {
    return @ptrCast(&ownerStorageConst(owner).registry);
}

pub fn deinitOwner(owner: *Owner) void {
    const storage = ownerStorage(owner);
    const allocator = storage.backing_allocator;
    storage.arena.deinit();
    allocator.destroy(storage);
}

fn validateCandidate(candidate: RegistryCandidate) Error!void {
    inventory.validate(candidate.inventory) catch return error.InvalidWorkflowRegistry;
    inventory.validateCaptureBudget(candidate.inventory) catch return error.InvalidWorkflowRegistry;
    if (candidate.graphs.len > workflow_definition.max_definitions or candidate.graphs.len != candidate.definitions.len or
        candidate.graphs.len != candidate.captures.len or
        candidate.graphs.len != candidate.inventory.definition_ordinals.len)
    {
        return error.InvalidWorkflowRegistry;
    }
    try validateCaptureDefinitionJoins(
        candidate.inventory.descriptors,
        candidate.inventory.definition_ordinals,
        candidate.captures,
        candidate.definitions,
    );
    for (candidate.inventory.accounts, 0..) |account, index| {
        if (account.ordinal != index + 1 or !std.mem.eql(u8, account.path, candidate.inventory.descriptors[index].path)) {
            return error.InvalidWorkflowRegistry;
        }
    }
    for (candidate.graphs, 0..) |graph, index| {
        const definition = findDefinition(candidate.definitions, graph.source_ordinal) orelse return error.InvalidWorkflowRegistry;
        if (!graphProjectsDefinition(graph, definition) or
            !containsOrdinal(candidate.inventory.definition_ordinals, graph.source_ordinal)) return error.InvalidWorkflowRegistry;
        for (candidate.graphs[0..index]) |previous| {
            if (std.mem.eql(u8, graph.authority.workflow_id.bytes, previous.authority.workflow_id.bytes) or
                std.mem.eql(u8, &graph.shortcode.bytes, &previous.shortcode.bytes) or
                graph.source_ordinal == previous.source_ordinal) return error.InvalidWorkflowRegistry;
        }
        if (index > 0 and std.mem.order(
            u8,
            candidate.graphs[index - 1].authority.workflow_id.bytes,
            graph.authority.workflow_id.bytes,
        ) != .lt) return error.InvalidWorkflowRegistry;
    }
}

fn graphProjectsDefinition(graph: compilation.CompiledWorkflow, definition: workflow_definition.Definition) bool {
    if (graph.source_ordinal != definition.source_ordinal or
        !std.mem.eql(u8, graph.authority.workflow_id.bytes, definition.workflow_id.bytes) or
        graph.authority.workflow_version != definition.workflow_version or
        !std.mem.eql(u8, &graph.shortcode.bytes, &definition.shortcode.bytes) or
        !std.mem.eql(u8, graph.authority.invocation_contract_id.bytes, definition.invocation_contract_id.bytes) or
        !std.mem.eql(u8, graph.authority.policy_profile_id.bytes, definition.policy_profile_id.bytes) or
        !std.mem.eql(u8, graph.authority.entry_node_id.bytes, definition.entry_node_id.bytes) or
        graph.authority.nodes.len != definition.nodes.len or
        graph.authority.transitions.len != definition.transitions.len) return false;
    for (graph.authority.nodes, definition.nodes) |compiled, declared| {
        if (!std.mem.eql(u8, compiled.id.bytes, declared.id.bytes) or
            !std.mem.eql(u8, compiled.contract_id.bytes, declared.contract_id.bytes) or
            compiled.parameters.len != declared.parameters.len) return false;
        for (compiled.parameters, declared.parameters) |compiled_parameter, declared_parameter| {
            if (!sameParameter(compiled_parameter, declared_parameter)) return false;
        }
    }
    for (graph.authority.transitions, definition.transitions) |compiled, declared| {
        if (!sameTransition(compiled, declared)) return false;
    }
    return true;
}

fn sameParameter(left: workflow.ParameterBinding, right: workflow.ParameterBinding) bool {
    if (!std.mem.eql(u8, left.id.bytes, right.id.bytes) or
        std.meta.activeTag(left.value) != std.meta.activeTag(right.value)) return false;
    return switch (left.value) {
        .boolean => |value| value == right.value.boolean,
        .integer => |value| value == right.value.integer,
        .@"enum" => |value| std.mem.eql(u8, value.bytes, right.value.@"enum".bytes),
        .registered_id => |value| std.mem.eql(u8, value.bytes, right.value.registered_id.bytes),
    };
}

fn sameTransition(left: workflow.Transition, right: workflow.Transition) bool {
    if (!std.mem.eql(u8, left.from.bytes, right.from.bytes) or left.outcome != right.outcome or
        std.meta.activeTag(left.target) != std.meta.activeTag(right.target)) return false;
    return switch (left.target) {
        .node => |value| std.mem.eql(u8, value.bytes, right.target.node.bytes),
        .terminal => |value| value == right.target.terminal,
    };
}

fn validateCaptureDefinitionJoins(
    descriptors: []const inventory.InventoryDescriptor,
    definition_ordinals: []const u16,
    captures: []const inventory.Capture,
    definitions: []const workflow_definition.Definition,
) Error!void {
    if (captures.len != definition_ordinals.len or definitions.len != captures.len) return error.InvalidWorkflowRegistry;
    for (captures, definitions, definition_ordinals) |capture, definition, ordinal| {
        if (ordinal == 0 or ordinal > descriptors.len) return error.InvalidWorkflowRegistry;
        const expected_size = descriptors[ordinal - 1].size orelse return error.InvalidWorkflowRegistry;
        if (capture.ordinal != ordinal or capture.bytes.len != expected_size or definition.source_ordinal != ordinal) {
            return error.InvalidWorkflowRegistry;
        }
    }
}

fn cloneGraph(allocator: std.mem.Allocator, source: compilation.CompiledWorkflow) !compilation.CompiledWorkflow {
    const nodes = try allocator.alloc(compilation.CompiledNode, source.authority.nodes.len);
    for (nodes, source.authority.nodes) |*destination, node| {
        destination.* = node;
        destination.id.bytes = try allocator.dupe(u8, node.id.bytes);
        destination.contract_id.bytes = try allocator.dupe(u8, node.contract_id.bytes);
        destination.parameters = try cloneParameters(allocator, node.parameters);
        destination.requires = try allocator.dupe(pipeline.DataKey, node.requires);
        destination.produces = try allocator.dupe(pipeline.DataKey, node.produces);
        destination.replaces = try allocator.dupe(pipeline.DataKey, node.replaces);
        destination.invalidates = try allocator.dupe(pipeline.DataKey, node.invalidates);
        destination.outcomes = try allocator.dupe(workflow.OutcomeTag, node.outcomes);
        destination.gates = try cloneStrings(allocator, node.gates);
        destination.capabilities = try cloneStrings(allocator, node.capabilities);
    }
    const transitions = try allocator.alloc(workflow.Transition, source.authority.transitions.len);
    for (transitions, source.authority.transitions) |*destination, transition| {
        destination.* = transition;
        destination.from.bytes = try allocator.dupe(u8, transition.from.bytes);
        if (transition.target == .node) destination.target.node.bytes = try allocator.dupe(u8, transition.target.node.bytes);
    }
    return .{
        .source_ordinal = source.source_ordinal,
        .shortcode = source.shortcode,
        .authority = .{
            .workflow_id = .{ .bytes = try allocator.dupe(u8, source.authority.workflow_id.bytes) },
            .workflow_version = source.authority.workflow_version,
            .invocation_contract_id = .{ .bytes = try allocator.dupe(u8, source.authority.invocation_contract_id.bytes) },
            .policy_profile_id = .{ .bytes = try allocator.dupe(u8, source.authority.policy_profile_id.bytes) },
            .entry_node_id = .{ .bytes = try allocator.dupe(u8, source.authority.entry_node_id.bytes) },
            .invocation_outputs = try allocator.dupe(pipeline.DataKey, source.authority.invocation_outputs),
            .nodes = nodes,
            .transitions = transitions,
        },
    };
}

fn cloneParameters(allocator: std.mem.Allocator, source: []const workflow.ParameterBinding) ![]const workflow.ParameterBinding {
    const values = try allocator.alloc(workflow.ParameterBinding, source.len);
    for (values, source) |*destination, parameter| {
        destination.* = parameter;
        destination.id.bytes = try allocator.dupe(u8, parameter.id.bytes);
        switch (destination.value) {
            .@"enum" => |*item| item.bytes = try allocator.dupe(u8, item.bytes),
            .registered_id => |*item| item.bytes = try allocator.dupe(u8, item.bytes),
            else => {},
        }
    }
    return values;
}

fn cloneStrings(allocator: std.mem.Allocator, source: []const []const u8) ![]const []const u8 {
    const values = try allocator.alloc([]const u8, source.len);
    for (values, source) |*destination, value| destination.* = try allocator.dupe(u8, value);
    return values;
}

fn findDefinition(values: []const workflow_definition.Definition, ordinal: u16) ?workflow_definition.Definition {
    for (values) |value| if (value.source_ordinal == ordinal) return value;
    return null;
}

fn containsOrdinal(values: []const u16, expected: u16) bool {
    for (values) |value| if (value == expected) return true;
    return false;
}

fn registryStorage(value: *const ValidatedWorkflowDefinitionRegistry) *const RegistryStorage {
    return @ptrCast(@alignCast(value));
}

fn ownerStorage(owner: *Owner) *OwnerStorage {
    return @ptrCast(@alignCast(owner));
}

fn ownerStorageConst(owner: *const Owner) *const OwnerStorage {
    return @ptrCast(@alignCast(owner));
}

test "definition captures and graphs join exact registry evidence" {
    const descriptor = [_]inventory.InventoryDescriptor{.{ .path = "hello.workflow.yaml", .kind = .file, .size = 3 }};
    const ordinals = [_]u16{1};
    const captures = [_]inventory.Capture{.{ .ordinal = 1, .bytes = "abc" }};
    const definition = workflow_definition.Definition{
        .source_ordinal = 1,
        .workflow_id = workflow.WorkflowId.parse("hello").?,
        .workflow_version = 1,
        .shortcode = telemetry.WorkflowShortcode.parse("HELO") catch unreachable,
        .invocation_contract_id = workflow.RegisteredRef.parse("core.empty@1").?,
        .policy_profile_id = workflow.RegisteredRef.parse("core.safe@1").?,
        .entry_node_id = workflow.WorkflowNodeId.parse("run").?,
        .nodes = &.{},
        .transitions = &.{},
    };
    try validateCaptureDefinitionJoins(&descriptor, &ordinals, &captures, &.{definition});
    const wrong_size = [_]inventory.Capture{.{ .ordinal = 1, .bytes = "ab" }};
    try std.testing.expectError(error.InvalidWorkflowRegistry, validateCaptureDefinitionJoins(&descriptor, &ordinals, &wrong_size, &.{definition}));

    const declared_node: workflow.DeclarativeNode = .{
        .id = workflow.WorkflowNodeId.parse("run").?,
        .contract_id = workflow.RegisteredRef.parse("core.noop@1").?,
        .parameters = &.{},
    };
    const transition: workflow.Transition = .{ .from = declared_node.id, .outcome = .ok, .target = .{ .terminal = .ok } };
    var projected_definition = definition;
    projected_definition.entry_node_id = declared_node.id;
    projected_definition.nodes = &.{declared_node};
    projected_definition.transitions = &.{transition};
    const compiled_node: compilation.CompiledNode = .{
        .id = declared_node.id,
        .contract_id = declared_node.contract_id,
        .parameters = &.{},
        .requires = &.{},
        .produces = &.{},
        .replaces = &.{},
        .invalidates = &.{},
        .outcomes = &.{.ok},
        .side_effect = .none,
        .gates = &.{},
        .capabilities = &.{},
    };
    var graph: compilation.CompiledWorkflow = .{
        .source_ordinal = 1,
        .shortcode = projected_definition.shortcode,
        .authority = .{
            .workflow_id = projected_definition.workflow_id,
            .workflow_version = 1,
            .invocation_contract_id = projected_definition.invocation_contract_id,
            .policy_profile_id = projected_definition.policy_profile_id,
            .entry_node_id = declared_node.id,
            .invocation_outputs = &.{},
            .nodes = &.{compiled_node},
            .transitions = &.{transition},
        },
    };
    try std.testing.expect(graphProjectsDefinition(graph, projected_definition));
    graph.authority.workflow_version = 2;
    try std.testing.expect(!graphProjectsDefinition(graph, projected_definition));
}
