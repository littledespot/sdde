const std = @import("std");
const pipeline = @import("domain/pipeline.zig");
const execution = @import("domain/workflow_execution.zig");
const workflow = @import("domain/workflow_registry.zig");
const telemetry = @import("domain/telemetry.zig");
const log_runtime = @import("domain/feature_log_runtime.zig");
const implementation = @import("ports/workflow_node_implementation.zig");
const barrier_port = @import("ports/telemetry_barrier.zig");
const runner_module = @import("application/workflow_pipeline_runner.zig");
const engine = @import("application/workflow_engine_orchestrator.zig");

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
        try std.testing.expectEqual(expected, engine.run(&graph, runner.bindings()));
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
    try std.testing.expectEqual(workflow.OutcomeTag.blocked, engine.run(&graph, runner.bindings()));
    try std.testing.expectEqual(@as(usize, 1), barrier.calls);
}

const NodeControl = struct { outcome: workflow.OutcomeTag };
const FakeBarrier = struct {
    calls: usize = 0,
    block: bool = false,
    fn port(self: *FakeBarrier) barrier_port.Barrier {
        return .{ .context = self, .process_fn = process };
    }
    fn process(context: *anyopaque, _: telemetry.WorkflowTelemetryFact) log_runtime.BarrierOutcome {
        const self: *FakeBarrier = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (self.block) return .{ .blocked = .LOG_SINK_FAILURE };
        return .{ .persisted = .{ .segment_ordinal = 1, .sequence = self.calls, .bytes_written = 1, .flushed = true } };
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

fn testGraph() !workflow.CompiledWorkflow {
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
const test_nodes = [_]workflow.CompiledNode{.{
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
