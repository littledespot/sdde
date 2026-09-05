const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const workflow = @import("../../domain/workflow.zig");
const definition = @import("../../domain/workflow_definition.zig");
const compilation = @import("../../domain/workflow_compilation.zig");
const operation = @import("../../domain/workflow_operation.zig");
const inventory = @import("../../domain/workflow_inventory.zig");
const operation_registry = @import("../../ports/workflow_operation_registry.zig");
const provider_identity = @import("../../domain/llm_provider_identity.zig");
const workflow_retry = @import("../../domain/workflow_retry.zig");
const data = @import("../../domain/pipeline_data.zig");

pub const Error = error{WorkflowGraphCompileInvalid};

pub const Action = struct {
    registry: *const operation_registry.Registry,
    result_schema_compiler: @import("../../ports/model_result_schema_compiler.zig").Compiler,

    pub const contract: pipeline.NodeContract = .{
        .id = "compile-workflow-graphs@1",
        .kind = .action,
        .requires = &.{ .declarative_workflow_definitions, .workflow_resource_manifest, .workflow_resource_captures, .workflow_operation_registry_evidence },
        .produces = &.{.compiled_workflow_graphs},
        .side_effect = .none,
    };

    pub fn execute(
        self: Action,
        allocator: std.mem.Allocator,
        definitions: []const definition.Definition,
        inventory_value: inventory.Inventory,
        manifest: inventory.ResourceManifest,
        captures: []const inventory.Capture,
    ) Error![]const compilation.CompiledWorkflow {
        if (!self.registry.validate()) return invalid();
        const graphs = allocator.alloc(compilation.CompiledWorkflow, definitions.len) catch return invalid();
        for (definitions, graphs) |item, *graph| {
            const invocation = self.registry.resolveOperation(item.invocation_operation_id) orelse return invalid();
            if (invocation.contract.kind != .invocation) return invalid();
            const policy = self.registry.resolvePolicy(item.policy_profile_id) orelse return invalid();
            if (!hasStep(item.steps, item.start_step_id.bytes)) return invalid();

            const resources = try compileResources(allocator, self.registry, self.result_schema_compiler, item, inventory_value, manifest, captures);
            const steps = allocator.alloc(compilation.CompiledStep, item.steps.len) catch return invalid();
            var transition_count: usize = 0;
            for (item.steps, steps) |declared, *compiled| {
                const entry = self.registry.resolveOperation(declared.operation_id) orelse return invalid();
                if (entry.contract.kind != .step) return invalid();
                if (!@import("../../domain/workflow_capability.zig").permits(policy.allowed_capabilities, entry.binding.capabilities())) return invalid();
                const parameters = try compileParameters(allocator, entry.contract, declared.parameters, resources);
                const retry_authority = try resolveRetryAuthority(item, declared.id, entry.contract, parameters);
                transition_count = std.math.add(usize, transition_count, declared.outcomes.len) catch return invalid();
                try validateDeclaredOutcomes(entry.contract.outcomes, declared.outcomes, item.steps, policy.*);
                compiled.* = .{
                    .id = declared.id,
                    .operation_id = declared.operation_id,
                    .parameters = parameters,
                    .requires = entry.contract.requires,
                    .optional = entry.contract.optional,
                    .produces = entry.contract.produces,
                    .replaces = entry.contract.replaces,
                    .invalidates = entry.contract.invalidates,
                    .outcomes = entry.contract.outcomes,
                    .side_effect = entry.contract.side_effect,
                    .gates = try compileGates(allocator, self.registry, entry.contract.gates),
                    .capabilities = entry.binding.capabilities(),
                    .retry_authority = retry_authority,
                    .model = if (entry.contract.model_capacity) |capacity|
                        @import("../../domain/workflow_model.zig").resolve(self.registry.model_capacity orelse return invalid(), capacity, parameters) orelse return invalid()
                    else
                        null,
                };
            }

            const transitions = allocator.alloc(workflow.Transition, transition_count) catch return invalid();
            var transition_index: usize = 0;
            for (item.steps) |step| for (step.outcomes) |outcome| {
                transitions[transition_index] = .{ .from = step.id, .outcome = outcome.outcome, .target = outcome.target };
                transition_index += 1;
            };
            const maximum_step_executions = compilation.calculateExecutionLimit(steps) orelse return invalid();
            graph.* = .{
                .source_ordinal = item.source_ordinal,
                .shortcode = item.shortcode,
                .authority = .{
                    .allowed_capabilities = policy.allowed_capabilities,
                    .data_schemas = try compileDataSchemas(allocator, self.registry.data_schemas, invocation.contract.produces, steps),
                    .workflow_id = item.workflow_id,
                    .workflow_version = item.workflow_version,
                    .invocation_operation_id = item.invocation_operation_id,
                    .policy_profile_id = item.policy_profile_id,
                    .total_model_token_budget = policy.total_model_token_budget,
                    .start_step_id = item.start_step_id,
                    .invocation_outputs = invocation.contract.produces,
                    .resources = resources,
                    .steps = steps,
                    .transitions = transitions,
                    .maximum_step_executions = maximum_step_executions,
                },
            };
        }
        return graphs;
    }
};

fn compileDataSchemas(
    allocator: std.mem.Allocator,
    schemas: []const data.Schema,
    invocation_outputs: []const pipeline.DataKey,
    steps: []const compilation.CompiledStep,
) Error![]const data.Schema {
    var used = [_]bool{false} ** data.key_count;
    for (invocation_outputs) |key| used[@intFromEnum(key)] = true;
    for (steps) |step| {
        for (step.gates) |gate| {
            used[@intFromEnum(gate.evidence)] = true;
            for (gate.authority) |key| used[@intFromEnum(key)] = true;
        }
        inline for (.{ step.requires, step.optional, step.produces, step.replaces, step.invalidates }) |keys| {
            for (keys) |key| used[@intFromEnum(key)] = true;
        }
    }
    var count: usize = 0;
    for (used) |present| if (present) {
        count += 1;
    };
    const result = allocator.alloc(data.Schema, count) catch return invalid();
    var index: usize = 0;
    for (used, 0..) |present, key_index| {
        if (!present) continue;
        result[index] = data.find(schemas, @enumFromInt(key_index)) orelse return invalid();
        index += 1;
    }
    return result;
}

fn compileGates(allocator: std.mem.Allocator, registry: *const operation_registry.Registry, ids: []const []const u8) Error![]const @import("../../domain/workflow_gate.zig").Contract {
    const result = allocator.alloc(@import("../../domain/workflow_gate.zig").Contract, ids.len) catch return invalid();
    for (result, ids) |*destination, id| destination.* = (registry.resolveGate(.{ .bytes = id }) orelse return invalid()).*;
    return result;
}

fn compileResources(
    allocator: std.mem.Allocator,
    registry: *const operation_registry.Registry,
    result_schema_compiler: @import("../../ports/model_result_schema_compiler.zig").Compiler,
    item: definition.Definition,
    inventory_value: inventory.Inventory,
    manifest: inventory.ResourceManifest,
    captures: []const inventory.Capture,
) Error![]const compilation.CompiledResource {
    const resources = allocator.alloc(compilation.CompiledResource, item.resources.len) catch return invalid();
    for (item.resources, resources) |declared, *compiled| {
        const kind = deriveResourceKind(registry, item, declared.id) orelse return invalid();
        const binding = findResourceBinding(manifest.bindings, item.source_ordinal, declared.id) orelse return invalid();
        if (binding.resource_ordinal == 0 or binding.resource_ordinal > inventory_value.descriptors.len) return invalid();
        const descriptor = inventory_value.descriptors[binding.resource_ordinal - 1];
        const capture = findCapture(captures, binding.resource_ordinal) orelse return invalid();
        if (!std.mem.eql(u8, descriptor.path, declared.name) or descriptor.size == null or
            descriptor.size.? != capture.bytes.len) return invalid();
        compiled.* = .{ .id = declared.id, .content = switch (kind) {
            .result_schema => .{ .result_schema = result_schema_compiler.compile(allocator, capture.bytes) catch return invalid() },
            .prompt => .{ .prompt = capture.bytes },
            .example => .{ .example = capture.bytes },
            .data => .{ .data = capture.bytes },
        } };
        if (!std.mem.eql(u8, compiled.bytes(), capture.bytes)) return invalid();
    }
    return resources;
}

fn deriveResourceKind(
    registry: *const operation_registry.Registry,
    item: definition.Definition,
    id: workflow.WorkflowResourceId,
) ?operation.ResourceKind {
    var found: ?operation.ResourceKind = null;
    for (item.steps) |step| {
        const entry = registry.resolveOperation(step.operation_id) orelse return null;
        for (step.parameters) |parameter| {
            const descriptor = findDescriptor(entry.contract.parameters, parameter.id.bytes) orelse continue;
            if (descriptor.kind != .resource or parameter.value != .string or
                !std.mem.eql(u8, parameter.value.string, id.bytes)) continue;
            const kind = descriptor.resource_kind orelse return null;
            if (found != null and found.? != kind) return null;
            found = kind;
        }
    }
    return found;
}

fn compileParameters(
    allocator: std.mem.Allocator,
    contract: operation.Contract,
    declared: []const workflow.ParameterBinding,
    resources: []const compilation.CompiledResource,
) Error![]const compilation.CompiledParameter {
    if (declared.len > contract.parameters.len) return invalid();
    for (contract.parameters) |descriptor| {
        const value = findParameter(declared, descriptor.id);
        if (descriptor.required and value == null) return invalid();
    }
    const parameters = allocator.alloc(compilation.CompiledParameter, declared.len) catch return invalid();
    for (declared, parameters) |binding, *compiled| {
        const descriptor = findDescriptor(contract.parameters, binding.id.bytes) orelse return invalid();
        compiled.* = .{ .id = binding.id, .value = try compileParameter(descriptor, binding.value, resources) };
    }
    return parameters;
}

fn compileParameter(
    descriptor: operation.ParameterDescriptor,
    value: workflow.ParameterValue,
    resources: []const compilation.CompiledResource,
) Error!compilation.CompiledParameterValue {
    return switch (descriptor.kind) {
        .boolean => if (value == .boolean) .{ .boolean = value.boolean } else invalid(),
        .integer => if (value == .integer and value.integer >= descriptor.integer_min and value.integer <= descriptor.integer_max)
            .{ .integer = value.integer }
        else
            invalid(),
        .string => if (value == .string and value.string.len <= descriptor.string_max_bytes and allowed(descriptor.allowed_values, value.string))
            .{ .string = value.string }
        else
            invalid(),
        .enumeration => if (value == .string and allowedRequired(descriptor.allowed_values, value.string))
            .{ .enumeration = value.string }
        else
            invalid(),
        .registered_ref => if (value == .string and allowedRequired(descriptor.allowed_values, value.string))
            .{ .registered_ref = workflow.RegisteredRef.parse(value.string) orelse return invalid() }
        else
            invalid(),
        .resource => if (value == .string) resource: {
            const id = workflow.WorkflowResourceId.parse(value.string) orelse return invalid();
            const resource_value = findCompiledResource(resources, id.bytes) orelse return invalid();
            if (resource_value.kind() != descriptor.resource_kind.?) return invalid();
            break :resource .{ .resource = id };
        } else invalid(),
        .model_slot => if (value == .string and value.string.len <= descriptor.string_max_bytes)
            .{ .model_slot = provider_identity.ModelSlotId.parse(value.string) orelse return invalid() }
        else
            invalid(),
    };
}

fn resolveRetryAuthority(
    item: definition.Definition,
    operation_instance_id: workflow.WorkflowStepId,
    contract: operation.Contract,
    parameters: []const compilation.CompiledParameter,
) Error!?workflow_retry.CompiledAuthority {
    const descriptor = contract.retry_limit orelse return null;
    const parameter = findCompiledParameter(parameters, workflow_retry.parameter_id) orelse return invalid();
    if (parameter.value != .integer or parameter.value.integer < 0 or parameter.value.integer > descriptor.maximum) return invalid();
    return .{
        .workflow_id = item.workflow_id,
        .workflow_version = item.workflow_version,
        .operation_instance_id = operation_instance_id,
        .limit = .{ .value = @intCast(parameter.value.integer) },
    };
}

fn validateDeclaredOutcomes(
    expected: []const workflow.OutcomeTag,
    declared: []const workflow.OutcomeTransition,
    steps: []const workflow.DeclarativeStep,
    policy: operation.PolicyProfile,
) Error!void {
    if (expected.len != declared.len) return invalid();
    for (expected) |expected_outcome| {
        const transition = findOutcome(declared, expected_outcome) orelse return invalid();
        switch (transition.target) {
            .step => |target| if (!hasStep(steps, target.bytes)) return invalid(),
            .terminal => |terminal| if (terminal != expected_outcome or !containsOutcome(policy.allowed_terminal_outcomes, terminal)) return invalid(),
        }
    }
    for (declared) |transition| if (!containsOutcome(expected, transition.outcome)) return invalid();
}

fn findDescriptor(values: []const operation.ParameterDescriptor, id: []const u8) ?operation.ParameterDescriptor {
    for (values) |value| if (std.mem.eql(u8, value.id, id)) return value;
    return null;
}
fn findParameter(values: []const workflow.ParameterBinding, id: []const u8) ?workflow.ParameterBinding {
    for (values) |value| if (std.mem.eql(u8, value.id.bytes, id)) return value;
    return null;
}
fn findCompiledParameter(values: []const compilation.CompiledParameter, id: []const u8) ?compilation.CompiledParameter {
    for (values) |value| if (std.mem.eql(u8, value.id.bytes, id)) return value;
    return null;
}
fn findCompiledResource(values: []const compilation.CompiledResource, id: []const u8) ?compilation.CompiledResource {
    for (values) |value| if (std.mem.eql(u8, value.id.bytes, id)) return value;
    return null;
}
fn findResourceBinding(values: []const inventory.ResourceBinding, ordinal: u16, id: workflow.WorkflowResourceId) ?inventory.ResourceBinding {
    for (values) |value| if (value.definition_ordinal == ordinal and std.mem.eql(u8, value.resource_id.bytes, id.bytes)) return value;
    return null;
}
fn findCapture(values: []const inventory.Capture, ordinal: u16) ?inventory.Capture {
    for (values) |value| if (value.ordinal == ordinal) return value;
    return null;
}
fn findOutcome(values: []const workflow.OutcomeTransition, outcome: workflow.OutcomeTag) ?workflow.OutcomeTransition {
    for (values) |value| if (value.outcome == outcome) return value;
    return null;
}
fn hasStep(values: []const workflow.DeclarativeStep, id: []const u8) bool {
    for (values) |value| if (std.mem.eql(u8, value.id.bytes, id)) return true;
    return false;
}
fn containsOutcome(values: []const workflow.OutcomeTag, expected: workflow.OutcomeTag) bool {
    for (values) |value| if (value == expected) return true;
    return false;
}
fn containsString(values: []const []const u8, expected: []const u8) bool {
    for (values) |value| if (std.mem.eql(u8, value, expected)) return true;
    return false;
}
fn allowed(values: []const []const u8, candidate: []const u8) bool {
    return values.len == 0 or containsString(values, candidate);
}
fn allowedRequired(values: []const []const u8, candidate: []const u8) bool {
    return values.len != 0 and containsString(values, candidate);
}
fn invalid() Error {
    return error.WorkflowGraphCompileInvalid;
}
