const std = @import("std");
const pipeline = @import("pipeline.zig");
const workflow = @import("workflow.zig");
const definition = @import("workflow_definition.zig");
const compilation = @import("workflow_compilation.zig");
const inventory = @import("workflow_inventory.zig");
const workflow_retry = @import("workflow_retry.zig");

pub const RegistryCandidate = struct {
    inventory: inventory.Inventory,
    definition_captures: []const inventory.Capture,
    resource_manifest: inventory.ResourceManifest,
    resource_captures: []const inventory.Capture,
    definitions: []const definition.Definition,
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
    inventory.validate(candidate.inventory) catch return invalid();
    inventory.validateCaptureBudget(candidate.inventory) catch return invalid();
    inventory.validateResourceCaptureBudget(candidate.inventory, candidate.resource_manifest) catch return invalid();
    if (candidate.graphs.len > definition.max_definitions or
        candidate.graphs.len != candidate.definitions.len or
        candidate.graphs.len != candidate.definition_captures.len or
        candidate.graphs.len != candidate.inventory.definition_ordinals.len or
        candidate.resource_captures.len != candidate.resource_manifest.resource_ordinals.len) return invalid();
    try validateDefinitionCaptures(candidate);
    try validateResourceCaptures(candidate);
    for (candidate.graphs, 0..) |graph, index| {
        const declared = findDefinition(candidate.definitions, graph.source_ordinal) orelse return invalid();
        if (!graphProjectsDefinition(candidate, graph, declared) or
            !containsOrdinal(candidate.inventory.definition_ordinals, graph.source_ordinal)) return invalid();
        for (candidate.graphs[0..index]) |prior| {
            if (std.mem.eql(u8, graph.authority.workflow_id.bytes, prior.authority.workflow_id.bytes) or
                std.mem.eql(u8, &graph.shortcode.bytes, &prior.shortcode.bytes) or
                graph.source_ordinal == prior.source_ordinal) return invalid();
        }
        if (index > 0 and std.mem.order(u8, candidate.graphs[index - 1].authority.workflow_id.bytes, graph.authority.workflow_id.bytes) != .lt) {
            return invalid();
        }
    }
}

fn validateDefinitionCaptures(candidate: RegistryCandidate) Error!void {
    for (candidate.definition_captures, candidate.definitions, candidate.inventory.definition_ordinals) |capture, declared, ordinal| {
        if (ordinal == 0 or ordinal > candidate.inventory.descriptors.len) return invalid();
        const descriptor = candidate.inventory.descriptors[ordinal - 1];
        if (descriptor.size == null or capture.ordinal != ordinal or capture.bytes.len != descriptor.size.? or
            declared.source_ordinal != ordinal) return invalid();
    }
}

fn validateResourceCaptures(candidate: RegistryCandidate) Error!void {
    for (candidate.resource_captures, candidate.resource_manifest.resource_ordinals) |capture, ordinal| {
        if (ordinal == 0 or ordinal > candidate.inventory.descriptors.len) return invalid();
        const descriptor = candidate.inventory.descriptors[ordinal - 1];
        if (descriptor.size == null or capture.ordinal != ordinal or capture.bytes.len != descriptor.size.? or
            candidate.inventory.accounts[ordinal - 1].disposition != .resource) return invalid();
    }
}

fn graphProjectsDefinition(
    candidate: RegistryCandidate,
    graph: compilation.CompiledWorkflow,
    declared: definition.Definition,
) bool {
    if (graph.source_ordinal != declared.source_ordinal or
        !std.mem.eql(u8, graph.authority.workflow_id.bytes, declared.workflow_id.bytes) or
        graph.authority.workflow_version != declared.workflow_version or
        !std.mem.eql(u8, &graph.shortcode.bytes, &declared.shortcode.bytes) or
        !std.mem.eql(u8, graph.authority.invocation_operation_id.bytes, declared.invocation_operation_id.bytes) or
        !std.mem.eql(u8, graph.authority.policy_profile_id.bytes, declared.policy_profile_id.bytes) or
        !std.mem.eql(u8, graph.authority.start_step_id.bytes, declared.start_step_id.bytes) or
        !graph.authority.total_model_token_budget.isValid() or
        graph.authority.resources.len != declared.resources.len or
        graph.authority.steps.len != declared.steps.len) return false;

    for (graph.authority.resources, declared.resources) |compiled, resource| {
        const binding = findBinding(candidate.resource_manifest.bindings, declared.source_ordinal, resource.id) orelse return false;
        const capture = findCapture(candidate.resource_captures, binding.resource_ordinal) orelse return false;
        if (!std.mem.eql(u8, compiled.id.bytes, resource.id.bytes) or
            !std.mem.eql(u8, compiled.bytes, capture.bytes)) return false;
    }
    var transition_count: usize = 0;
    for (graph.authority.steps, declared.steps) |compiled, step| {
        if (!std.mem.eql(u8, compiled.id.bytes, step.id.bytes) or
            !std.mem.eql(u8, compiled.operation_id.bytes, step.operation_id.bytes) or
            compiled.parameters.len != step.parameters.len or compiled.outcomes.len != step.outcomes.len) return false;
        const retry_parameter = findCompiledParameter(compiled.parameters, workflow_retry.parameter_id);
        if (compiled.retry_authority) |authority| {
            if (!authority.isValid() or
                !std.mem.eql(u8, authority.workflow_id.bytes, graph.authority.workflow_id.bytes) or
                authority.workflow_version != graph.authority.workflow_version or
                !std.mem.eql(u8, authority.operation_instance_id.bytes, compiled.id.bytes) or
                retry_parameter == null or retry_parameter.?.value != .integer or
                retry_parameter.?.value.integer < 0 or
                authority.limit.value != retry_parameter.?.value.integer)
            {
                return false;
            }
        } else if (retry_parameter != null) {
            return false;
        }
        for (compiled.parameters, step.parameters) |compiled_parameter, parameter| {
            if (!sameParameter(compiled_parameter, parameter)) return false;
        }
        transition_count += step.outcomes.len;
        for (step.outcomes) |outcome| {
            const transition = findTransition(graph.authority.transitions, step.id, outcome.outcome) orelse return false;
            if (!sameTarget(transition.target, outcome.target)) return false;
        }
    }
    return graph.authority.transitions.len == transition_count;
}

fn cloneDataSchemas(allocator: std.mem.Allocator, schemas: []const @import("pipeline_data.zig").Schema) std.mem.Allocator.Error![]const @import("pipeline_data.zig").Schema {
    const result = try allocator.dupe(@import("pipeline_data.zig").Schema, schemas);
    for (result) |*schema| schema.type_name = try allocator.dupe(u8, schema.type_name);
    return result;
}

fn sameParameter(left: compilation.CompiledParameter, right: workflow.ParameterBinding) bool {
    if (!std.mem.eql(u8, left.id.bytes, right.id.bytes)) return false;
    return switch (left.value) {
        .boolean => |value| right.value == .boolean and value == right.value.boolean,
        .integer => |value| right.value == .integer and value == right.value.integer,
        .string => |value| right.value == .string and std.mem.eql(u8, value, right.value.string),
        .enumeration => |value| right.value == .string and std.mem.eql(u8, value, right.value.string),
        .registered_ref => |value| right.value == .string and std.mem.eql(u8, value.bytes, right.value.string),
        .resource => |value| right.value == .string and std.mem.eql(u8, value.bytes, right.value.string),
        .model_slot => |value| right.value == .string and std.mem.eql(u8, value.bytes, right.value.string),
    };
}

fn sameTarget(left: workflow.TransitionTarget, right: workflow.TransitionTarget) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .step => |value| std.mem.eql(u8, value.bytes, right.step.bytes),
        .terminal => |value| value == right.terminal,
    };
}

fn cloneGraph(allocator: std.mem.Allocator, source: compilation.CompiledWorkflow) !compilation.CompiledWorkflow {
    const resources = try allocator.alloc(compilation.CompiledResource, source.authority.resources.len);
    for (resources, source.authority.resources) |*destination, item| {
        destination.* = item;
        destination.id.bytes = try allocator.dupe(u8, item.id.bytes);
        destination.bytes = try allocator.dupe(u8, item.bytes);
    }
    const steps = try allocator.alloc(compilation.CompiledStep, source.authority.steps.len);
    for (steps, source.authority.steps) |*destination, step| {
        destination.* = step;
        destination.id.bytes = try allocator.dupe(u8, step.id.bytes);
        destination.operation_id.bytes = try allocator.dupe(u8, step.operation_id.bytes);
        destination.parameters = try cloneParameters(allocator, step.parameters);
        destination.requires = try allocator.dupe(pipeline.DataKey, step.requires);
        destination.optional = try allocator.dupe(pipeline.DataKey, step.optional);
        destination.produces = try allocator.dupe(pipeline.DataKey, step.produces);
        destination.replaces = try allocator.dupe(pipeline.DataKey, step.replaces);
        destination.invalidates = try allocator.dupe(pipeline.DataKey, step.invalidates);
        destination.outcomes = try allocator.dupe(workflow.OutcomeTag, step.outcomes);
        destination.gates = try cloneStrings(allocator, step.gates);
        destination.capabilities = try cloneStrings(allocator, step.capabilities);
        if (step.retry_authority) |authority| {
            destination.retry_authority = authority;
            destination.retry_authority.?.workflow_id.bytes = try allocator.dupe(u8, authority.workflow_id.bytes);
            destination.retry_authority.?.operation_instance_id.bytes = try allocator.dupe(u8, authority.operation_instance_id.bytes);
        }
    }
    const transitions = try allocator.alloc(workflow.Transition, source.authority.transitions.len);
    for (transitions, source.authority.transitions) |*destination, transition| {
        destination.* = transition;
        destination.from.bytes = try allocator.dupe(u8, transition.from.bytes);
        if (transition.target == .step) destination.target.step.bytes = try allocator.dupe(u8, transition.target.step.bytes);
    }
    return .{
        .source_ordinal = source.source_ordinal,
        .shortcode = source.shortcode,
        .authority = .{
            .data_schemas = try cloneDataSchemas(allocator, source.authority.data_schemas),
            .workflow_id = .{ .bytes = try allocator.dupe(u8, source.authority.workflow_id.bytes) },
            .workflow_version = source.authority.workflow_version,
            .invocation_operation_id = .{ .bytes = try allocator.dupe(u8, source.authority.invocation_operation_id.bytes) },
            .policy_profile_id = .{ .bytes = try allocator.dupe(u8, source.authority.policy_profile_id.bytes) },
            .total_model_token_budget = source.authority.total_model_token_budget,
            .start_step_id = .{ .bytes = try allocator.dupe(u8, source.authority.start_step_id.bytes) },
            .invocation_outputs = try allocator.dupe(pipeline.DataKey, source.authority.invocation_outputs),
            .resources = resources,
            .steps = steps,
            .transitions = transitions,
            .maximum_step_executions = source.authority.maximum_step_executions,
        },
    };
}

fn cloneParameters(allocator: std.mem.Allocator, source: []const compilation.CompiledParameter) ![]const compilation.CompiledParameter {
    const values = try allocator.alloc(compilation.CompiledParameter, source.len);
    for (values, source) |*destination, parameter| {
        destination.* = parameter;
        destination.id.bytes = try allocator.dupe(u8, parameter.id.bytes);
        switch (destination.value) {
            .string => |*value| value.* = try allocator.dupe(u8, value.*),
            .enumeration => |*value| value.* = try allocator.dupe(u8, value.*),
            .registered_ref => |*value| value.bytes = try allocator.dupe(u8, value.bytes),
            .resource => |*value| value.bytes = try allocator.dupe(u8, value.bytes),
            .model_slot => |*value| value.bytes = try allocator.dupe(u8, value.bytes),
            else => {},
        }
    }
    return values;
}

fn findCompiledParameter(values: []const compilation.CompiledParameter, id: []const u8) ?compilation.CompiledParameter {
    for (values) |value| if (std.mem.eql(u8, value.id.bytes, id)) return value;
    return null;
}

fn cloneStrings(allocator: std.mem.Allocator, source: []const []const u8) ![]const []const u8 {
    const values = try allocator.alloc([]const u8, source.len);
    for (values, source) |*destination, value| destination.* = try allocator.dupe(u8, value);
    return values;
}

fn findDefinition(values: []const definition.Definition, ordinal: u16) ?definition.Definition {
    for (values) |value| if (value.source_ordinal == ordinal) return value;
    return null;
}
fn findBinding(values: []const inventory.ResourceBinding, ordinal: u16, id: workflow.WorkflowResourceId) ?inventory.ResourceBinding {
    for (values) |value| if (value.definition_ordinal == ordinal and std.mem.eql(u8, value.resource_id.bytes, id.bytes)) return value;
    return null;
}
fn findCapture(values: []const inventory.Capture, ordinal: u16) ?inventory.Capture {
    for (values) |value| if (value.ordinal == ordinal) return value;
    return null;
}
fn findTransition(values: []const workflow.Transition, step: workflow.WorkflowStepId, outcome: workflow.OutcomeTag) ?workflow.Transition {
    for (values) |value| if (value.outcome == outcome and std.mem.eql(u8, value.from.bytes, step.bytes)) return value;
    return null;
}
fn containsOrdinal(values: []const u16, expected: u16) bool {
    for (values) |value| if (value == expected) return true;
    return false;
}
fn invalid() Error {
    return error.InvalidWorkflowRegistry;
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
