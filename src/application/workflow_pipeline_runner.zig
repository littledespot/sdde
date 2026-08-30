const pipeline = @import("../domain/pipeline.zig");
const execution = @import("../domain/workflow_execution.zig");
const workflow = @import("../domain/workflow_registry.zig");
const implementations = @import("../ports/workflow_node_implementation.zig");
const telemetry_barrier = @import("../ports/telemetry_barrier.zig");
const child_bindings = @import("workflow_engine_child_bindings.zig");

pub const Runner = struct {
    selected: execution.SelectedWorkflow,
    implementations: implementations.Registry,
    barrier: telemetry_barrier.Barrier,
    runtime: pipeline.NodeRuntime,
    envelope: pipeline.PipelineEnvelope = pipeline.PipelineEnvelope.init(&.{}),

    pub fn bindings(self: *Runner) child_bindings.ChildBindings {
        return .{ .context = self, .vtable = &vtable };
    }

    fn invokeInvocation(self: *Runner) execution.Applied {
        if (runtimeTerminal(self.runtime)) |outcome| return .{ .outcome = outcome };
        const authority = self.selected.graph.authority;
        const implementation = self.implementations.resolveInvocation(authority.invocation_contract_id) orelse {
            return .{ .outcome = .failed };
        };
        const candidate = implementation.invoke(.{ .arguments = self.selected.invocation.arguments }) catch {
            return .{ .outcome = .failed };
        };
        const contract: pipeline.NodeContract = .{
            .id = authority.invocation_contract_id.bytes,
            .kind = .action,
            .requires = &.{},
            .produces = authority.invocation_outputs,
            .side_effect = .none,
        };
        return self.applyCandidate(contract, candidate);
    }

    fn invokeNode(self: *Runner, id: workflow.WorkflowNodeId) execution.Applied {
        if (runtimeTerminal(self.runtime)) |outcome| return .{ .outcome = outcome };
        const node = findNode(self.selected.graph.authority.nodes, id) orelse return .{ .outcome = .failed };
        const implementation = self.implementations.resolveNode(node.contract_id) orelse return .{ .outcome = .failed };
        const candidate = implementation.invoke(.{
            .node = node,
            .log = pipeline.WorkflowLog.init(self.selected.graph.shortcode),
        }) catch return .{ .outcome = .failed };
        if (!containsOutcome(node.outcomes, candidate.outcome)) return .{ .outcome = .failed };
        const contract: pipeline.NodeContract = .{
            .id = node.contract_id.bytes,
            .kind = .action,
            .requires = node.requires,
            .produces = node.produces,
            .replaces = node.replaces,
            .invalidates = node.invalidates,
            .side_effect = node.side_effect,
        };
        return self.applyCandidate(contract, candidate);
    }

    fn applyCandidate(self: *Runner, contract: pipeline.NodeContract, candidate: execution.Candidate) execution.Applied {
        const next = self.envelope.apply(contract, candidate.delta) catch return .{ .outcome = .invalid };
        self.envelope = next;
        for (candidate.delta.addedTelemetryFacts()) |fact| switch (self.barrier.process(fact)) {
            .dropped, .persisted => {},
            .blocked => return .{ .outcome = .blocked },
        };
        return .{ .outcome = candidate.outcome };
    }
};

fn invokeInvocation(context: *anyopaque) execution.Applied {
    return cast(context).invokeInvocation();
}
fn invokeNode(context: *anyopaque, id: workflow.WorkflowNodeId) execution.Applied {
    return cast(context).invokeNode(id);
}
fn cast(context: *anyopaque) *Runner {
    return @ptrCast(@alignCast(context));
}
const vtable: child_bindings.ChildBindings.VTable = .{
    .invoke_invocation = invokeInvocation,
    .invoke_node = invokeNode,
};

fn findNode(nodes: []const workflow.CompiledNode, id: workflow.WorkflowNodeId) ?*const workflow.CompiledNode {
    for (nodes) |*node| if (@import("std").mem.eql(u8, node.id.bytes, id.bytes)) return node;
    return null;
}
fn containsOutcome(outcomes: []const workflow.OutcomeTag, outcome: workflow.OutcomeTag) bool {
    for (outcomes) |allowed| if (allowed == outcome) return true;
    return false;
}
fn runtimeTerminal(runtime: pipeline.NodeRuntime) ?workflow.OutcomeTag {
    return switch (runtime.status()) {
        .active => null,
        .cancelled => .cancelled,
        .deadline_exhausted => .failed,
    };
}
