const std = @import("std");
const pipeline = @import("pipeline.zig");
const workflow = @import("workflow.zig");
const definition = @import("workflow_definition.zig");
const compilation = @import("workflow_compilation.zig");
const workflow_retry = @import("workflow_retry.zig");
const kernel = @import("model_request_kernel.zig");
const operation_registry = @import("../ports/workflow_operation_registry.zig");
const rejection = @import("definition_rejection.zig");

pub const Error = error{WorkflowGraphCompileInvalid};

/// Validates every compiled graph, including that each step of a contract with variants carries
/// exactly the variant its selector picks (ADR 0030 "Contract variants"): the compiler's output is
/// rechecked against the registry's contracts, not trusted. A rejection records its stage, the graph's
/// source ordinal and, for a step's own checks, the step in `evidence`, when one is supplied.
pub fn validate(
    allocator: std.mem.Allocator,
    graphs: []const compilation.CompiledWorkflow,
    operations: *const operation_registry.Registry,
    evidence: ?*rejection.Slot,
) Error!compilation.ValidatedGraphs {
    for (graphs) |graph| {
        if (!operations.stepsMatchVariants(graph.authority.steps)) return reject(evidence, .operation_variants, graph, null);
        try validateGraph(allocator, graph, evidence);
    }
    return .{ .values = graphs };
}

const key_count = @typeInfo(pipeline.DataKey).@"enum".fields.len;
const KeyState = [key_count]bool;

fn validateGraph(allocator: std.mem.Allocator, graph: compilation.CompiledWorkflow, evidence: ?*rejection.Slot) Error!void {
    const steps = graph.authority.steps;
    for (graph.authority.transitions) |transition| if (transition.target == .terminal and transition.target.terminal == .more) return reject(evidence, .graph_shape, graph, null);
    if (workflow.OperationId.parse(graph.authority.invocation_operation_id.bytes) == null) return reject(evidence, .graph_shape, graph, null);
    validateDataSchemas(graph.authority) catch return reject(evidence, .data_schemas, graph, null);
    if (steps.len == 0 or steps.len > definition.max_steps or
        !compilation.publicationTerminates(graph.authority) or
        !compilation.validResourceBindings(graph.authority.resources) or
        graph.authority.maximum_step_executions != (compilation.calculateExecutionLimit(steps) orelse return reject(evidence, .graph_shape, graph, null))) return reject(evidence, .graph_shape, graph, null);
    for (steps) |step| {
        if (kernel.isKernel(step)) {
            // The kernel step's own contract is fixed by the domain; its stages are the steps
            // the stage-level checks below apply to (ADR 0030).
            if (!kernel.validProjection(step)) return reject(evidence, .step_contract, graph, step.id.bytes);
            for (step.request_stages) |stage| validateStep(graph, stage.step) catch return reject(evidence, .step_contract, graph, step.id.bytes);
        }
        validateStep(graph, step) catch return reject(evidence, .step_contract, graph, step.id.bytes);
    }
    const start = stepIndex(steps, graph.authority.start_step_id.bytes) orelse return reject(evidence, .graph_shape, graph, null);
    validateReachability(allocator, steps, graph.authority.transitions, start) catch return reject(evidence, .unreachable_step, graph, null);
    validateTerminalReachability(allocator, steps, graph.authority.transitions) catch return reject(evidence, .no_terminal_path, graph, null);
    validateBoundedCycles(allocator, steps, graph.authority.transitions) catch return reject(evidence, .unbounded_cycle, graph, null);
    validateIterationResets(allocator, steps, graph.authority.transitions) catch return reject(evidence, .iteration_reset, graph, null);
    @import("workflow_outcome_flow.zig").validate(allocator, graph.authority) catch return reject(evidence, .outcome_flow, graph, null);
    const flow = @import("workflow_data_flow.zig").analyze(allocator, graph.authority) catch return reject(evidence, .data_flow, graph, null);
    allocator.free(flow);
}

/// The family's one error, with the stage that raised it and the graph's source ordinal recorded.
fn reject(evidence: ?*rejection.Slot, rule: rejection.Rule, graph: compilation.CompiledWorkflow, subject: ?[]const u8) Error {
    rejection.record(evidence, rule, graph.source_ordinal, subject);
    return error.WorkflowGraphCompileInvalid;
}

/// One compiled step's own checks. The validators a kernel step does not take are stated once,
/// at `kernel.takesSingleOperationValidators`.
fn validateStep(graph: compilation.CompiledWorkflow, step: compilation.CompiledStep) Error!void {
    const single_operation = kernel.takesSingleOperationValidators(step);
    if (!@import("workflow_iteration.zig").validProjection(step)) return invalid();
    if (single_operation and !@import("workflow_operation.zig").validRepair(step.repair_role, if (step.retry_authority) |value| value.scope else null, step.runner_accounting, step.side_effect)) return invalid();
    if (step.repair_role != .none and step.capabilities.len != 0) return invalid();
    if (!@import("workflow_outcome_association.zig").validDescriptor(step.outcome_association, step.requires, step.optional, step.produces, step.replaces, step.repair_role, step.outcomes)) return invalid();
    if (workflow.WorkflowStepId.parse(step.id.bytes) == null or workflow.OperationId.parse(step.operation_id.bytes) == null) return invalid();
    if (single_operation and !@import("workflow_operation.zig").validAccounting(step.runner_accounting, step.requires, step.produces, step.side_effect, step.retry_authority != null)) return invalid();
    if (!@import("workflow_capability.zig").permits(graph.authority.allowed_capabilities, step.capabilities)) return invalid();
    if (!@import("workflow_model.zig").validProjection(step)) return invalid();
    if (single_operation) {
        if (!@import("workflow_model_request_lifecycle.zig").validProjection(step)) return invalid();
        if (!@import("workflow_provider_operation.zig").validProjection(step)) return invalid();
        if (!@import("workflow_provider_authorization.zig").validProjection(step)) return invalid();
        if (!@import("workflow_actor_authentication.zig").validProjection(step)) return invalid();
        if (!@import("workflow_model_invocation.zig").validProjection(step)) return invalid();
    }
    const retry_parameter = findParameter(step.parameters, workflow_retry.parameter_id);
    if (step.retry_authority) |authority| {
        if (!authority.isValid() or
            !std.mem.eql(u8, authority.workflow_id.bytes, graph.authority.workflow_id.bytes) or
            authority.workflow_version != graph.authority.workflow_version or
            !std.mem.eql(u8, authority.operation_instance_id.bytes, step.id.bytes) or
            retry_parameter == null or retry_parameter.?.value != .integer or
            retry_parameter.?.value.integer < 0 or
            authority.limit.value != retry_parameter.?.value.integer)
        {
            return invalid();
        }
    } else if (retry_parameter != null) {
        return invalid();
    }
}

fn validateDataSchemas(authority: compilation.SemanticAuthority) Error!void {
    var required: KeyState = @splat(false);
    for (authority.invocation_outputs) |key| required[@intFromEnum(key)] = true;
    for (authority.steps) |step| {
        markKeys(&required, step);
        for (step.request_stages) |stage| markKeys(&required, stage.step);
    }
    var seen: KeyState = @splat(false);
    for (authority.data_schemas) |schema| {
        const index = @intFromEnum(schema.key);
        if (!schema.valid() or seen[index] or !required[index]) return invalid();
        seen[index] = true;
    }
    if (!std.mem.eql(bool, &required, &seen)) return invalid();
}

fn markKeys(required: *KeyState, step: compilation.CompiledStep) void {
    for (step.gates) |gate| {
        required[@intFromEnum(gate.evidence)] = true;
        for (gate.authority) |key| required[@intFromEnum(key)] = true;
    }
    inline for (.{ step.requires, step.optional, step.produces, step.replaces, step.invalidates }) |keys| {
        for (keys) |key| required[@intFromEnum(key)] = true;
    }
}

fn validateReachability(
    allocator: std.mem.Allocator,
    steps: []const compilation.CompiledStep,
    transitions: []const workflow.Transition,
    start: usize,
) Error!void {
    const reached = allocator.alloc(bool, steps.len) catch return invalid();
    @memset(reached, false);
    var queue: std.ArrayList(usize) = .empty;
    queue.append(allocator, start) catch return invalid();
    reached[start] = true;
    var cursor: usize = 0;
    while (cursor < queue.items.len) : (cursor += 1) {
        const index = queue.items[cursor];
        for (transitions) |transition| {
            if (!std.mem.eql(u8, transition.from.bytes, steps[index].id.bytes)) continue;
            if (transition.target == .step) {
                const target = stepIndex(steps, transition.target.step.bytes) orelse return invalid();
                if (!reached[target]) {
                    reached[target] = true;
                    queue.append(allocator, target) catch return invalid();
                }
            }
        }
    }
    for (reached) |value| if (!value) return invalid();
}

fn validateTerminalReachability(
    allocator: std.mem.Allocator,
    steps: []const compilation.CompiledStep,
    transitions: []const workflow.Transition,
) Error!void {
    const reaches_terminal = allocator.alloc(bool, steps.len) catch return invalid();
    @memset(reaches_terminal, false);
    for (steps, 0..) |step, index| {
        for (transitions) |transition| {
            if (std.mem.eql(u8, transition.from.bytes, step.id.bytes) and transition.target == .terminal) {
                reaches_terminal[index] = true;
                break;
            }
        }
    }
    var changed = true;
    while (changed) {
        changed = false;
        for (steps, 0..) |step, index| {
            if (reaches_terminal[index]) continue;
            for (transitions) |transition| {
                if (!std.mem.eql(u8, transition.from.bytes, step.id.bytes) or transition.target != .step) continue;
                const target = stepIndex(steps, transition.target.step.bytes) orelse return invalid();
                if (reaches_terminal[target]) {
                    reaches_terminal[index] = true;
                    changed = true;
                    break;
                }
            }
        }
    }
    for (reaches_terminal) |value| if (!value) return invalid();
}

fn validateBoundedCycles(
    allocator: std.mem.Allocator,
    steps: []const compilation.CompiledStep,
    transitions: []const workflow.Transition,
) Error!void {
    const colors = allocator.alloc(u2, steps.len) catch return invalid();
    @memset(colors, 0);
    for (steps, 0..) |step, index| {
        if (guardsCycle(step) or colors[index] != 0) continue;
        try visitUnguarded(steps, transitions, index, colors);
    }
}

/// A step's retry authority bounds how often a cycle may revisit it. A `request-model` step's
/// authority does too, as the accounting step it replaces did: it counts attempts per request
/// assignment, and `calculateExecutionLimit` counts its allowance toward the workflow's execution
/// ceiling.
fn guardsCycle(step: compilation.CompiledStep) bool {
    return step.retry_authority != null;
}

fn visitUnguarded(
    steps: []const compilation.CompiledStep,
    transitions: []const workflow.Transition,
    index: usize,
    colors: []u2,
) Error!void {
    if (colors[index] == 1) return invalid();
    if (colors[index] == 2 or guardsCycle(steps[index])) return;
    colors[index] = 1;
    for (transitions) |transition| {
        if (!std.mem.eql(u8, transition.from.bytes, steps[index].id.bytes) or transition.target != .step) continue;
        if (steps[index].iteration) |iteration| {
            if (iteration.kind == .advance and transition.outcome == iteration.outcome) continue;
        }
        const target = stepIndex(steps, transition.target.step.bytes) orelse return invalid();
        if (!guardsCycle(steps[target])) try visitUnguarded(steps, transitions, target, colors);
    }
    colors[index] = 2;
}

/// An initializer cannot replenish finite native work through its own native
/// loop. Every return to initialization must consume an independent retry guard.
fn validateIterationResets(allocator: std.mem.Allocator, steps: []const compilation.CompiledStep, transitions: []const workflow.Transition) Error!void {
    const reached = allocator.alloc(bool, steps.len) catch return invalid();
    defer allocator.free(reached);
    for (steps, 0..) |step, index| {
        const iteration = step.iteration orelse continue;
        if (iteration.kind != .initialize) continue;
        @memset(reached, false);
        try visitIterationReset(steps, transitions, index, index, reached);
    }
}

fn visitIterationReset(steps: []const compilation.CompiledStep, transitions: []const workflow.Transition, initializer: usize, index: usize, reached: []bool) Error!void {
    if (reached[index] or guardsCycle(steps[index])) return;
    reached[index] = true;
    for (transitions) |transition| {
        if (!std.mem.eql(u8, transition.from.bytes, steps[index].id.bytes) or transition.target != .step) continue;
        const target = stepIndex(steps, transition.target.step.bytes) orelse return invalid();
        if (target == initializer) return invalid();
        try visitIterationReset(steps, transitions, initializer, target, reached);
    }
}

fn stepIndex(steps: []const compilation.CompiledStep, expected: []const u8) ?usize {
    for (steps, 0..) |step, index| if (std.mem.eql(u8, step.id.bytes, expected)) return index;
    return null;
}
fn findParameter(parameters: []const compilation.CompiledParameter, id: []const u8) ?compilation.CompiledParameter {
    for (parameters) |parameter| if (std.mem.eql(u8, parameter.id.bytes, id)) return parameter;
    return null;
}
fn invalid() Error {
    return error.WorkflowGraphCompileInvalid;
}

/// These tests build graphs by hand from steps of no registered operation; the variant recheck is
/// the registry tests' subject (`operation_variant_test.zig`).
const no_operations: operation_registry.Registry = .{ .operations = &.{}, .policies = &.{}, .gates = &.{} };

test "bounded progress can never be a compiled workflow terminal state" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var step = testStep("start", null);
    step.outcomes = &.{ .ok, .more };
    const transitions = [_]workflow.Transition{
        .{ .from = step.id, .outcome = .ok, .target = .{ .terminal = .ok } },
        .{ .from = step.id, .outcome = .more, .target = .{ .terminal = .more } },
    };
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(arena.allocator(), &.{testGraph(&.{step}, &transitions)}, &no_operations, null));
}

test "publication ends every outcome directly without a later pure or effectful operation" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var publication = testStep("publish", null);
    publication.side_effect = .workflow_publication;
    publication.outcomes = &.{ .ok, .needs_user, .failed };
    const terminal = [_]workflow.Transition{
        .{ .from = publication.id, .outcome = .ok, .target = .{ .terminal = .ok } },
        .{ .from = publication.id, .outcome = .needs_user, .target = .{ .terminal = .needs_user } },
        .{ .from = publication.id, .outcome = .failed, .target = .{ .terminal = .failed } },
    };
    var accepted = testGraph(&.{publication}, &terminal);
    accepted.authority.maximum_step_executions = compilation.calculateExecutionLimit(accepted.authority.steps).?;
    _ = try validate(a, &.{accepted}, &no_operations, null);
    for ([_]pipeline.SideEffect{ .none, .filesystem_read, .filesystem_write, .model_call, .workflow_publication, .actor_authentication }) |effect| {
        var after = testStep("later", null);
        after.side_effect = effect;
        for (0..terminal.len) |redirected| {
            var transitions = terminal ++ [_]workflow.Transition{
                .{ .from = after.id, .outcome = .ok, .target = .{ .terminal = .ok } },
                .{ .from = after.id, .outcome = .failed, .target = .{ .terminal = .failed } },
            };
            transitions[redirected].target = .{ .step = after.id };
            var rejected = testGraph(&.{ publication, after }, &transitions);
            rejected.authority.maximum_step_executions = compilation.calculateExecutionLimit(rejected.authority.steps).?;
            try std.testing.expect(!compilation.publicationTerminates(rejected.authority));
            try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(a, &.{rejected}, &no_operations, null));
        }
    }
    var loop = terminal;
    loop[0].target = .{ .step = publication.id };
    accepted.authority.transitions = &loop;
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(a, &.{accepted}, &no_operations, null));
    var wrong_terminal = terminal;
    wrong_terminal[1].target = .{ .terminal = .ok };
    accepted.authority.transitions = &wrong_terminal;
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(a, &.{accepted}, &no_operations, null));
}

test "a graph rejection records its stage, the graph's ordinal and, for a step's own checks, the step" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The progress outcome as a terminal is a graph-shape rejection, which names no step.
    var progress = testStep("start", null);
    progress.outcomes = &.{ .ok, .more };
    const to_progress = [_]workflow.Transition{
        .{ .from = progress.id, .outcome = .ok, .target = .{ .terminal = .ok } },
        .{ .from = progress.id, .outcome = .more, .target = .{ .terminal = .more } },
    };
    var shape: rejection.Slot = .{};
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(a, &.{testGraph(&.{progress}, &to_progress)}, &no_operations, &shape));
    try std.testing.expectEqual(rejection.Rule.graph_shape, shape.evidence.rule.?);
    try std.testing.expectEqual(@as(u16, 1), shape.evidence.ordinal.?);
    try std.testing.expect(shape.evidence.subject == null);
    // A step whose own iteration projection is wrong is a step-contract rejection, and names that step.
    const steps = [_]compilation.CompiledStep{iterationTestStep("initialize", .initialize)};
    const transitions = [_]workflow.Transition{
        .{ .from = steps[0].id, .outcome = .ok, .target = .{ .terminal = .ok } },
        .{ .from = steps[0].id, .outcome = .failed, .target = .{ .terminal = .failed } },
    };
    var invalid_steps = steps;
    invalid_steps[0].iteration.?.scope = .workflow_definition_registry;
    var contract: rejection.Slot = .{};
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(a, &.{iterationTestGraph(&invalid_steps, &transitions)}, &no_operations, &contract));
    try std.testing.expectEqual(rejection.Rule.step_contract, contract.evidence.rule.?);
    try std.testing.expectEqualStrings("initialize", contract.evidence.subject.?.text());
    // An accepted graph records nothing.
    var accepted: rejection.Slot = .{};
    _ = try validate(a, &.{iterationTestGraph(&steps, &transitions)}, &no_operations, &accepted);
    try std.testing.expect(accepted.evidence.rule == null);
}

test "separate workflow branches may each select their own terminal publication" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var select = testStep("select", null);
    select.outcomes = &.{ .ok, .more };
    var first = testStep("first-output", null);
    first.side_effect = .workflow_publication;
    var second = testStep("second-output", null);
    second.side_effect = .workflow_publication;
    const transitions = [_]workflow.Transition{
        .{ .from = select.id, .outcome = .ok, .target = .{ .step = first.id } },
        .{ .from = select.id, .outcome = .more, .target = .{ .step = second.id } },
        .{ .from = first.id, .outcome = .ok, .target = .{ .terminal = .ok } },
        .{ .from = first.id, .outcome = .failed, .target = .{ .terminal = .failed } },
        .{ .from = second.id, .outcome = .ok, .target = .{ .terminal = .ok } },
        .{ .from = second.id, .outcome = .failed, .target = .{ .terminal = .failed } },
    };
    var graph = testGraph(&.{ select, first, second }, &transitions);
    graph.authority.maximum_step_executions = compilation.calculateExecutionLimit(graph.authority.steps).?;
    _ = try validate(arena.allocator(), &.{graph}, &no_operations, null);
}

fn testStep(id: []const u8, retry_limit: ?u32) compilation.CompiledStep {
    return .{
        .id = workflow.WorkflowStepId.parse(id).?,
        .operation_id = workflow.OperationId.parse("core.noop").?,
        .parameters = if (retry_limit == null) &.{} else &test_retry_parameters,
        .requires = &.{},
        .produces = &.{},
        .replaces = &.{},
        .invalidates = &.{},
        .outcomes = &.{ .ok, .failed },
        .side_effect = .none,
        .gates = &.{},
        .capabilities = &.{},
        .retry_authority = if (retry_limit) |limit| .{
            .workflow_id = workflow.WorkflowId.parse("graph-test").?,
            .workflow_version = 1,
            .operation_instance_id = workflow.WorkflowStepId.parse(id).?,
            .limit = .{ .value = limit },
        } else null,
    };
}

const test_retry_parameters = [_]compilation.CompiledParameter{.{
    .id = workflow.WorkflowParameterId.parse(workflow_retry.parameter_id).?,
    .value = .{ .integer = 2 },
}};

fn testGraph(steps: []const compilation.CompiledStep, transitions: []const workflow.Transition) compilation.CompiledWorkflow {
    return .{
        .source_ordinal = 1,
        .shortcode = @import("telemetry.zig").WorkflowShortcode.parse("TEST") catch unreachable,
        .authority = .{
            .workflow_id = workflow.WorkflowId.parse("graph-test").?,
            .workflow_version = 1,
            .invocation_operation_id = workflow.OperationId.parse("core.empty").?,
            .policy_profile_id = workflow.RegisteredRef.parse("core.safe@1").?,
            .start_step_id = steps[0].id,
            .invocation_outputs = &.{},
            .resources = &.{},
            .steps = steps,
            .transitions = transitions,
            .maximum_step_executions = steps.len * 3,
        },
    };
}

fn iterationTestStep(id: []const u8, kind: @FieldType(@import("workflow_iteration.zig").Descriptor, "kind")) compilation.CompiledStep {
    var step = testStep(id, null);
    step.iteration = .{ .kind = kind, .scope = .workflow_operation_registry, .progress = .workflow_definition_registry };
    step.requires = if (kind == .initialize) &.{.workflow_operation_registry} else &.{ .workflow_operation_registry, .workflow_definition_registry };
    step.produces = if (kind == .initialize) &.{.workflow_definition_registry} else &.{};
    step.replaces = if (kind == .advance) &.{.workflow_definition_registry} else &.{};
    return step;
}

fn iterationTestGraph(steps: []const compilation.CompiledStep, transitions: []const workflow.Transition) compilation.CompiledWorkflow {
    var graph = testGraph(steps, transitions);
    graph.authority.invocation_outputs = &.{.workflow_operation_registry};
    graph.authority.data_schemas = &.{
        .{ .key = .workflow_operation_registry, .version = 1, .type_name = "finite-scope", .maximum_bytes = null },
        .{ .key = .workflow_definition_registry, .version = 1, .type_name = "finite-progress", .maximum_bytes = null },
    };
    graph.authority.maximum_step_executions = compilation.calculateExecutionLimit(steps).?;
    return graph;
}

test "native finite iteration guards only its declared advancing outcome" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const steps = [_]compilation.CompiledStep{ iterationTestStep("initialize", .initialize), iterationTestStep("advance", .advance) };
    const transitions = [_]workflow.Transition{
        .{ .from = steps[0].id, .outcome = .ok, .target = .{ .step = steps[1].id } },
        .{ .from = steps[0].id, .outcome = .failed, .target = .{ .terminal = .failed } },
        .{ .from = steps[1].id, .outcome = .ok, .target = .{ .step = steps[1].id } },
        .{ .from = steps[1].id, .outcome = .failed, .target = .{ .terminal = .failed } },
    };
    _ = try validate(arena.allocator(), &.{iterationTestGraph(&steps, &transitions)}, &no_operations, null);
    var failure_loop = transitions;
    failure_loop[2].target = .{ .terminal = .ok };
    failure_loop[3].target = .{ .step = steps[1].id };
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(arena.allocator(), &.{iterationTestGraph(&steps, &failure_loop)}, &no_operations, null));
    var unguarded = steps;
    unguarded[1].iteration = null;
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(arena.allocator(), &.{iterationTestGraph(&unguarded, &transitions)}, &no_operations, null));
}

test "native iteration initialization cannot replenish a cycle without an independent retry guard" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var reset = testStep("regenerate", 2);
    reset.requires = &.{.workflow_operation_registry};
    reset.replaces = &.{.workflow_operation_registry};
    reset.invalidates = &.{.workflow_definition_registry};
    const steps = [_]compilation.CompiledStep{ iterationTestStep("initialize", .initialize), iterationTestStep("advance", .advance), reset };
    const transitions = [_]workflow.Transition{
        .{ .from = steps[0].id, .outcome = .ok, .target = .{ .step = steps[1].id } },
        .{ .from = steps[0].id, .outcome = .failed, .target = .{ .terminal = .failed } },
        .{ .from = steps[1].id, .outcome = .ok, .target = .{ .step = steps[2].id } },
        .{ .from = steps[1].id, .outcome = .failed, .target = .{ .terminal = .failed } },
        .{ .from = steps[2].id, .outcome = .ok, .target = .{ .step = steps[0].id } },
        .{ .from = steps[2].id, .outcome = .failed, .target = .{ .terminal = .failed } },
    };
    _ = try validate(arena.allocator(), &.{iterationTestGraph(&steps, &transitions)}, &no_operations, null);
    var unguarded = steps;
    unguarded[2].retry_authority = null;
    unguarded[2].parameters = &.{};
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(arena.allocator(), &.{iterationTestGraph(&unguarded, &transitions)}, &no_operations, null));
    var bypass = transitions;
    bypass[3].target = .{ .step = steps[0].id };
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(arena.allocator(), &.{iterationTestGraph(&steps, &bypass)}, &no_operations, null));
}

test "compiled native iteration rejects undeclared authority and effects" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const steps = [_]compilation.CompiledStep{iterationTestStep("initialize", .initialize)};
    const transitions = [_]workflow.Transition{
        .{ .from = steps[0].id, .outcome = .ok, .target = .{ .terminal = .ok } },
        .{ .from = steps[0].id, .outcome = .failed, .target = .{ .terminal = .failed } },
    };
    for (0..6) |fault| {
        var invalid_steps = steps;
        switch (fault) {
            0 => invalid_steps[0].iteration.?.scope = .workflow_definition_registry,
            1 => invalid_steps[0].iteration.?.progress = .workflow_operation_registry,
            2 => invalid_steps[0].iteration.?.outcome = .more,
            3 => invalid_steps[0].iteration.?.kind = .advance,
            4 => invalid_steps[0].side_effect = .model_call,
            5 => invalid_steps[0].repair_role = .validate,
            else => unreachable,
        }
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(arena.allocator(), &.{iterationTestGraph(&invalid_steps, &transitions)}, &no_operations, null));
    }
}

test "accepts a guarded cycle and rejects the same unguarded cycle" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const guarded_steps = [_]compilation.CompiledStep{ testStep("guard", 2), testStep("work", null) };
    const transitions = [_]workflow.Transition{
        .{ .from = guarded_steps[0].id, .outcome = .ok, .target = .{ .step = guarded_steps[1].id } },
        .{ .from = guarded_steps[0].id, .outcome = .failed, .target = .{ .terminal = .failed } },
        .{ .from = guarded_steps[1].id, .outcome = .ok, .target = .{ .step = guarded_steps[0].id } },
        .{ .from = guarded_steps[1].id, .outcome = .failed, .target = .{ .terminal = .failed } },
    };
    _ = try validate(arena.allocator(), &.{testGraph(&guarded_steps, &transitions)}, &no_operations, null);

    var wrong_bound = testGraph(&guarded_steps, &transitions);
    wrong_bound.authority.maximum_step_executions -= 1;
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        validate(arena.allocator(), &.{wrong_bound}, &no_operations, null),
    );

    var wrong_retry_steps = guarded_steps;
    wrong_retry_steps[0].retry_authority.?.operation_instance_id = workflow.WorkflowStepId.parse("work").?;
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        validate(arena.allocator(), &.{testGraph(&wrong_retry_steps, &transitions)}, &no_operations, null),
    );

    var mismatched_retry_steps = guarded_steps;
    mismatched_retry_steps[0].retry_authority.?.limit = .{ .value = 1 };
    var mismatched_retry_graph = testGraph(&mismatched_retry_steps, &transitions);
    mismatched_retry_graph.authority.maximum_step_executions = compilation.calculateExecutionLimit(&mismatched_retry_steps).?;
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        validate(arena.allocator(), &.{mismatched_retry_graph}, &no_operations, null),
    );

    // Each other way the authority can disagree with its graph or its `retry-limit` parameter.
    const negative_limit = [_]compilation.CompiledParameter{.{ .id = test_retry_parameters[0].id, .value = .{ .integer = -1 } }};
    const textual_limit = [_]compilation.CompiledParameter{.{ .id = test_retry_parameters[0].id, .value = .{ .string = "2" } }};
    for (0..4) |fault| {
        var faulty_steps = guarded_steps;
        switch (fault) {
            0 => faulty_steps[0].retry_authority.?.workflow_id = workflow.WorkflowId.parse("other-graph").?,
            1 => faulty_steps[0].retry_authority.?.workflow_version = 2,
            2 => faulty_steps[0].parameters = &negative_limit,
            3 => faulty_steps[0].parameters = &textual_limit,
            else => unreachable,
        }
        try std.testing.expectError(
            error.WorkflowGraphCompileInvalid,
            validate(arena.allocator(), &.{testGraph(&faulty_steps, &transitions)}, &no_operations, null),
        );
    }

    // A `retry-limit` parameter with no authority, on a step no cycle needs to guard.
    const lone = [_]compilation.CompiledStep{testStep("lone", null)};
    const lone_transitions = [_]workflow.Transition{
        .{ .from = lone[0].id, .outcome = .ok, .target = .{ .terminal = .ok } },
        .{ .from = lone[0].id, .outcome = .failed, .target = .{ .terminal = .failed } },
    };
    var lone_graph = testGraph(&lone, &lone_transitions);
    lone_graph.authority.maximum_step_executions = compilation.calculateExecutionLimit(&lone).?;
    _ = try validate(arena.allocator(), &.{lone_graph}, &no_operations, null);
    var parameterized = lone;
    parameterized[0].parameters = &test_retry_parameters;
    var parameterized_graph = testGraph(&parameterized, &lone_transitions);
    parameterized_graph.authority.maximum_step_executions = compilation.calculateExecutionLimit(&parameterized).?;
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        validate(arena.allocator(), &.{parameterized_graph}, &no_operations, null),
    );

    var unguarded_steps = guarded_steps;
    unguarded_steps[0].retry_authority = null;
    unguarded_steps[0].parameters = &.{};
    var unguarded_graph = testGraph(&unguarded_steps, &transitions);
    unguarded_graph.authority.maximum_step_executions = compilation.calculateExecutionLimit(&unguarded_steps).?;
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        validate(arena.allocator(), &.{unguarded_graph}, &no_operations, null),
    );
}

/// A step that carries stages is a `request-model` step (ADR 0030): the one marker the ceiling reads.
fn kernelStep(id: []const u8, retry_limit: u32, stages: []const compilation.RequestStage) compilation.CompiledStep {
    var step = testStep(id, retry_limit);
    step.retry_authority.?.scope = .model_request;
    step.request_stages = stages;
    return step;
}

/// How many request assignments a request-scope retry authority counts, as the formula adds them.
fn requestKeys() usize {
    return @as(usize, workflow_retry.maximum_repair_keys) + workflow_retry.maximum_request_assignments;
}

test "a request-model step's allowance counts toward the compiled ceiling" {
    // ADR 0030 and ADR 0039: the step makes its attempts and their one runaway re-send each inside
    // one execution and counts them per request assignment: a revisit for another stage run, unit
    // owner, model operation or purpose restarts the count, and a revisit under the same assignment
    // continues it. Its allowance is counted like the attempt-accounting step it replaced.
    const stages = [_]compilation.RequestStage{.{ .stage = .invoke_model, .step = testStep("stage", null) }};
    for ([_]u32{ 0, 2 }) |limit| {
        const steps = [_]compilation.CompiledStep{ testStep("before", null), kernelStep("request", limit, &stages), testStep("after", null) };
        const allowance: usize = @intCast(kernel.attemptAllowance(.{ .value = limit }));
        try std.testing.expectEqual(steps.len * (1 + allowance * requestKeys()), compilation.calculateExecutionLimit(&steps).?);
    }
}

test "a request-model step's allowance adds to a repair-scope step's" {
    const stages = [_]compilation.RequestStage{.{ .stage = .invoke_model, .step = testStep("stage", null) }};
    var repair = testStep("repair", 1);
    repair.retry_authority.?.scope = .repair;
    const steps = [_]compilation.CompiledStep{ kernelStep("request", 2, &stages), repair };
    const kernel_term = @as(usize, @intCast(kernel.attemptAllowance(.{ .value = 2 }))) * requestKeys();
    const repair_term = (1 + 1) * @as(usize, workflow_retry.maximum_repair_keys);
    try std.testing.expectEqual(steps.len * (1 + kernel_term + repair_term), compilation.calculateExecutionLimit(&steps).?);
}

test "a step without request stages counts no runaway re-send, whatever its accounting" {
    // The re-send belongs to the `request-model` step; the attempt-accounting marker alone adds none.
    var counted = [_]compilation.CompiledStep{testStep("account", 2)};
    const ordinary = compilation.calculateExecutionLimit(&counted).?;
    const attempt_accounting: @FieldType(compilation.CompiledStep, "runner_accounting") = .increment_model_attempt;
    counted[0].runner_accounting = attempt_accounting;
    // Operation scope: two corrections.
    try std.testing.expectEqual(@as(usize, 1 + 2), ordinary);
    try std.testing.expectEqual(ordinary, compilation.calculateExecutionLimit(&counted).?);
    // Request scope: every assignment may revisit it three times, and still no re-send.
    counted[0].retry_authority.?.scope = .model_request;
    try std.testing.expectEqual(1 + 3 * requestKeys(), compilation.calculateExecutionLimit(&counted).?);
}

test "the ceiling is checked arithmetic: exact up to the step count a 64-bit usize sets, null past it" {
    const stages = [_]compilation.RequestStage{.{ .stage = .invoke_model, .step = testStep("stage", null) }};
    // Every step is a request-model step at the widest limit a descriptor can carry, the widest term the
    // formula has. The ceiling is `n * (1 + n * term)` with `term = 2 * (limit + 1) * keys`, and the
    // largest `n` whose ceiling fits is found with checked arithmetic of the test's own.
    const limit: u32 = std.math.maxInt(u32);
    const term = 2 * (@as(usize, limit) + 1) * requestKeys();
    var largest: usize = 1;
    while (ceilingOf(largest + 1, term) != null) largest += 1;
    // A graph has at most `definition.max_steps` steps, so no graph's ceiling reaches null: neither the
    // compiler nor `validate` can meet it (both refuse it rather than saturate).
    try std.testing.expect(largest > definition.max_steps);
    const steps = try std.testing.allocator.alloc(compilation.CompiledStep, largest + 1);
    defer std.testing.allocator.free(steps);
    @memset(steps, kernelStep("request", limit, &stages));
    try std.testing.expectEqual(ceilingOf(largest, term).?, compilation.calculateExecutionLimit(steps[0..largest]).?);
    try std.testing.expect(compilation.calculateExecutionLimit(steps) == null);
}

/// `n * (1 + n * term)`, or null when it does not fit `usize`.
fn ceilingOf(n: usize, term: usize) ?usize {
    const rounds = std.math.add(usize, 1, std.math.mul(usize, n, term) catch return null) catch return null;
    return std.math.mul(usize, n, rounds) catch null;
}
