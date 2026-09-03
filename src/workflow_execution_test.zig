const std = @import("std");
const pipeline = @import("domain/pipeline.zig");
const execution = @import("domain/workflow_execution.zig");
const workflow = @import("domain/workflow.zig");
const workflow_compilation = @import("domain/workflow_compilation.zig");
const telemetry = @import("domain/telemetry.zig");
const log_stream = @import("domain/feature_log_stream.zig");
const implementation = @import("ports/workflow_node_implementation.zig");
const barrier_port = @import("ports/telemetry_barrier.zig");
const runner_module = @import("application/workflow_pipeline_runner.zig");
const engine = @import("application/workflow_engine_orchestrator.zig");
const engine_bindings = @import("application/workflow_engine_child_bindings.zig");

test "generic engine preserves every compiled terminal outcome without workflow-name branching" {
    inline for (std.meta.tags(workflow.OutcomeTag)) |expected| {
        var node_control: NodeControl = .{ .outcome = expected };
        var barrier: FakeBarrier = .{};
        var graph = try testGraph();
        const invocation_implementations = [_]implementation.InvocationImplementation{.{ .contract_id = "test.empty@1", .invoke_fn = invokeEmpty }};
        const node_implementations = [_]implementation.NodeImplementation{.{ .contract_id = "test.node@1", .context = &node_control, .invoke_fn = invokeNode }};
        var runner: runner_module.Runner = .{
            .selected = .{
                .invocation = .{ .workflow_id = graph.authority.workflow_id, .arguments = &.{} },
                .graph = &graph,
            },
            .implementations = .{ .invocations = &invocation_implementations, .nodes = &node_implementations },
            .barrier = barrier.port(),
            .runtime = .{},
        };
        var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner };
        try std.testing.expectEqual(expected, engine.run(children.bindings()).execution);
        try std.testing.expectEqual(@as(usize, 1), barrier.calls);
    }
}

test "runner applies the node delta before logging and blocks before a successor" {
    var node_control: NodeControl = .{ .outcome = .ok };
    var barrier: FakeBarrier = .{ .block = true };
    var graph = try testGraph();
    const invocation_implementations = [_]implementation.InvocationImplementation{.{ .contract_id = "test.empty@1", .invoke_fn = invokeEmpty }};
    const node_implementations = [_]implementation.NodeImplementation{.{ .contract_id = "test.node@1", .context = &node_control, .invoke_fn = invokeNode }};
    var runner: runner_module.Runner = .{
        .selected = .{
            .invocation = .{ .workflow_id = graph.authority.workflow_id, .arguments = &.{} },
            .graph = &graph,
        },
        .implementations = .{ .invocations = &invocation_implementations, .nodes = &node_implementations },
        .barrier = barrier.port(),
        .runtime = .{},
    };
    var children: TestEngineBindings = .{ .graph = &graph, .runner = &runner };
    try std.testing.expectEqual(workflow.OutcomeTag.blocked, engine.run(children.bindings()).execution);
    try std.testing.expectEqual(@as(usize, 1), barrier.calls);
}

const TestEngineBindings = struct {
    graph: *const workflow_compilation.CompiledWorkflow,
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
    fn selectedGraph(context: *const anyopaque) *const workflow_compilation.CompiledWorkflow {
        const self: *const TestEngineBindings = @ptrCast(@alignCast(context));
        return self.graph;
    }
    fn invokeInvocation(context: *anyopaque) execution.Applied {
        const self: *TestEngineBindings = @ptrCast(@alignCast(context));
        return self.runner.bindings().invokeInvocation();
    }
    fn invokeNode(context: *anyopaque, id: workflow.WorkflowNodeId) execution.Applied {
        const self: *TestEngineBindings = @ptrCast(@alignCast(context));
        return self.runner.bindings().invokeNode(id);
    }
};

const test_engine_vtable: engine_bindings.ChildBindings.VTable = .{
    .validate_implementation_registry = TestEngineBindings.selectionOk,
    .parse_invocation = TestEngineBindings.selectionOk,
    .select_workflow = TestEngineBindings.selectionOk,
    .prepare_workflow = TestEngineBindings.preparationOk,
    .selected_graph = TestEngineBindings.selectedGraph,
    .invoke_invocation = TestEngineBindings.invokeInvocation,
    .invoke_node = TestEngineBindings.invokeNode,
};

const NodeControl = struct { outcome: workflow.OutcomeTag };
const FakeBarrier = struct {
    calls: usize = 0,
    block: bool = false,
    fn port(self: *FakeBarrier) barrier_port.Barrier {
        return .{ .context = self, .process_fn = process };
    }
    fn process(context: *anyopaque, _: telemetry.WorkflowTelemetryFact) execution.Candidate {
        const self: *FakeBarrier = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (self.block) return .{ .outcome = .blocked, .delta = .{} };
        return .{ .outcome = .ok, .delta = .{ .data_writes = &.{.feature_log_append_evidence} } };
    }
};

fn invokeEmpty(_: ?*anyopaque, _: implementation.InvocationInput) implementation.Error!execution.Candidate {
    return .{ .outcome = .ok, .delta = .{} };
}
fn invokeNode(context: ?*anyopaque, input: implementation.NodeInput) implementation.Error!execution.Candidate {
    const control: *NodeControl = @ptrCast(@alignCast(context.?));
    var delta: pipeline.NodeDelta = .{};
    input.log.log(&delta, .{ .event_type = .action_completed }) catch return error.NodeExecutionFailed;
    return .{ .outcome = control.outcome, .delta = delta };
}

fn testGraph() !workflow_compilation.CompiledWorkflow {
    return .{
        .source_ordinal = 1,
        .shortcode = try telemetry.WorkflowShortcode.parse("TEST"),
        .authority = .{
            .workflow_id = .{ .bytes = "arbitrary-workflow" },
            .workflow_version = 1,
            .invocation_contract_id = .{ .bytes = "test.empty@1" },
            .policy_profile_id = .{ .bytes = "test.safe@1" },
            .entry_node_id = .{ .bytes = "run" },
            .invocation_outputs = &.{},
            .nodes = &test_nodes,
            .transitions = &test_transitions,
        },
    };
}

const test_outcomes = std.meta.tags(workflow.OutcomeTag);
const test_nodes = [_]workflow_compilation.CompiledNode{.{
    .id = .{ .bytes = "run" },
    .contract_id = .{ .bytes = "test.node@1" },
    .parameters = &.{},
    .requires = &.{},
    .produces = &.{},
    .replaces = &.{},
    .invalidates = &.{},
    .outcomes = test_outcomes,
    .side_effect = .none,
    .gates = &.{},
    .capabilities = &.{},
}};
const test_transitions = [_]workflow.Transition{
    .{ .from = .{ .bytes = "run" }, .outcome = .ok, .target = .{ .terminal = .ok } },
    .{ .from = .{ .bytes = "run" }, .outcome = .needs_user, .target = .{ .terminal = .needs_user } },
    .{ .from = .{ .bytes = "run" }, .outcome = .invalid, .target = .{ .terminal = .invalid } },
    .{ .from = .{ .bytes = "run" }, .outcome = .blocked, .target = .{ .terminal = .blocked } },
    .{ .from = .{ .bytes = "run" }, .outcome = .failed, .target = .{ .terminal = .failed } },
    .{ .from = .{ .bytes = "run" }, .outcome = .cancelled, .target = .{ .terminal = .cancelled } },
};
