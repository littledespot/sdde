const std = @import("std");
const pipeline = @import("domain/pipeline.zig");
const execution = @import("domain/workflow_execution.zig");
const workflow = @import("domain/workflow.zig");
const compilation = @import("domain/workflow_compilation.zig");
const telemetry = @import("domain/telemetry.zig");
const operations = @import("ports/workflow_operation_registry.zig");
const operation_bindings = @import("application/workflow_operation_binding.zig");
const barrier_port = @import("ports/telemetry_barrier.zig");
const runner_module = @import("application/workflow_pipeline_runner.zig");
const engine = @import("application/workflow_engine_orchestrator.zig");
const engine_bindings = @import("application/workflow_engine_child_bindings.zig");
const run_outcome = @import("domain/run_outcome.zig");
const finalization = @import("ports/feature_log_activation.zig");

test "generic engine preserves every YAML-compiled terminal outcome" {
    inline for (test_outcomes) |expected| {
        var control: OperationControl = .{ .state = .{ .outcome = expected } };
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
        try std.testing.expectEqual(expected, engine.run(children.bindings()).executionStatus().?);
        try std.testing.expectEqual(@as(usize, 1), barrier.calls);
    }
}

test "generic engine finalizes every terminal outcome and propagates close failures" {
    for (test_outcomes) |expected| {
        for ([_]bool{ false, true }) |fail| {
            var control: OperationControl = .{ .state = .{ .outcome = expected } };
            var barrier: FakeBarrier = .{};
            var graph = try testGraph();
            var registry = testRegistry(&control);
            var runner = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
            defer runner.deinit();
            var finalizer: FakeFinalizer = .{ .fail = fail };
            var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner, .finalizer = finalizer.port() };
            const result = engine.run(children.bindings());
            try std.testing.expectEqual(@as(usize, 1), finalizer.calls);
            try std.testing.expectEqualDeep(@as(run_outcome.Outcome, .{ .execution = expected }), finalizer.last.?);
            if (fail) {
                try std.testing.expectEqualDeep(@as(execution.Rejection, .{ .logging = .LOG_FLUSH_FAILURE }), result.execution_rejected);
            } else {
                try std.testing.expectEqualDeep(finalizer.last.?, result);
            }
        }
    }
}

test "generic engine finalizes selection and preparation failures before any operation" {
    for (0..3) |selection_index| {
        for ([_]engine_bindings.SelectionStepOutcome{ .invocation_invalid, .failed, .cancelled }) |terminal| {
            var control: OperationControl = .{ .state = .{ .outcome = .ok } };
            var barrier: FakeBarrier = .{};
            var graph = try testGraph();
            var registry = testRegistry(&control);
            var runner = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
            defer runner.deinit();
            var finalizer: FakeFinalizer = .{};
            var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner, .finalizer = finalizer.port() };
            children.selection_results[selection_index] = terminal;
            const result = engine.run(children.bindings());
            const expected: run_outcome.Outcome = switch (terminal) {
                .ok => unreachable,
                .invocation_invalid => .invocation_invalid,
                .failed => .{ .execution = .failed },
                .cancelled => .{ .execution = .cancelled },
            };
            try std.testing.expectEqualDeep(expected, result);
            try std.testing.expectEqualDeep(expected, finalizer.last.?);
            try std.testing.expectEqual(@as(usize, 1), finalizer.calls);
            try std.testing.expectEqual(@as(usize, 0), control.state.calls);
            try std.testing.expectEqual(selection_index + 1, children.selection_calls);
        }
    }
    for ([_]engine_bindings.PreparationOutcome{ .{ .failed = .LLM_PROVIDER_MODEL_BINDING_INVALID }, .cancelled }) |preparation| {
        var control: OperationControl = .{ .state = .{ .outcome = .ok } };
        var barrier: FakeBarrier = .{};
        var graph = try testGraph();
        var registry = testRegistry(&control);
        var runner = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
        defer runner.deinit();
        var finalizer: FakeFinalizer = .{};
        var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner, .finalizer = finalizer.port(), .preparation_result = preparation };
        const expected: run_outcome.Outcome = switch (preparation) {
            .ok => unreachable,
            .failed => |failure| .{ .bootstrap_failed = failure },
            .cancelled => .{ .execution = .cancelled },
        };
        try std.testing.expectEqualDeep(expected, engine.run(children.bindings()));
        try std.testing.expectEqualDeep(expected, finalizer.last.?);
        try std.testing.expectEqual(@as(usize, 1), finalizer.calls);
        try std.testing.expectEqual(@as(usize, 0), control.state.calls);
    }
}

test "publication effects finalize logging before the shared runner invokes any writer" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const output = @import("domain/workflow_output.zig");
    const values = @import("application/pipeline_values.zig");
    const prepared_schema = @import("application/workflow_output_binding.zig").prepared_schema;
    const feature = try @import("domain/feature_directory.zig").validate(a, .{ .bytes = "example" }, .{ .specs = "specs", .archive = "archive" });
    const prepared: output.Prepared = .{
        .terminal_outcome = .needs_user,
        .feature = .{ .selector = feature, .root_observation = .absent, .observation = .absent },
        .paths = try @import("domain/workflow_artifact_registry.zig").resolveFeaturePaths(a, .{ .specs = "specs", .archive = "archive", .workflows = "workflows" }, feature),
        .prior = .{ .state = null, .forms = &.{} },
        .files = &.{.{ .target = .{ .artifact = .specification }, .bytes = "incomplete" }},
    };
    for ([_]pipeline.SideEffect{ .workflow_publication, .filesystem_write, .none }) |effect| {
        for ([_]bool{ false, true }) |fail| {
            var control: OperationControl = .{ .state = .{ .outcome = .ok } };
            var barrier: FakeBarrier = .{};
            var graph = try testGraph();
            var steps = test_steps;
            steps[0].side_effect = effect;
            steps[0].requires = &.{prepared_schema.key};
            graph.authority.steps = &steps;
            graph.authority.data_schemas = &.{prepared_schema};
            var registry = testRegistry(&control);
            registry.data_schemas = graph.authority.data_schemas;
            control.entries[1].contract.side_effect = effect;
            control.entries[1].contract.requires = steps[0].requires;
            var runner = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
            defer runner.deinit();
            var finalizer: FakeFinalizer = .{ .fail = fail, .operations = &control.state };
            runner.publication_finalizer = finalizer.port();
            try std.testing.expectEqualDeep(@as(execution.Applied, .{ .outcome = .ok }), runner.bindings().invokeInvocation());
            var delta: pipeline.NodeDelta = .{};
            delta.data_writes[@intFromEnum(prepared_schema.key)] = try values.create(std.testing.allocator, prepared_schema, output.Prepared, prepared);
            defer runner.envelope.discard(&delta);
            try runner.envelope.apply(.{ .id = "test.prepare", .kind = .action, .requires = &.{}, .produces = &.{prepared_schema.key}, .side_effect = .none }, &delta, .ok);
            const result = runner.bindings().invokeStep(steps[0].id);
            const publication = effect == .workflow_publication;
            try std.testing.expectEqual(@as(usize, if (publication) 1 else 0), finalizer.calls);
            try std.testing.expectEqual(@as(usize, 0), finalizer.operations_at_finish);
            if (publication and fail) {
                try std.testing.expectEqualDeep(@as(execution.Rejection, .{ .logging = .LOG_FLUSH_FAILURE }), result.rejected);
                try std.testing.expectEqual(@as(usize, 0), control.state.calls);
                try std.testing.expectEqual(@as(usize, 0), barrier.calls);
            } else {
                try std.testing.expectEqualDeep(@as(execution.Applied, .{ .outcome = .ok }), result);
                try std.testing.expectEqual(@as(usize, 1), control.state.calls);
            }
        }
    }
    try std.testing.expectEqual(pipeline.SideEffect.workflow_publication, @import("actions/workflow/publish_workflow_output.zig").Action.contract.side_effect);
}

test "maximum graph validates executes every operation and rejects cycles and overflow" {
    const definition = @import("domain/workflow_definition.zig");
    const validate = @import("actions/workflow/validate_compiled_workflow_graphs.zig");
    const maximum = definition.max_steps;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const steps = try a.alloc(compilation.CompiledStep, maximum + 1);
    const transitions = try a.alloc(workflow.Transition, maximum * 2);
    for (steps, 0..) |*step, index| {
        step.* = test_steps[0];
        step.id = workflow.WorkflowStepId.parse(try std.fmt.allocPrint(a, "operation-{d}", .{index})).?;
    }
    for (steps[0..maximum], 0..) |step, index| {
        transitions[index * 2] = .{
            .from = step.id,
            .outcome = .ok,
            .target = if (index + 1 == maximum) .{ .terminal = .ok } else .{ .step = steps[index + 1].id },
        };
        // Each node has a terminal edge, while the success chain exercises the
        // complete bound and the cycle validator's maximum recursion depth.
        transitions[index * 2 + 1] = .{ .from = step.id, .outcome = .failed, .target = .{ .terminal = .failed } };
    }
    var graph = try testGraph();
    graph.authority.start_step_id = steps[0].id;
    graph.authority.steps = steps[0..maximum];
    graph.authority.transitions = transitions;
    graph.authority.maximum_step_executions = compilation.calculateExecutionLimit(graph.authority.steps).?;
    _ = try (validate.Action{}).execute(a, &.{graph});
    var control: OperationControl = .{ .state = .{ .outcome = .ok } };
    var barrier: FakeBarrier = .{};
    var registry = testRegistry(&control);
    var runner = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
    defer runner.deinit();
    var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner };
    try std.testing.expectEqual(workflow.OutcomeTag.ok, engine.run(children.bindings()).executionStatus().?);
    try std.testing.expectEqual(maximum, control.state.calls);
    try std.testing.expectEqual(maximum, barrier.calls);
    try std.testing.expectEqual(maximum, runner.retry_execution_counts.len);
    try std.testing.expectEqual(@as(u128, 0), runner.token_accounting.current().committed());

    transitions[(maximum - 1) * 2].target = .{ .step = steps[0].id };
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, (validate.Action{}).execute(a, &.{graph}));
    transitions[(maximum - 1) * 2].target = .{ .terminal = .ok };
    graph.authority.steps = steps;
    graph.authority.maximum_step_executions = compilation.calculateExecutionLimit(steps).?;
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, (validate.Action{}).execute(a, &.{graph}));

    var bounded = test_steps[0];
    bounded.retry_authority = .{
        .workflow_id = graph.authority.workflow_id,
        .workflow_version = graph.authority.workflow_version,
        .operation_instance_id = bounded.id,
        .limit = .{ .value = std.math.maxInt(u32) },
        .scope = .model_request,
    };
    @memset(steps[0..maximum], bounded);
    try std.testing.expect(compilation.calculateExecutionLimit(steps[0..maximum]) == null);
}

test "rerunning an abandoned workflow executes every step again from compiled start" {
    inline for (.{ .failed, .blocked, .cancelled, .needs_user }) |terminal| {
        var steps = [_]compilation.CompiledStep{test_steps[0]} ** 3;
        for (&steps, [_][]const u8{ "first", "second", "last" }) |*step, id| step.id = .{ .bytes = id };
        const transitions = [_]workflow.Transition{
            .{ .from = .{ .bytes = "first" }, .outcome = .ok, .target = .{ .step = .{ .bytes = "second" } } },
            .{ .from = .{ .bytes = "second" }, .outcome = .ok, .target = .{ .step = .{ .bytes = "last" } } },
            .{ .from = .{ .bytes = "second" }, .outcome = terminal, .target = .{ .terminal = terminal } },
            .{ .from = .{ .bytes = "last" }, .outcome = .ok, .target = .{ .terminal = .ok } },
        };
        var graph = try testGraph();
        graph.authority.start_step_id = steps[0].id;
        graph.authority.steps = &steps;
        graph.authority.transitions = &transitions;
        graph.authority.maximum_step_executions = steps.len;
        {
            var control: OperationControl = .{ .state = .{
                .outcome = terminal,
                .scripted = &.{ .ok, terminal },
                .expected_steps = &.{ "first", "second" },
            } };
            var barrier: FakeBarrier = .{};
            var registry = testRegistry(&control);
            var runner = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
            defer runner.deinit();
            var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner };
            try std.testing.expectEqual(@as(workflow.OutcomeTag, terminal), engine.run(children.bindings()).executionStatus().?);
            try std.testing.expectEqual(@as(usize, 2), control.state.calls);
        }
        var control: OperationControl = .{ .state = .{ .outcome = .ok, .expected_steps = &.{ "first", "second", "last" } } };
        var barrier: FakeBarrier = .{};
        var registry = testRegistry(&control);
        var runner = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
        defer runner.deinit();
        var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner };
        try std.testing.expectEqual(workflow.OutcomeTag.ok, engine.run(children.bindings()).executionStatus().?);
        try std.testing.expectEqual(@as(usize, 3), control.state.calls);
    }
}

test "runner applies an operation delta before the telemetry barrier" {
    var control: OperationControl = .{ .state = .{ .outcome = .ok } };
    var barrier: FakeBarrier = .{ .block = true };
    var graph = try testGraph();
    var registry = testRegistry(&control);
    var runner = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
    defer runner.deinit();
    var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner };
    try std.testing.expectEqual(workflow.OutcomeTag.blocked, engine.run(children.bindings()).executionStatus().?);
    try std.testing.expectEqual(@as(usize, 1), barrier.calls);
}

test "runner follows a compiled bounded cycle and enforces its limit" {
    inline for ([_]workflow.OutcomeTag{ .invalid, .more }) |retry_outcome| {
        const loop_steps = [_]compilation.CompiledStep{.{
            .id = .{ .bytes = "run" },
            .operation_id = .{ .bytes = "test.operation" },
            .parameters = &.{},
            .requires = &.{},
            .produces = &.{},
            .replaces = &.{},
            .invalidates = &.{},
            .outcomes = &.{ .ok, retry_outcome, .failed },
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
            .{ .from = .{ .bytes = "run" }, .outcome = retry_outcome, .target = .{ .step = .{ .bytes = "run" } } },
            // A runner rejection must never follow the operation's failure edge.
            .{ .from = .{ .bytes = "run" }, .outcome = .failed, .target = .{ .terminal = .ok } },
        };

        var completes: OperationControl = .{ .state = .{ .outcome = retry_outcome, .scripted = &.{ retry_outcome, .ok } } };
        var complete_barrier: FakeBarrier = .{};
        var complete_graph = try testGraph();
        complete_graph.authority.steps = &loop_steps;
        complete_graph.authority.transitions = &loop_transitions;
        complete_graph.authority.maximum_step_executions = 4;
        var complete_registry = testRegistry(&completes);
        completes.entries[1].contract.outcomes = &.{ .ok, retry_outcome, .failed };
        completes.entries[1].contract.retry_limit = .{ .maximum = 2 };
        completes.entries[1].contract.parameters = &retry_parameters;
        var complete_runner = runner_module.Runner.init(std.testing.allocator, selected(&complete_graph), &complete_registry, complete_barrier.port(), .{}, null);
        defer complete_runner.deinit();
        var complete_children: TestEngineBindings = .{ .graph = &complete_graph, .runner = &complete_runner };
        try std.testing.expectEqual(workflow.OutcomeTag.ok, engine.run(complete_children.bindings()).executionStatus().?);
        try std.testing.expectEqual(@as(usize, 2), completes.state.calls);
        try std.testing.expectEqual(@as(usize, 2), complete_barrier.calls);

        var exhausts: OperationControl = .{ .state = .{ .outcome = retry_outcome } };
        var exhausted_barrier: FakeBarrier = .{};
        var exhausted_graph = complete_graph;
        var exhausted_registry = testRegistry(&exhausts);
        exhausts.entries[1].contract.outcomes = &.{ .ok, retry_outcome, .failed };
        exhausts.entries[1].contract.retry_limit = .{ .maximum = 2 };
        exhausts.entries[1].contract.parameters = &retry_parameters;
        var exhausted_runner = runner_module.Runner.init(std.testing.allocator, selected(&exhausted_graph), &exhausted_registry, exhausted_barrier.port(), .{}, null);
        defer exhausted_runner.deinit();
        var exhausted_children: TestEngineBindings = .{ .graph = &exhausted_graph, .runner = &exhausted_runner };
        const exhausted = engine.run(exhausted_children.bindings());
        try std.testing.expectEqual(workflow.OutcomeTag.failed, exhausted.executionStatus().?);
        try std.testing.expectEqualStrings("RetryLimitExhausted", exhausted.execution_rejected.diagnostic());
        const diagnostic = exhausted.execution_rejected.retry_limit;
        try std.testing.expectEqualStrings("run", diagnostic.operation().bytes);
        try std.testing.expectEqual(@as(u32, 2), diagnostic.limit.value);
        try std.testing.expectEqual(@as(u64, 3), diagnostic.completed_executions);
        try std.testing.expectEqual(@as(usize, 3), exhausts.state.calls);
        try std.testing.expectEqual(@as(usize, 3), exhausted_barrier.calls);

        var zero_steps = loop_steps;
        zero_steps[0].retry_authority.?.limit = .{ .value = 0 };
        var zero_graph = try testGraph();
        zero_graph.authority.steps = &zero_steps;
        zero_graph.authority.transitions = &loop_transitions;
        zero_graph.authority.maximum_step_executions = 1;
        var zero_control: OperationControl = .{ .state = .{ .outcome = .ok } };
        var zero_barrier: FakeBarrier = .{};
        var zero_registry = testRegistry(&zero_control);
        zero_control.entries[1].contract.outcomes = &.{ .ok, retry_outcome, .failed };
        zero_control.entries[1].contract.retry_limit = .{ .maximum = 2 };
        zero_control.entries[1].contract.parameters = &retry_parameters;
        var zero_runner = runner_module.Runner.init(std.testing.allocator, selected(&zero_graph), &zero_registry, zero_barrier.port(), .{}, null);
        defer zero_runner.deinit();
        var zero_children: TestEngineBindings = .{ .graph = &zero_graph, .runner = &zero_runner };
        try std.testing.expectEqual(workflow.OutcomeTag.ok, engine.run(zero_children.bindings()).executionStatus().?);
        try std.testing.expectEqual(@as(usize, 1), zero_control.state.calls);
    }
}

test "each workflow runner owns a fresh token ledger" {
    var control: OperationControl = .{ .state = .{ .outcome = .ok } };
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
        .{ .id = .{ .bytes = "prompt" }, .content = .{ .prompt = "visible" } },
        .{ .id = .{ .bytes = "other" }, .content = .{ .prompt = "not visible" } },
    };
    var steps = test_steps;
    steps[0].parameters = &parameters;
    var graph = try testGraph();
    graph.authority.steps = &steps;
    graph.authority.resources = &resources;
    var control: OperationControl = .{ .state = .{ .outcome = .ok, .expected_resource_id = "prompt" } };
    var barrier: FakeBarrier = .{};
    var registry = testRegistry(&control);
    var runner = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
    defer runner.deinit();
    var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner };
    try std.testing.expectEqual(workflow.OutcomeTag.ok, engine.run(children.bindings()).executionStatus().?);
    try std.testing.expectEqual(@as(usize, 1), control.state.calls);
}

test "runner rejects an operation binding that differs from compiled authority" {
    var control: OperationControl = .{ .state = .{ .outcome = .ok } };
    var barrier: FakeBarrier = .{};
    var graph = try testGraph();
    var registry = testRegistry(&control);
    control.entries[1].contract.outcomes = &.{.ok};
    var runner = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
    defer runner.deinit();
    var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner };
    try std.testing.expectEqual(workflow.OutcomeTag.failed, engine.run(children.bindings()).executionStatus().?);
    try std.testing.expectEqual(@as(usize, 0), control.state.calls);
    try std.testing.expectEqual(@as(usize, 0), barrier.calls);
}

test "unexpected binding failure never follows a declared transition to clarification" {
    var steps = [_]compilation.CompiledStep{test_steps[0]} ** 2;
    steps[0].id = .{ .bytes = "first" };
    steps[1].id = .{ .bytes = "later" };
    const transitions = [_]workflow.Transition{
        .{ .from = steps[0].id, .outcome = .failed, .target = .{ .step = steps[1].id } },
        .{ .from = steps[1].id, .outcome = .ok, .target = .{ .terminal = .needs_user } },
    };
    var graph = try testGraph();
    graph.authority.steps = &steps;
    graph.authority.start_step_id = steps[0].id;
    graph.authority.transitions = &transitions;
    graph.authority.maximum_step_executions = 2;
    var control: OperationControl = .{ .state = .{ .outcome = .ok, .fail_call = 1 } };
    var registry = testRegistry(&control);
    var barrier: FakeBarrier = .{};
    var runner = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
    defer runner.deinit();
    var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner };
    const result = engine.run(children.bindings());
    try std.testing.expectEqualDeep(@as(execution.Rejection, .{ .operation_failed = error.OperationExecutionFailed }), result.execution_rejected);
    try std.testing.expectEqual(.failed, result.executionStatus().?);
    try std.testing.expectEqual(@as(usize, 1), control.state.calls);
    try std.testing.expectEqual(@as(usize, 0), barrier.calls);
}

test "runner contract rejections cannot enter invalid or failed recovery leading to clarification" {
    inline for (std.meta.tags(DeltaFault)) |fault| {
        var steps = [_]compilation.CompiledStep{test_steps[0]} ** 2;
        steps[0].id = .{ .bytes = "first" };
        steps[1].id = .{ .bytes = "recovery" };
        for (&steps) |*step| step.produces = &.{test_value_schema.key};
        const transitions = [_]workflow.Transition{
            .{ .from = steps[0].id, .outcome = .invalid, .target = .{ .step = steps[1].id } },
            .{ .from = steps[0].id, .outcome = .failed, .target = .{ .step = steps[1].id } },
            .{ .from = steps[1].id, .outcome = .ok, .target = .{ .terminal = .needs_user } },
        };
        var graph = try testGraph();
        graph.authority.steps = &steps;
        graph.authority.start_step_id = steps[0].id;
        graph.authority.transitions = &transitions;
        graph.authority.maximum_step_executions = 2;
        graph.authority.data_schemas = &.{test_value_schema};
        var control: OperationControl = .{ .state = .{ .outcome = .ok, .delta_fault = fault } };
        var registry = testRegistry(&control);
        registry.data_schemas = graph.authority.data_schemas;
        control.entries[1].contract.produces = steps[0].produces;
        var barrier: FakeBarrier = .{};
        var runner = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
        defer runner.deinit();
        var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner };
        const result = engine.run(children.bindings());
        try std.testing.expect(result == .execution_rejected);
        try std.testing.expectEqual(.authority, result.execution_rejected);
        try std.testing.expectEqual(@as(usize, 1), control.state.calls);
        try std.testing.expectEqual(@as(usize, 0), barrier.calls);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(test_value_schema.key)] == null);
        try std.testing.expect(!runner.envelope.latestInformation(test_value_schema.key).contains(test_value_schema.key));
        try std.testing.expectEqual(@as(u128, 0), runner.token_accounting.current().committed());
    }
}

test "runner rejects incomplete dependency renewal without committing repair progress or following recovery" {
    const values = @import("application/pipeline_values.zig");
    const retry = @import("domain/workflow_retry.zig");
    const candidate = comptime values.schema(.model_input_packet, u32, 1, 32).captured().recorded();
    const review = values.schema(.model_payload_schema_result, u32, 1, 32).captured().recorded();
    const permit: retry.Permit = .{ .key = .{ .scope = @splat(1), .target = @splat(2), .family = @splat(3) }, .authorization = @splat(4), .revision = 1, .maximum_targets = 1 };
    const Merge = struct {
        calls: usize = 0,
        fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
            context.?.calls += 1;
            var delta: pipeline.NodeDelta = .{};
            delta.data_replacements[@intFromEnum(candidate.key)] = values.create(std.testing.allocator, candidate, u32, 2) catch return error.OperationExecutionFailed;
            delta.data_invalidations = .initMany(input.step.step.invalidates);
            delta.repair_transition = .{ .merged = .{ .permit = permit, .revision_after = 2, .validation = .dependent_review } };
            return .{ .outcome = .ok, .delta = delta };
        }
    };
    for ([_]bool{ false, true }) |complete| {
        var steps = [_]compilation.CompiledStep{test_steps[0]} ** 2;
        steps[1].id = .{ .bytes = "recovery" };
        for (&steps) |*step| {
            step.requires = &.{ candidate.key, review.key, test_value_schema.key };
            step.replaces = &.{candidate.key};
            step.invalidates = if (complete) &.{ review.key, test_value_schema.key } else &.{review.key};
            step.repair_role = .merge;
        }
        const transitions = [_]workflow.Transition{
            .{ .from = steps[0].id, .outcome = .ok, .target = .{ .terminal = .ok } },
            .{ .from = steps[0].id, .outcome = .invalid, .target = .{ .step = steps[1].id } },
            .{ .from = steps[0].id, .outcome = .failed, .target = .{ .step = steps[1].id } },
        };
        var graph = try testGraph();
        graph.authority.steps = &steps;
        graph.authority.transitions = &transitions;
        graph.authority.data_schemas = &.{ candidate, review, test_value_schema };
        var control: OperationControl = .{ .state = .{ .outcome = .ok } };
        var registry = testRegistry(&control);
        registry.data_schemas = graph.authority.data_schemas;
        var merge: Merge = .{};
        control.entries[1].binding = operation_bindings.bind(Merge, &merge, Merge.invoke);
        control.entries[1].contract.requires = steps[0].requires;
        control.entries[1].contract.replaces = steps[0].replaces;
        control.entries[1].contract.invalidates = steps[0].invalidates;
        control.entries[1].contract.repair_role = .merge;
        var barrier: FakeBarrier = .{};
        var runner = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
        defer runner.deinit();
        var delta: pipeline.NodeDelta = .{};
        defer runner.envelope.discard(&delta);
        delta.data_writes[@intFromEnum(candidate.key)] = try values.create(std.testing.allocator, candidate, u32, 1);
        try runner.envelope.apply(.{ .id = "test.candidate", .kind = .action, .requires = &.{}, .produces = &.{candidate.key}, .side_effect = .none }, &delta, .ok);
        delta.data_writes[@intFromEnum(review.key)] = try values.create(std.testing.allocator, review, u32, 1);
        delta.data_writes[@intFromEnum(test_value_schema.key)] = try values.create(std.testing.allocator, test_value_schema, u32, 1);
        try runner.envelope.apply(.{ .id = "test.review", .kind = .action, .requires = &.{candidate.key}, .produces = &.{ review.key, test_value_schema.key }, .side_effect = .none }, &delta, .ok);
        try runner.repair_retry.commit(try runner.repair_retry.prepare(.{ .authorized = permit }));
        const generation = runner.envelope.generation;
        const revision = runner.repair_retry.revision;
        const original = runner.envelope.slots[@intFromEnum(candidate.key)];
        const history_count = runner.envelope.records.items.len;
        var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner };
        const result = engine.run(children.bindings());
        try std.testing.expectEqual(@as(usize, 1), merge.calls);
        try std.testing.expectEqual(@as(usize, 0), barrier.calls);
        try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
        if (complete) {
            try std.testing.expectEqual(.ok, result.executionStatus().?);
            try std.testing.expectEqual(revision + 1, runner.repair_retry.revision);
            try std.testing.expect(runner.envelope.slots[@intFromEnum(test_value_schema.key)] == null);
            try std.testing.expect(runner.envelope.slots[@intFromEnum(candidate.key)] != original);
        } else {
            try std.testing.expectEqual(.authority, result.execution_rejected);
            try std.testing.expectEqual(revision, runner.repair_retry.revision);
            // The engine applied only its empty invocation delta before merge.
            try std.testing.expectEqual(generation + 1, runner.envelope.generation);
            try std.testing.expectEqual(history_count, runner.envelope.records.items.len);
            try std.testing.expect(runner.envelope.slots[@intFromEnum(test_value_schema.key)] != null);
            try std.testing.expect(runner.envelope.slots[@intFromEnum(candidate.key)] == original);
        }
    }
}

const TestEngineBindings = struct {
    graph: *const compilation.CompiledWorkflow,
    runner: *runner_module.Runner,
    rejection: ?execution.Rejection = null,
    reject_invocation: bool = false,
    selection_results: [3]engine_bindings.SelectionStepOutcome = .{ .ok, .ok, .ok },
    selection_calls: usize = 0,
    preparation_result: engine_bindings.PreparationOutcome = .ok,
    finalizer: ?finalization.Finalizer = null,

    fn bindings(self: *TestEngineBindings) engine_bindings.ChildBindings {
        return .{ .context = self, .vtable = &test_engine_vtable };
    }
    fn selectionOk(context: *anyopaque) engine_bindings.SelectionStepOutcome {
        const self: *TestEngineBindings = @ptrCast(@alignCast(context));
        defer self.selection_calls += 1;
        return self.selection_results[self.selection_calls];
    }
    fn preparationOk(context: *anyopaque) engine_bindings.PreparationOutcome {
        const self: *TestEngineBindings = @ptrCast(@alignCast(context));
        return self.preparation_result;
    }
    fn selectedGraph(context: *const anyopaque) *const compilation.CompiledWorkflow {
        const self: *const TestEngineBindings = @ptrCast(@alignCast(context));
        return self.graph;
    }
    fn invokeInvocation(context: *anyopaque) execution.Applied {
        const self: *TestEngineBindings = @ptrCast(@alignCast(context));
        if (self.reject_invocation) if (self.rejection) |reason| return .{ .rejected = reason };
        return self.runner.bindings().invokeInvocation();
    }
    fn invokeStep(context: *anyopaque, id: workflow.WorkflowStepId) execution.Applied {
        const self: *TestEngineBindings = @ptrCast(@alignCast(context));
        if (!self.reject_invocation) if (self.rejection) |reason| return .{ .rejected = reason };
        return self.runner.bindings().invokeStep(id);
    }
    fn finalize(context: *anyopaque, outcome: run_outcome.Outcome) run_outcome.Outcome {
        const self: *TestEngineBindings = @ptrCast(@alignCast(context));
        return if (self.finalizer) |finalizer| finalizer.finish(outcome) else outcome;
    }
};

test "runner rejections bypass clarification transitions and preserve exact failure at invocation and step boundaries" {
    for ([_]execution.Rejection{ .authority, .{ .operation_failed = error.OperationExecutionFailed }, .{ .operation_failed = error.REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE }, .cancelled, .deadline_exhausted, .{ .gate = .missing_evidence }, .{ .logging = .LOG_SINK_FAILURE }, .{ .token_budget = error.WorkflowTokenBudgetExceeded }, .{ .token_budget = error.ProviderTokenUsageUnavailable }, .{ .retry_limit = @import("domain/workflow_retry.zig").Exhaustion.init(.{ .bytes = "account" }, .{ .value = 1 }, 2).? } }) |reason| {
        for ([_]bool{ false, true }) |invocation| {
            var graph = try testGraph();
            var transitions = test_transitions;
            for (&transitions) |*transition| transition.target = .{ .terminal = .needs_user };
            graph.authority.transitions = &transitions;
            var control: OperationControl = .{ .state = .{ .outcome = .ok } };
            var barrier: FakeBarrier = .{};
            var registry = testRegistry(&control);
            var runner = runner_module.Runner.init(std.testing.allocator, selected(&graph), &registry, barrier.port(), .{}, null);
            defer runner.deinit();
            var finalizer: FakeFinalizer = .{};
            var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner, .rejection = reason, .reject_invocation = invocation, .finalizer = finalizer.port() };
            const outcome = engine.run(children.bindings());
            try std.testing.expectEqualDeep(reason, outcome.execution_rejected);
            try std.testing.expectEqual(reason.status(), outcome.executionStatus().?);
            try std.testing.expectEqual(@as(usize, 0), control.state.calls);
            try std.testing.expectEqual(@as(usize, 1), finalizer.calls);
            try std.testing.expectEqualDeep(outcome, finalizer.last.?);
            try std.testing.expect(outcome.executionStatus() != .needs_user);
            for ([_]pipeline.DataKey{ .clarification_needs, .prepared_workflow_output, .published_workflow_output }) |key| {
                try std.testing.expect(runner.envelope.slots[@intFromEnum(key)] == null);
            }
        }
    }
}

test "retry exhaustion owns the operation name after source teardown" {
    const Exhaustion = @import("domain/workflow_retry.zig").Exhaustion;
    var name = "request-account".*;
    const rejection: execution.Rejection = .{ .retry_limit = Exhaustion.init(.{ .bytes = &name }, .{ .value = 4 }, 5).? };
    @memset(&name, 'x');
    try std.testing.expectEqualStrings("request-account", rejection.retry_limit.operation().bytes);
    try std.testing.expect(Exhaustion.init(.{ .bytes = "account" }, .{ .value = 4 }, 4) == null);
    try std.testing.expect(Exhaustion.init(.{ .bytes = "invalid/name" }, .{ .value = 4 }, 5) == null);
    var maximum: [workflow.max_step_id_bytes]u8 = @splat('s');
    const longest = Exhaustion.init(.{ .bytes = &maximum }, .{ .value = 4 }, 5).?;
    @memset(&maximum, 'x');
    try std.testing.expectEqualStrings("s" ** workflow.max_step_id_bytes, longest.operation().bytes);
    try std.testing.expect(Exhaustion.init(.{ .bytes = "s" ** (workflow.max_step_id_bytes + 1) }, .{ .value = 4 }, 5) == null);
}

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
    .finalize = TestEngineBindings.finalize,
};

const FakeFinalizer = struct {
    calls: usize = 0,
    last: ?run_outcome.Outcome = null,
    fail: bool = false,
    operations: ?*const OperationState = null,
    operations_at_finish: usize = 0,

    fn port(self: *FakeFinalizer) finalization.Finalizer {
        return .{ .context = @ptrCast(self), .finish_fn = finish };
    }
    fn finish(context: *finalization.Context, reason: finalization.Finalizer.Reason) run_outcome.Outcome {
        const self: *FakeFinalizer = @ptrCast(@alignCast(context));
        const outcome = reason.outcome();
        self.calls += 1;
        self.last = outcome;
        if (self.operations) |operations_state| self.operations_at_finish = operations_state.calls;
        return if (self.fail) .{ .execution_rejected = .{ .logging = .LOG_FLUSH_FAILURE } } else outcome;
    }
};

const OperationControl = struct {
    state: OperationState,
    entries: [2]operations.Entry = undefined,
};

const retry_parameters = [_]@import("domain/workflow_operation.zig").ParameterDescriptor{.{
    .id = "retry-limit",
    .kind = .integer,
    .required = true,
    .workflow_definition_safe = true,
    .integer_min = 0,
    .integer_max = 2,
}};
const OperationState = struct {
    outcome: workflow.OutcomeTag,
    scripted: []const workflow.OutcomeTag = &.{},
    expected_steps: []const []const u8 = &.{},
    expected_resource_id: ?[]const u8 = null,
    calls: usize = 0,
    fail_call: ?usize = null,
    delta_fault: ?DeltaFault = null,
};
const DeltaFault = enum { missing_write, wrong_schema, undeclared_invalidation, undeclared_outcome };
const test_value_schema = @import("application/pipeline_values.zig").schema(.canonical_log_level, u32, 1, 32).recorded();
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
            .contract = .{ .id = "test.empty", .kind = .invocation, .outcomes = &.{.ok}, .side_effect = .none },
            .binding = operation_bindings.bind(OperationState, &control.state, invokeOperation),
        },
        .{
            .contract = .{
                .id = "test.operation",
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
            .binding = operation_bindings.bind(OperationState, &control.state, invokeOperation),
        },
    };
    return .{
        .operations = &control.entries,
        .policies = &.{.{ .id = "test.safe@1", .allowed_capabilities = &.{}, .allowed_terminal_outcomes = test_outcomes, .total_model_token_budget = .{ .value = 1000 } }},
        .gates = &.{},
    };
}

fn invokeOperation(context: ?*OperationState, input: operations.Input) operations.Error!execution.Candidate {
    return switch (input) {
        .invocation => .{ .outcome = .ok, .delta = .{} },
        .step => |step_input| step: {
            const control = context.?;
            if (control.expected_steps.len != 0) {
                if (control.calls >= control.expected_steps.len or
                    !std.mem.eql(u8, step_input.step.id.bytes, control.expected_steps[control.calls]))
                    return error.OperationExecutionFailed;
            }
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
            if (control.fail_call == control.calls) return error.OperationExecutionFailed;
            var delta: pipeline.NodeDelta = .{};
            if (control.delta_fault) |fault| {
                const values = @import("application/pipeline_values.zig");
                if (fault != .missing_write or control.calls > 1) {
                    var schema = test_value_schema;
                    if (fault == .wrong_schema and control.calls == 1) schema.version += 1;
                    delta.data_writes[@intFromEnum(test_value_schema.key)] = values.create(std.testing.allocator, schema, u32, 1) catch return error.OperationExecutionFailed;
                }
                if (fault == .undeclared_invalidation and control.calls == 1) delta.data_invalidations.insert(.workflow_invocation);
                if (fault == .undeclared_outcome and control.calls == 1) break :step .{ .outcome = .more, .delta = delta };
            }
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
            .invocation_operation_id = .{ .bytes = "test.empty" },
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

const test_outcomes: []const workflow.OutcomeTag = &.{ .ok, .needs_user, .invalid, .blocked, .failed, .cancelled };

test "native policies cannot admit bounded progress as terminal authority" {
    var control: OperationControl = .{ .state = .{ .outcome = .ok } };
    var registry = testRegistry(&control);
    var policy = registry.policies[0];
    policy.allowed_terminal_outcomes = &.{ .ok, .more };
    registry.policies = &.{policy};
    try std.testing.expect(!registry.validate());
}
const test_steps = [_]compilation.CompiledStep{.{
    .id = .{ .bytes = "run" },
    .operation_id = .{ .bytes = "test.operation" },
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
