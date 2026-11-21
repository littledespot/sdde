const std = @import("std");
const pipeline = @import("pipeline.zig");
const workflow = @import("workflow.zig");
const definition = @import("workflow_definition.zig");
const compilation = @import("workflow_compilation.zig");
const operation = @import("workflow_operation.zig");
const inventory = @import("workflow_inventory.zig");
const operation_registry = @import("../ports/workflow_operation_registry.zig");
const schema_compiler = @import("../ports/model_result_schema_compiler.zig");
const provider_identity = @import("llm_provider_identity.zig");
const workflow_retry = @import("workflow_retry.zig");
const data = @import("pipeline_data.zig");
const kernel = @import("model_request_kernel.zig");
const rejection = @import("definition_rejection.zig");

pub const Error = error{WorkflowGraphCompileInvalid};

/// Compiles every validated definition into its graph from the registered operation contracts, the
/// captured resources and the result-schema compiler. The result is a candidate: graph validation
/// is a distinct step. A rejection records the check that failed, the definition's source ordinal and,
/// for a step's own checks, the step in `evidence`, when one is supplied.
pub fn compile(
    registry: *const operation_registry.Registry,
    result_schema_compiler: schema_compiler.Compiler,
    allocator: std.mem.Allocator,
    definitions: []const definition.Definition,
    inventory_value: inventory.Inventory,
    manifest: inventory.ResourceManifest,
    captures: []const inventory.Capture,
    evidence: ?*rejection.Slot,
) Error![]const compilation.CompiledWorkflow {
    if (!registry.validate()) return invalid();
    const graphs = allocator.alloc(compilation.CompiledWorkflow, definitions.len) catch return invalid();
    for (definitions, graphs) |source, *graph| {
        const ordinal = source.source_ordinal;
        const expanded = @import("workflow_subgraphs.zig").expand(allocator, source) catch return rejected(evidence, .subgraph_expansion, ordinal, null);
        var item = source;
        item.steps = expanded.steps;
        item.start_step_id = expanded.start;
        const invocation = registry.resolveOperation(item.invocation_operation_id) orelse return rejected(evidence, .invocation, ordinal, null);
        if (invocation.contract.kind != .invocation) return rejected(evidence, .invocation, ordinal, null);
        const policy = registry.resolvePolicy(item.policy_profile_id) orelse return rejected(evidence, .policy, ordinal, null);
        if (!hasStep(item.steps, item.start_step_id.bytes)) return rejected(evidence, .start_step, ordinal, null);

        const resources = compileResources(allocator, registry, result_schema_compiler, item, inventory_value, manifest, captures, evidence) catch return rejected(evidence, .compiled_resources, ordinal, null);
        const steps = allocator.alloc(compilation.CompiledStep, item.steps.len) catch return invalid();
        var transition_count: usize = 0;
        for (item.steps, steps) |declared, *compiled| {
            const subject = declared.id.bytes;
            const entry = registry.resolveOperation(declared.operation_id) orelse return rejected(evidence, .step_operation, ordinal, subject);
            if (entry.contract.kind != .step) return rejected(evidence, .step_operation, ordinal, subject);
            if (!@import("workflow_capability.zig").permits(policy.allowed_capabilities, entry.binding.capabilities())) return rejected(evidence, .step_capabilities, ordinal, subject);
            // The selector is read and checked first: everything after it, the remaining parameters,
            // the outcomes, the retry authority and the data effects, is checked against the one
            // variant it selects (ADR 0030 "Contract variants").
            const contract = selectDeclared(entry.contract, declared.parameters) orelse return rejected(evidence, .step_parameters, ordinal, subject);
            const parameters = compileParameters(allocator, contract, declared.parameters, resources) catch return rejected(evidence, .step_parameters, ordinal, subject);
            const retry_authority = resolveRetryAuthority(item, declared.id, contract, parameters) catch return rejected(evidence, .retry_authority, ordinal, subject);
            transition_count = std.math.add(usize, transition_count, declared.outcomes.len) catch return invalid();
            validateDeclaredOutcomes(contract.outcomes, declared.outcomes, item.steps, policy.*) catch return rejected(evidence, .declared_outcomes, ordinal, subject);
            compiled.* = buildStep(allocator, registry, declared.id, declared.source_chain, declared.operation_id, contract, entry.binding.capabilities(), parameters, retry_authority) catch return rejected(evidence, .step_operation, ordinal, subject);
            compiled.request_stages = compileRequestStages(allocator, registry, item, declared, entry, resources) catch return rejected(evidence, .request_stages, ordinal, subject);
        }

        const transitions = allocator.alloc(workflow.Transition, transition_count) catch return invalid();
        var transition_index: usize = 0;
        for (item.steps) |step| for (step.outcomes) |outcome| {
            transitions[transition_index] = .{ .from = step.id, .outcome = outcome.outcome, .target = outcome.target };
            transition_index += 1;
        };
        const maximum_step_executions = compilation.calculateExecutionLimit(steps) orelse return rejected(evidence, .execution_limit, ordinal, null);
        graph.* = .{
            .source_ordinal = item.source_ordinal,
            .shortcode = item.shortcode,
            .authority = .{
                .allowed_capabilities = policy.allowed_capabilities,
                .data_schemas = compileDataSchemas(allocator, registry.data_schemas, invocation.contract.produces, steps) catch return rejected(evidence, .data_schemas, ordinal, null),
                .workflow_id = item.workflow_id,
                .workflow_version = item.workflow_version,
                .invocation_operation_id = item.invocation_operation_id,
                .policy_profile_id = item.policy_profile_id,
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

/// The family's one error with the compile check and the definition (and step) recorded.
fn rejected(evidence: ?*rejection.Slot, rule: rejection.Rule, ordinal: u16, subject: ?[]const u8) Error {
    rejection.record(evidence, rule, ordinal, subject);
    return invalid();
}

/// The contract a declared step runs against: its registered contract, or the variant its selector
/// parameter names. A selector is a required closed enumeration, so a missing one, one of another
/// kind and one that names no variant all reject; a contract without variants takes none.
fn selectDeclared(contract: operation.Contract, declared: []const workflow.ParameterBinding) ?operation.Contract {
    const id = contract.selector orelse return contract.resolve(null);
    const binding = findParameter(declared, id) orelse return null;
    return switch (binding.value) {
        .string => |value| contract.resolve(value),
        .boolean, .integer => null,
    };
}

fn buildStep(
    allocator: std.mem.Allocator,
    registry: *const operation_registry.Registry,
    id: workflow.WorkflowStepId,
    source_chain: []const @import("workflow_source.zig").Entry,
    operation_id: workflow.OperationId,
    contract: operation.Contract,
    capabilities: []const []const u8,
    parameters: []const compilation.CompiledParameter,
    retry_authority: ?workflow_retry.CompiledAuthority,
) Error!compilation.CompiledStep {
    return .{
        .id = id,
        .source_chain = source_chain,
        .operation_id = operation_id,
        .parameters = parameters,
        .requires = contract.requires,
        .optional = contract.optional,
        .produces = contract.produces,
        .replaces = contract.replaces,
        .invalidates = contract.invalidates,
        .outcomes = contract.outcomes,
        .side_effect = contract.side_effect,
        .runner_accounting = contract.runner_accounting,
        .repair_role = contract.repair_role,
        .outcome_association = contract.outcome_association,
        .gates = try compileGates(allocator, registry, contract.gates),
        .capabilities = capabilities,
        .retry_authority = retry_authority,
        .iteration = contract.iteration,
        .model = if (contract.requiresModelBinding())
            @import("workflow_model.zig").resolve(parameters) orelse return invalid()
        else
            null,
    };
}

/// A `request-model` step also compiles its fixed stages (ADR 0030), each from its own stage
/// contract exactly as a workflow step compiles: the parameters the stage declares are the
/// step's own, plus the ones the engine fixes. A stage takes the step's id for retry and gate
/// identity and has no transition of its own.
fn compileRequestStages(
    allocator: std.mem.Allocator,
    registry: *const operation_registry.Registry,
    item: definition.Definition,
    declared: workflow.DeclarativeStep,
    entry: *const operation_registry.Entry,
    resources: []const compilation.CompiledResource,
) Error![]const compilation.RequestStage {
    if (entry.request_stages.len == 0) return &.{};
    const stages = allocator.alloc(compilation.RequestStage, entry.request_stages.len) catch return invalid();
    for (entry.request_stages, stages) |stage, *compiled| {
        var bindings: std.ArrayList(workflow.ParameterBinding) = .empty;
        for (stage.contract.parameters) |descriptor| {
            if (kernel.fixedParameter(stage.stage)) |fixed| if (std.mem.eql(u8, fixed.id, descriptor.id)) {
                bindings.append(allocator, .{ .id = workflow.WorkflowParameterId.parse(fixed.id) orelse return invalid(), .value = .{ .string = fixed.value } }) catch return invalid();
                continue;
            };
            if (findParameter(declared.parameters, descriptor.id)) |value| bindings.append(allocator, value) catch return invalid();
        }
        const parameters = try compileParameters(allocator, stage.contract, bindings.items, resources);
        const retry_authority = try resolveRetryAuthority(item, declared.id, stage.contract, parameters);
        compiled.* = .{
            .stage = stage.stage,
            .step = try buildStep(allocator, registry, declared.id, declared.source_chain, workflow.OperationId.parse(stage.contract.id) orelse return invalid(), stage.contract, stage.binding.capabilities(), parameters, retry_authority),
        };
    }
    return stages;
}

fn compileDataSchemas(
    allocator: std.mem.Allocator,
    schemas: []const data.Schema,
    invocation_outputs: []const pipeline.DataKey,
    steps: []const compilation.CompiledStep,
) Error![]const data.Schema {
    var used = [_]bool{false} ** data.key_count;
    for (invocation_outputs) |key| used[@intFromEnum(key)] = true;
    for (steps) |step| {
        markStepKeys(&used, step);
        for (step.request_stages) |stage| markStepKeys(&used, stage.step);
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

fn markStepKeys(used: *[data.key_count]bool, step: compilation.CompiledStep) void {
    for (step.gates) |gate| {
        used[@intFromEnum(gate.evidence)] = true;
        for (gate.authority) |key| used[@intFromEnum(key)] = true;
    }
    inline for (.{ step.requires, step.optional, step.produces, step.replaces, step.invalidates }) |keys| {
        for (keys) |key| used[@intFromEnum(key)] = true;
    }
}

fn compileGates(allocator: std.mem.Allocator, registry: *const operation_registry.Registry, ids: []const []const u8) Error![]const @import("workflow_gate.zig").Contract {
    const result = allocator.alloc(@import("workflow_gate.zig").Contract, ids.len) catch return invalid();
    for (result, ids) |*destination, id| destination.* = (registry.resolveGate(.{ .bytes = id }) orelse return invalid()).*;
    return result;
}

fn compileResources(
    allocator: std.mem.Allocator,
    registry: *const operation_registry.Registry,
    result_schema_compiler: schema_compiler.Compiler,
    item: definition.Definition,
    inventory_value: inventory.Inventory,
    manifest: inventory.ResourceManifest,
    captures: []const inventory.Capture,
    evidence: ?*rejection.Slot,
) Error![]const compilation.CompiledResource {
    const resources = allocator.alloc(compilation.CompiledResource, item.resources.len) catch return invalid();
    const kinds = allocator.alloc(?operation.ResourceKind, item.resources.len) catch return invalid();
    const bytes = allocator.alloc([]const u8, item.resources.len) catch return invalid();
    const canonical_aliases = allocator.alloc(?workflow.WorkflowResourceId, item.resources.len) catch return invalid();
    @memset(canonical_aliases, null);
    for (item.resources, 0..) |declared, index| {
        kinds[index] = try deriveResourceKind(registry, item, declared.id, evidence);
        const binding = findResourceBinding(manifest.bindings, item.source_ordinal, declared.id) orelse return rejected(evidence, .compiled_resources, item.source_ordinal, declared.id.bytes);
        if (binding.resource_ordinal == 0 or binding.resource_ordinal > inventory_value.descriptors.len) return rejected(evidence, .compiled_resources, item.source_ordinal, declared.id.bytes);
        const descriptor = inventory_value.descriptors[binding.resource_ordinal - 1];
        const capture = findCapture(captures, binding.resource_ordinal) orelse return rejected(evidence, .compiled_resources, item.source_ordinal, declared.id.bytes);
        if (!std.mem.eql(u8, descriptor.path, declared.name) or descriptor.size == null or
            descriptor.size.? != capture.bytes.len) return rejected(evidence, .compiled_resources, item.source_ordinal, declared.id.bytes);
        bytes[index] = capture.bytes;
    }
    // A composition's result alias is a reference to the same workflow-owned
    // schema resource; it need not also be passed directly to an operation.
    for (kinds, 0..) |kind, index| if (kind == .json_composition) {
        const canonical_alias = result_schema_compiler.compositionResultAlias(allocator, bytes[index]) catch return invalid();
        const canonical_index = for (item.resources, 0..) |resource, at| {
            if (std.mem.eql(u8, resource.id.bytes, canonical_alias.bytes)) break at;
        } else return invalid();
        if (kinds[canonical_index] != null and kinds[canonical_index] != .result_schema) return invalid();
        kinds[canonical_index] = .result_schema;
        canonical_aliases[index] = canonical_alias;
    };
    for (item.resources, resources, kinds, bytes) |declared, *compiled, kind, captured| {
        if (kind == .json_composition) continue;
        compiled.* = .{ .id = declared.id, .source_path = declared.name, .content = switch (kind orelse return rejected(evidence, .compiled_resources, item.source_ordinal, declared.id.bytes)) {
            .result_schema => .{ .result_schema = result_schema_compiler.compile(allocator, captured) catch return rejected(evidence, .compiled_resources, item.source_ordinal, declared.id.bytes) },
            .packet_guidance => .{ .packet_guidance = @import("packet_guidance.zig").compile(allocator, captured) catch return rejected(evidence, .compiled_resources, item.source_ordinal, declared.id.bytes) },
            .prompt => .{ .prompt = captured },
            .example => .{ .example = captured },
            .data => .{ .data = captured },
            .json_composition => unreachable,
        } };
    }
    for (item.resources, resources, kinds, bytes, canonical_aliases) |declared, *compiled, kind, captured, canonical_alias| if (kind == .json_composition) {
        const canonical_index = for (item.resources, 0..) |resource, at| {
            if (std.mem.eql(u8, resource.id.bytes, canonical_alias.?.bytes)) break at;
        } else return invalid();
        compiled.* = .{ .id = declared.id, .source_path = declared.name, .content = .{ .json_composition = result_schema_compiler.compileComposition(allocator, captured, resources[canonical_index].content.result_schema) catch return rejected(evidence, .compiled_resources, item.source_ordinal, declared.id.bytes) } };
    };
    for (resources, bytes) |compiled, captured| if (!std.mem.eql(u8, compiled.bytes(), captured)) return invalid();
    if (!compilation.validResourceBindings(resources)) return invalid();
    return resources;
}

fn deriveResourceKind(
    registry: *const operation_registry.Registry,
    item: definition.Definition,
    id: workflow.WorkflowResourceId,
    evidence: ?*rejection.Slot,
) Error!?operation.ResourceKind {
    var found: ?operation.ResourceKind = null;
    for (item.steps) |step| {
        // The kind is read from every step, so a step that fails here is the step's own fault, not the resource's.
        const entry = registry.resolveOperation(step.operation_id) orelse return rejected(evidence, .step_operation, item.source_ordinal, step.id.bytes);
        // A resource's kind is read from the descriptors of the variant the step selects.
        const contract = selectDeclared(entry.contract, step.parameters) orelse return rejected(evidence, .step_parameters, item.source_ordinal, step.id.bytes);
        for (step.parameters) |parameter| {
            const descriptor = findDescriptor(contract.parameters, parameter.id.bytes) orelse continue;
            if (descriptor.kind != .resource or parameter.value != .string or
                !std.mem.eql(u8, parameter.value.string, id.bytes)) continue;
            const kind = descriptor.resource_kind orelse return rejected(evidence, .compiled_resources, item.source_ordinal, id.bytes);
            if (found != null and found.? != kind) return rejected(evidence, .compiled_resources, item.source_ordinal, id.bytes);
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
        .scope = descriptor.scope,
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
            .terminal => |terminal| if (terminal == .more or terminal != expected_outcome or !containsOutcome(policy.allowed_terminal_outcomes, terminal)) return invalid(),
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
