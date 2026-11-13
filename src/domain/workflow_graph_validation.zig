const std = @import("std");
const pipeline = @import("pipeline.zig");
const workflow = @import("workflow.zig");
const definition = @import("workflow_definition.zig");
const compilation = @import("workflow_compilation.zig");
const workflow_retry = @import("workflow_retry.zig");
const kernel = @import("model_request_kernel.zig");
const operation_registry = @import("../ports/workflow_operation_registry.zig");

pub const Error = error{WorkflowGraphCompileInvalid};

/// Validates every compiled graph, including that each step of a contract with variants carries
/// exactly the variant its selector picks (ADR 0030 "Contract variants"): the compiler's output is
/// rechecked against the registry's contracts, not trusted.
pub fn validate(
    allocator: std.mem.Allocator,
    graphs: []const compilation.CompiledWorkflow,
    operations: *const operation_registry.Registry,
) Error!compilation.ValidatedGraphs {
    for (graphs) |graph| {
        if (!operations.stepsMatchVariants(graph.authority.steps)) return invalid();
        try validateGraph(allocator, graph);
    }
    return .{ .values = graphs };
}

const key_count = @typeInfo(pipeline.DataKey).@"enum".fields.len;
const KeyState = [key_count]bool;

fn validateGraph(allocator: std.mem.Allocator, graph: compilation.CompiledWorkflow) Error!void {
    const steps = graph.authority.steps;
    for (graph.authority.transitions) |transition| if (transition.target == .terminal and transition.target.terminal == .more) return invalid();
    if (workflow.OperationId.parse(graph.authority.invocation_operation_id.bytes) == null) return invalid();
    try validateDataSchemas(graph.authority);
    if (steps.len == 0 or steps.len > definition.max_steps or
        !compilation.publicationTerminates(graph.authority) or
        !compilation.validResourceBindings(graph.authority.resources) or
        graph.authority.maximum_step_executions != (compilation.calculateExecutionLimit(steps) orelse return invalid())) return invalid();
    for (steps) |step| {
        if (kernel.isKernel(step)) {
            // The kernel step's own contract is fixed by the domain; its stages are the steps
            // the stage-level checks below apply to (ADR 0030).
            if (!kernel.validProjection(step)) return invalid();
            for (step.request_stages) |stage| try validateStep(graph, stage.step);
        }
        try validateStep(graph, step);
    }
    const start = stepIndex(steps, graph.authority.start_step_id.bytes) orelse return invalid();
    try validateReachability(allocator, steps, graph.authority.transitions, start);
    try validateTerminalReachability(allocator, steps, graph.authority.transitions);
    try validateBoundedCycles(allocator, steps, graph.authority.transitions);
    try validateIterationResets(allocator, steps, graph.authority.transitions);
    @import("workflow_outcome_flow.zig").validate(allocator, graph.authority) catch return invalid();
    const flow = @import("workflow_data_flow.zig").analyze(allocator, graph.authority) catch return invalid();
    allocator.free(flow);
}

/// One compiled step's own checks. The validators a kernel step does not take are stated once,
/// at `kernel.takesSingleOperationValidators`.
fn validateStep(graph: compilation.CompiledWorkflow, step: compilation.CompiledStep) Error!void {
    const single_operation = kernel.takesSingleOperationValidators(step);
    if (!@import("workflow_iteration.zig").validProjection(step)) return invalid();
    if (single_operation and !@import("workflow_operation.zig").validRepair(step.repair_role, if (step.retry_authority) |value| value.scope else null, step.runner_accounting, step.side_effect)) return invalid();
    if (step.repair_role != .none and step.capabilities.len != 0) return invalid();
    if (!@import("workflow_outcome_association.zig").validDescriptor(step.outcome_association, step.requires, step.optional, step.produces, step.replaces, step.repair_role)) return invalid();
    if (workflow.WorkflowStepId.parse(step.id.bytes) == null or workflow.OperationId.parse(step.operation_id.bytes) == null) return invalid();
    if (single_operation and !@import("workflow_operation.zig").validAccounting(step.runner_accounting, step.requires, step.produces, step.side_effect, step.retry_authority != null)) return invalid();
    if (!@import("workflow_capability.zig").permits(graph.authority.allowed_capabilities, step.capabilities)) return invalid();
    if (!@import("workflow_model.zig").validProjection(step)) return invalid();
    if (single_operation) {
        if (!@import("workflow_model_request_lifecycle.zig").validProjection(step)) return invalid();
        if (!@import("workflow_provider_operation.zig").validProjection(step)) return invalid();
        if (!@import("workflow_provider_authorization.zig").validProjection(step)) return invalid();
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
/// assignment, and each execution of the step counts toward the workflow's execution ceiling.
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
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(arena.allocator(), &.{testGraph(&.{step}, &transitions)}, &no_operations));
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
    _ = try validate(a, &.{accepted}, &no_operations);
    for ([_]pipeline.SideEffect{ .none, .filesystem_read, .filesystem_write, .model_call, .workflow_publication }) |effect| {
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
            try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(a, &.{rejected}, &no_operations));
        }
    }
    var loop = terminal;
    loop[0].target = .{ .step = publication.id };
    accepted.authority.transitions = &loop;
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(a, &.{accepted}, &no_operations));
    var wrong_terminal = terminal;
    wrong_terminal[1].target = .{ .terminal = .ok };
    accepted.authority.transitions = &wrong_terminal;
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(a, &.{accepted}, &no_operations));
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
    _ = try validate(arena.allocator(), &.{graph}, &no_operations);
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
    step.iteration = .{ .kind = kind, .scope = .raw_engine_config, .progress = .engine_config };
    step.requires = if (kind == .initialize) &.{.raw_engine_config} else &.{ .raw_engine_config, .engine_config };
    step.produces = if (kind == .initialize) &.{.engine_config} else &.{};
    step.replaces = if (kind == .advance) &.{.engine_config} else &.{};
    return step;
}

fn iterationTestGraph(steps: []const compilation.CompiledStep, transitions: []const workflow.Transition) compilation.CompiledWorkflow {
    var graph = testGraph(steps, transitions);
    graph.authority.invocation_outputs = &.{.raw_engine_config};
    graph.authority.data_schemas = &.{
        .{ .key = .raw_engine_config, .version = 1, .type_name = "finite-scope", .maximum_bytes = null },
        .{ .key = .engine_config, .version = 1, .type_name = "finite-progress", .maximum_bytes = null },
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
    _ = try validate(arena.allocator(), &.{iterationTestGraph(&steps, &transitions)}, &no_operations);
    var failure_loop = transitions;
    failure_loop[2].target = .{ .terminal = .ok };
    failure_loop[3].target = .{ .step = steps[1].id };
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(arena.allocator(), &.{iterationTestGraph(&steps, &failure_loop)}, &no_operations));
    var unguarded = steps;
    unguarded[1].iteration = null;
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(arena.allocator(), &.{iterationTestGraph(&unguarded, &transitions)}, &no_operations));
}

test "native iteration initialization cannot replenish a cycle without an independent retry guard" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var reset = testStep("regenerate", 2);
    reset.requires = &.{.raw_engine_config};
    reset.replaces = &.{.raw_engine_config};
    reset.invalidates = &.{.engine_config};
    const steps = [_]compilation.CompiledStep{ iterationTestStep("initialize", .initialize), iterationTestStep("advance", .advance), reset };
    const transitions = [_]workflow.Transition{
        .{ .from = steps[0].id, .outcome = .ok, .target = .{ .step = steps[1].id } },
        .{ .from = steps[0].id, .outcome = .failed, .target = .{ .terminal = .failed } },
        .{ .from = steps[1].id, .outcome = .ok, .target = .{ .step = steps[2].id } },
        .{ .from = steps[1].id, .outcome = .failed, .target = .{ .terminal = .failed } },
        .{ .from = steps[2].id, .outcome = .ok, .target = .{ .step = steps[0].id } },
        .{ .from = steps[2].id, .outcome = .failed, .target = .{ .terminal = .failed } },
    };
    _ = try validate(arena.allocator(), &.{iterationTestGraph(&steps, &transitions)}, &no_operations);
    var unguarded = steps;
    unguarded[2].retry_authority = null;
    unguarded[2].parameters = &.{};
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(arena.allocator(), &.{iterationTestGraph(&unguarded, &transitions)}, &no_operations));
    var bypass = transitions;
    bypass[3].target = .{ .step = steps[0].id };
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(arena.allocator(), &.{iterationTestGraph(&steps, &bypass)}, &no_operations));
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
            0 => invalid_steps[0].iteration.?.scope = .engine_config,
            1 => invalid_steps[0].iteration.?.progress = .raw_engine_config,
            2 => invalid_steps[0].iteration.?.outcome = .more,
            3 => invalid_steps[0].iteration.?.kind = .advance,
            4 => invalid_steps[0].side_effect = .model_call,
            5 => invalid_steps[0].repair_role = .validate,
            else => unreachable,
        }
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(arena.allocator(), &.{iterationTestGraph(&invalid_steps, &transitions)}, &no_operations));
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
    _ = try validate(arena.allocator(), &.{testGraph(&guarded_steps, &transitions)}, &no_operations);

    var wrong_bound = testGraph(&guarded_steps, &transitions);
    wrong_bound.authority.maximum_step_executions -= 1;
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        validate(arena.allocator(), &.{wrong_bound}, &no_operations),
    );

    var wrong_retry_steps = guarded_steps;
    wrong_retry_steps[0].retry_authority.?.operation_instance_id = workflow.WorkflowStepId.parse("work").?;
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        validate(arena.allocator(), &.{testGraph(&wrong_retry_steps, &transitions)}, &no_operations),
    );

    var mismatched_retry_steps = guarded_steps;
    mismatched_retry_steps[0].retry_authority.?.limit = .{ .value = 1 };
    var mismatched_retry_graph = testGraph(&mismatched_retry_steps, &transitions);
    mismatched_retry_graph.authority.maximum_step_executions = compilation.calculateExecutionLimit(&mismatched_retry_steps).?;
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        validate(arena.allocator(), &.{mismatched_retry_graph}, &no_operations),
    );

    var unguarded_steps = guarded_steps;
    unguarded_steps[0].retry_authority = null;
    unguarded_steps[0].parameters = &.{};
    var unguarded_graph = testGraph(&unguarded_steps, &transitions);
    unguarded_graph.authority.maximum_step_executions = compilation.calculateExecutionLimit(&unguarded_steps).?;
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        validate(arena.allocator(), &.{unguarded_graph}, &no_operations),
    );
}

test "the compiled allowance gives each model attempt its one runaway re-send" {
    // ADR 0039: a re-send runs outside `retry-limit`, so an attempt-accounting
    // step's allowance covers one re-send for every attempt it admits.
    var counted = [_]compilation.CompiledStep{testStep("account", 2)};
    const ordinary = compilation.calculateExecutionLimit(&counted).?;
    const attempt_accounting: @FieldType(compilation.CompiledStep, "runner_accounting") = .increment_model_attempt;
    counted[0].runner_accounting = attempt_accounting;
    const with_resends = compilation.calculateExecutionLimit(&counted).?;
    // Operation scope: two corrections plus one re-send for each of three attempts.
    try std.testing.expectEqual(@as(usize, 1 + 2), ordinary);
    try std.testing.expectEqual(@as(usize, 1 + 2 + 3), with_resends);
}
