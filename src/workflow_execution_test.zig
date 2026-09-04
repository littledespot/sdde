const std = @import("std");
const pipeline = @import("domain/pipeline.zig");
const execution = @import("domain/workflow_execution.zig");
const workflow = @import("domain/workflow.zig");
const compilation = @import("domain/workflow_compilation.zig");
const telemetry = @import("domain/telemetry.zig");
const operations = @import("ports/workflow_operation_registry.zig");
const barrier_port = @import("ports/telemetry_barrier.zig");
const runner_module = @import("application/workflow_pipeline_runner.zig");
const engine = @import("application/workflow_engine_orchestrator.zig");
const engine_bindings = @import("application/workflow_engine_child_bindings.zig");

test "generic engine preserves every YAML-compiled terminal outcome" {
    inline for (std.meta.tags(workflow.OutcomeTag)) |expected| {
        var control: OperationControl = .{ .outcome = expected };
        var barrier: FakeBarrier = .{};
        var graph = try testGraph();
        var registry = testRegistry(&control);
        var runner = runner_module.Runner.init(
            std.testing.allocator,
            selected(&graph),
            &registry,
            barrier.port(),
            .{},
            null,
        );
        defer runner.deinit();
        var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner };
        try std.testing.expectEqual(expected, engine.run(children.bindings()).execution);
        try std.testing.expectEqual(@as(usize, 1), barrier.calls);
    }
}

test "runner applies an operation delta before the telemetry barrier" {
    var control: OperationControl = .{ .outcome = .ok };
    var barrier: FakeBarrier = .{ .block = true };
    var graph = try testGraph();
    var registry = testRegistry(&control);
    var runner = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
    defer runner.deinit();
    var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner };
    try std.testing.expectEqual(workflow.OutcomeTag.blocked, engine.run(children.bindings()).execution);
    try std.testing.expectEqual(@as(usize, 1), barrier.calls);
}

test "runner follows a compiled bounded cycle and enforces its limit" {
    const loop_steps = [_]compilation.CompiledStep{.{
        .id = .{ .bytes = "run" },
        .operation_id = .{ .bytes = "test.operation@1" },
        .parameters = &.{},
        .requires = &.{},
        .produces = &.{},
        .replaces = &.{},
        .invalidates = &.{},
        .outcomes = &.{ .ok, .invalid },
        .side_effect = .none,
        .gates = &.{},
        .capabilities = &.{},
        .retry_authority = .{
            .workflow_id = .{ .bytes = "arbitrary-workflow" },
            .workflow_version = 1,
            .operation_instance_id = .{ .bytes = "run" },
            .limit = .{ .value = 2 },
        },
    }};
    const loop_transitions = [_]workflow.Transition{
        .{ .from = .{ .bytes = "run" }, .outcome = .ok, .target = .{ .terminal = .ok } },
        .{ .from = .{ .bytes = "run" }, .outcome = .invalid, .target = .{ .step = .{ .bytes = "run" } } },
    };

    var completes: OperationControl = .{ .outcome = .invalid, .scripted = &.{ .invalid, .ok } };
    var complete_barrier: FakeBarrier = .{};
    var complete_graph = try testGraph();
    complete_graph.authority.steps = &loop_steps;
    complete_graph.authority.transitions = &loop_transitions;
    complete_graph.authority.maximum_step_executions = 3;
    var complete_registry = testRegistry(&completes);
    completes.entries[1].contract.outcomes = &.{ .ok, .invalid };
    completes.entries[1].contract.retry_limit = .{ .maximum = 2 };
    var complete_runner = runner_module.Runner.init(std.testing.allocator, selected(&complete_graph), &complete_registry, complete_barrier.port(), .{}, null);
    defer complete_runner.deinit();
    var complete_children: TestEngineBindings = .{ .graph = &complete_graph, .runner = &complete_runner };
    try std.testing.expectEqual(workflow.OutcomeTag.ok, engine.run(complete_children.bindings()).execution);
    try std.testing.expectEqual(@as(usize, 2), completes.calls);
    try std.testing.expectEqual(@as(usize, 2), complete_barrier.calls);

    var exhausts: OperationControl = .{ .outcome = .invalid };
    var exhausted_barrier: FakeBarrier = .{};
    var exhausted_graph = complete_graph;
    var exhausted_registry = testRegistry(&exhausts);
    exhausts.entries[1].contract.outcomes = &.{ .ok, .invalid };
    exhausts.entries[1].contract.retry_limit = .{ .maximum = 2 };
    var exhausted_runner = runner_module.Runner.init(std.testing.allocator, selected(&exhausted_graph), &exhausted_registry, exhausted_barrier.port(), .{}, null);
    defer exhausted_runner.deinit();
    var exhausted_children: TestEngineBindings = .{ .graph = &exhausted_graph, .runner = &exhausted_runner };
    try std.testing.expectEqual(workflow.OutcomeTag.failed, engine.run(exhausted_children.bindings()).execution);
    try std.testing.expectEqual(@as(usize, 3), exhausts.calls);
    try std.testing.expectEqual(@as(usize, 3), exhausted_barrier.calls);

    var zero_steps = loop_steps;
    zero_steps[0].retry_authority.?.limit = .{ .value = 0 };
    var zero_graph = try testGraph();
    zero_graph.authority.steps = &zero_steps;
    zero_graph.authority.transitions = &loop_transitions;
    zero_graph.authority.maximum_step_executions = 1;
    var zero_control: OperationControl = .{ .outcome = .ok };
    var zero_barrier: FakeBarrier = .{};
    var zero_registry = testRegistry(&zero_control);
    zero_control.entries[1].contract.outcomes = &.{ .ok, .invalid };
    zero_control.entries[1].contract.retry_limit = .{ .maximum = 2 };
    var zero_runner = runner_module.Runner.init(std.testing.allocator, selected(&zero_graph), &zero_registry, zero_barrier.port(), .{}, null);
    defer zero_runner.deinit();
    var zero_children: TestEngineBindings = .{ .graph = &zero_graph, .runner = &zero_runner };
    try std.testing.expectEqual(workflow.OutcomeTag.ok, engine.run(zero_children.bindings()).execution);
    try std.testing.expectEqual(@as(usize, 1), zero_control.calls);
}

test "each workflow runner owns a fresh token ledger" {
    var control: OperationControl = .{ .outcome = .ok };
    var barrier: FakeBarrier = .{};
    var graph = try testGraph();
    var registry = testRegistry(&control);
    var first = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
    defer first.deinit();
    var second = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
    defer second.deinit();

    try std.testing.expect(first.tokenLedger() != second.tokenLedger());
    try std.testing.expectEqual(@as(u64, 1000), first.tokenLedger().totalTokenBudget().value);
    try std.testing.expectEqual(@as(u64, 0), first.tokenLedger().revision().value);
    try std.testing.expectEqual(@as(u64, 0), second.tokenLedger().revision().value);
}

test "runner exposes only resources referenced by the active compiled step" {
    const parameters = [_]compilation.CompiledParameter{.{
        .id = .{ .bytes = "prompt" },
        .value = .{ .resource = .{ .bytes = "prompt" } },
    }};
    const resources = [_]compilation.CompiledResource{
        .{ .id = .{ .bytes = "prompt" }, .kind = .prompt, .bytes = "visible" },
        .{ .id = .{ .bytes = "other" }, .kind = .prompt, .bytes = "not visible" },
    };
    var steps = test_steps;
    steps[0].parameters = &parameters;
    var graph = try testGraph();
    graph.authority.steps = &steps;
    graph.authority.resources = &resources;
    var control: OperationControl = .{ .outcome = .ok, .expected_resource_id = "prompt" };
    var barrier: FakeBarrier = .{};
    var registry = testRegistry(&control);
    var runner = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
    defer runner.deinit();
    var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner };
    try std.testing.expectEqual(workflow.OutcomeTag.ok, engine.run(children.bindings()).execution);
    try std.testing.expectEqual(@as(usize, 1), control.calls);
}

test "runner rejects an operation binding that differs from compiled authority" {
    var control: OperationControl = .{ .outcome = .ok };
    var barrier: FakeBarrier = .{};
    var graph = try testGraph();
    var registry = testRegistry(&control);
    control.entries[1].contract.outcomes = &.{.ok};
    var runner = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
    defer runner.deinit();
    var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner };
    try std.testing.expectEqual(workflow.OutcomeTag.failed, engine.run(children.bindings()).execution);
    try std.testing.expectEqual(@as(usize, 0), control.calls);
    try std.testing.expectEqual(@as(usize, 0), barrier.calls);
}

const TestEngineBindings = struct {
    graph: *const compilation.CompiledWorkflow,
    runner: *runner_module.Runner,

    fn bindings(self: *TestEngineBindings) engine_bindings.ChildBindings {
        return .{ .context = self, .vtable = &test_engine_vtable };
    }
    fn selectionOk(_: *anyopaque) engine_bindings.SelectionStepOutcome {
        return .ok;
    }
    fn preparationOk(_: *anyopaque) engine_bindings.PreparationOutcome {
        return .ok;
    }
    fn selectedGraph(context: *const anyopaque) *const compilation.CompiledWorkflow {
        const self: *const TestEngineBindings = @ptrCast(@alignCast(context));
        return self.graph;
    }
    fn invokeInvocation(context: *anyopaque) execution.Applied {
        const self: *TestEngineBindings = @ptrCast(@alignCast(context));
        return self.runner.bindings().invokeInvocation();
    }
    fn invokeStep(context: *anyopaque, id: workflow.WorkflowStepId) execution.Applied {
        const self: *TestEngineBindings = @ptrCast(@alignCast(context));
        return self.runner.bindings().invokeStep(id);
    }
};

fn selected(graph: *const compilation.CompiledWorkflow) execution.SelectedWorkflow {
    return .{
        .invocation = .{ .workflow_id = graph.authority.workflow_id, .arguments = &.{} },
        .graph = graph,
    };
}

const test_engine_vtable: engine_bindings.ChildBindings.VTable = .{
    .validate_operation_registry = TestEngineBindings.selectionOk,
    .parse_invocation = TestEngineBindings.selectionOk,
    .select_workflow = TestEngineBindings.selectionOk,
    .prepare_workflow = TestEngineBindings.preparationOk,
    .selected_graph = TestEngineBindings.selectedGraph,
    .invoke_invocation = TestEngineBindings.invokeInvocation,
    .invoke_step = TestEngineBindings.invokeStep,
};

const OperationControl = struct {
    outcome: workflow.OutcomeTag,
    scripted: []const workflow.OutcomeTag = &.{},
    expected_resource_id: ?[]const u8 = null,
    calls: usize = 0,
    entries: [2]operations.Entry = undefined,
};
const FakeBarrier = struct {
    calls: usize = 0,
    block: bool = false,
    fn port(self: *FakeBarrier) barrier_port.Barrier {
        return .{ .context = self, .process_fn = process };
    }
    fn process(context: *anyopaque, _: telemetry.WorkflowTelemetryFact) @import("domain/feature_log_stream.zig").Outcome {
        const self: *FakeBarrier = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (self.block) return .{ .blocked = .LOG_SINK_FAILURE };
        return .{ .persisted = .{ .segment_ordinal = 1, .sequence = self.calls, .bytes_written = 1, .flushed = true } };
    }
};

fn testRegistry(control: *OperationControl) operations.Registry {
    control.entries = .{
        .{
            .contract = .{ .id = "test.empty@1", .kind = .invocation, .outcomes = &.{.ok}, .side_effect = .none },
            .invoke_fn = invokeOperation,
        },
        .{
            .contract = .{
                .id = "test.operation@1",
                .kind = .step,
                .parameters = &.{.{
                    .id = "prompt",
                    .kind = .resource,
                    .required = false,
                    .workflow_definition_safe = true,
                    .resource_kind = .prompt,
                }},
                .outcomes = test_outcomes,
                .side_effect = .none,
            },
            .context = control,
            .invoke_fn = invokeOperation,
        },
    };
    return .{
        .operations = &control.entries,
        .policies = &.{.{ .id = "test.safe@1", .allowed_capabilities = &.{}, .allowed_terminal_outcomes = test_outcomes, .total_model_token_budget = .{ .value = 1000 } }},
        .gates = &.{},
        .capabilities = &.{},
    };
}

fn invokeOperation(context: ?*anyopaque, input: operations.Input) operations.Error!execution.Candidate {
    return switch (input) {
        .invocation => .{ .outcome = .ok, .delta = .{} },
        .step => |step_input| step: {
            const control: *OperationControl = @ptrCast(@alignCast(context.?));
            if (control.expected_resource_id) |expected| {
                if (step_input.resources.len != 1 or
                    !std.mem.eql(u8, step_input.resources[0].id.bytes, expected))
                {
                    return error.OperationExecutionFailed;
                }
            }
            const outcome = if (control.calls < control.scripted.len)
                control.scripted[control.calls]
            else
                control.outcome;
            control.calls += 1;
            var delta: pipeline.NodeDelta = .{};
            step_input.log.log(&delta, .{ .event_type = .action_completed }) catch return error.OperationExecutionFailed;
            break :step .{ .outcome = outcome, .delta = delta };
        },
    };
}

fn testGraph() !compilation.CompiledWorkflow {
    return .{
        .source_ordinal = 1,
        .shortcode = try telemetry.WorkflowShortcode.parse("TEST"),
        .authority = .{
            .workflow_id = .{ .bytes = "arbitrary-workflow" },
            .workflow_version = 1,
            .invocation_operation_id = .{ .bytes = "test.empty@1" },
            .policy_profile_id = .{ .bytes = "test.safe@1" },
            .total_model_token_budget = .{ .value = 1000 },
            .start_step_id = .{ .bytes = "run" },
            .invocation_outputs = &.{},
            .resources = &.{},
            .steps = &test_steps,
            .transitions = &test_transitions,
            .maximum_step_executions = 1,
        },
    };
}

const test_outcomes = std.meta.tags(workflow.OutcomeTag);
const test_steps = [_]compilation.CompiledStep{.{
    .id = .{ .bytes = "run" },
    .operation_id = .{ .bytes = "test.operation@1" },
    .parameters = &.{},
    .requires = &.{},
    .produces = &.{},
    .replaces = &.{},
    .invalidates = &.{},
    .outcomes = test_outcomes,
    .side_effect = .none,
    .gates = &.{},
    .capabilities = &.{},
    .retry_authority = null,
}};
const test_transitions = [_]workflow.Transition{
    .{ .from = .{ .bytes = "run" }, .outcome = .ok, .target = .{ .terminal = .ok } },
    .{ .from = .{ .bytes = "run" }, .outcome = .needs_user, .target = .{ .terminal = .needs_user } },
    .{ .from = .{ .bytes = "run" }, .outcome = .invalid, .target = .{ .terminal = .invalid } },
    .{ .from = .{ .bytes = "run" }, .outcome = .blocked, .target = .{ .terminal = .blocked } },
    .{ .from = .{ .bytes = "run" }, .outcome = .failed, .target = .{ .terminal = .failed } },
    .{ .from = .{ .bytes = "run" }, .outcome = .cancelled, .target = .{ .terminal = .cancelled } },
};
