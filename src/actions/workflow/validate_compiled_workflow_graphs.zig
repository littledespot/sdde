const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const workflow = @import("../../domain/workflow_registry.zig");

pub const Error = error{WorkflowGraphCompileInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-compiled-workflow-graphs@1",
        .kind = .action,
        .requires = &.{.compiled_workflow_graphs},
        .produces = &.{.validated_workflow_graphs},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        graphs: []const workflow.CompiledWorkflow,
    ) Error!workflow.ValidatedGraphs {
        for (graphs) |graph| try validateGraph(allocator, graph);
        return .{ .values = graphs };
    }
};

const key_count = @typeInfo(pipeline.DataKey).@"enum".fields.len;
const KeyState = [key_count]bool;

fn validateGraph(allocator: std.mem.Allocator, graph: workflow.CompiledWorkflow) Error!void {
    const nodes = graph.authority.nodes;
    if (nodes.len == 0 or nodes.len > workflow.max_nodes) return invalid();
    const entry = nodeIndex(nodes, graph.authority.entry_node_id.bytes) orelse return invalid();
    const colors = allocator.alloc(u2, nodes.len) catch return invalid();
    @memset(colors, 0);
    var order: std.ArrayList(usize) = .empty;
    try visit(nodes, graph.authority.transitions, entry, colors, &order, allocator);
    if (order.items.len != nodes.len) return invalid();
    std.mem.reverse(usize, order.items);

    const terminal_memo = allocator.alloc(u2, nodes.len) catch return invalid();
    @memset(terminal_memo, 0);
    for (0..nodes.len) |index| if (!try reachesTerminal(nodes, graph.authority.transitions, index, terminal_memo)) return invalid();

    const inputs = allocator.alloc(?KeyState, nodes.len) catch return invalid();
    @memset(inputs, null);
    var initial = [_]bool{false} ** key_count;
    for (graph.authority.invocation_outputs) |key| {
        if (initial[@intFromEnum(key)]) return invalid();
        initial[@intFromEnum(key)] = true;
    }
    inputs[entry] = initial;
    for (order.items) |index| {
        const input = inputs[index] orelse return invalid();
        const output = try applyDataContract(input, nodes[index]);
        for (graph.authority.transitions) |transition| {
            if (!std.mem.eql(u8, transition.from.bytes, nodes[index].id.bytes)) continue;
            switch (transition.target) {
                .terminal => {},
                .node => |target| {
                    const target_index = nodeIndex(nodes, target.bytes) orelse return invalid();
                    if (inputs[target_index]) |existing| {
                        if (!std.mem.eql(bool, &existing, &output)) return invalid();
                    } else inputs[target_index] = output;
                },
            }
        }
    }
}

fn visit(
    nodes: []const workflow.CompiledNode,
    transitions: []const workflow.Transition,
    index: usize,
    colors: []u2,
    order: *std.ArrayList(usize),
    allocator: std.mem.Allocator,
) Error!void {
    if (colors[index] == 1) return invalid();
    if (colors[index] == 2) return;
    colors[index] = 1;
    for (transitions) |transition| {
        if (!std.mem.eql(u8, transition.from.bytes, nodes[index].id.bytes)) continue;
        switch (transition.target) {
            .terminal => {},
            .node => |target| try visit(
                nodes,
                transitions,
                nodeIndex(nodes, target.bytes) orelse return invalid(),
                colors,
                order,
                allocator,
            ),
        }
    }
    colors[index] = 2;
    order.append(allocator, index) catch return invalid();
}

fn reachesTerminal(
    nodes: []const workflow.CompiledNode,
    transitions: []const workflow.Transition,
    index: usize,
    memo: []u2,
) Error!bool {
    if (memo[index] == 2) return true;
    if (memo[index] == 3) return false;
    if (memo[index] == 1) return invalid();
    memo[index] = 1;
    var result = false;
    for (transitions) |transition| {
        if (!std.mem.eql(u8, transition.from.bytes, nodes[index].id.bytes)) continue;
        result = result or switch (transition.target) {
            .terminal => true,
            .node => |target| try reachesTerminal(
                nodes,
                transitions,
                nodeIndex(nodes, target.bytes) orelse return invalid(),
                memo,
            ),
        };
    }
    memo[index] = if (result) 2 else 3;
    return result;
}

fn applyDataContract(input: KeyState, node: workflow.CompiledNode) Error!KeyState {
    var result = input;
    for (node.requires) |key| if (!input[@intFromEnum(key)]) return invalid();
    for (node.produces) |key| {
        if (result[@intFromEnum(key)]) return invalid();
        result[@intFromEnum(key)] = true;
    }
    for (node.replaces) |key| if (!result[@intFromEnum(key)]) return invalid();
    for (node.invalidates) |key| {
        if (!result[@intFromEnum(key)]) return invalid();
        result[@intFromEnum(key)] = false;
    }
    return result;
}

fn nodeIndex(nodes: []const workflow.CompiledNode, expected: []const u8) ?usize {
    for (nodes, 0..) |node, index| if (std.mem.eql(u8, node.id.bytes, expected)) return index;
    return null;
}
fn invalid() Error {
    return error.WorkflowGraphCompileInvalid;
}

test "graph validator rejects cycles and unreachable registered nodes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const nodes = [_]workflow.CompiledNode{
        .{ .id = workflow.WorkflowNodeId.parse("one").?, .contract_id = workflow.RegisteredRef.parse("core.one@1").?, .parameters = &.{}, .requires = &.{}, .produces = &.{}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{.ok}, .side_effect = .none, .gates = &.{}, .capabilities = &.{} },
        .{ .id = workflow.WorkflowNodeId.parse("two").?, .contract_id = workflow.RegisteredRef.parse("core.two@1").?, .parameters = &.{}, .requires = &.{}, .produces = &.{}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{.ok}, .side_effect = .none, .gates = &.{}, .capabilities = &.{} },
    };
    const cyclic = [_]workflow.Transition{
        .{ .from = nodes[0].id, .outcome = .ok, .target = .{ .node = nodes[1].id } },
        .{ .from = nodes[1].id, .outcome = .ok, .target = .{ .node = nodes[0].id } },
    };
    const graph: workflow.CompiledWorkflow = .{
        .source_ordinal = 1,
        .shortcode = @import("../../domain/telemetry.zig").WorkflowShortcode.parse("TEST") catch unreachable,
        .authority = .{
            .workflow_id = workflow.WorkflowId.parse("graph-test").?,
            .workflow_version = 1,
            .invocation_contract_id = workflow.RegisteredRef.parse("core.empty@1").?,
            .policy_profile_id = workflow.RegisteredRef.parse("core.safe@1").?,
            .entry_node_id = nodes[0].id,
            .invocation_outputs = &.{},
            .nodes = &nodes,
            .transitions = &cyclic,
        },
    };
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, (Action{}).execute(arena.allocator(), &.{graph}));

    const terminal = [_]workflow.Transition{.{ .from = nodes[0].id, .outcome = .ok, .target = .{ .terminal = .ok } }};
    var disconnected = graph;
    disconnected.authority.transitions = &terminal;
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, (Action{}).execute(arena.allocator(), &.{disconnected}));
}

test "graph validator enforces the variable-size node boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const nodes = try arena.allocator().alloc(workflow.CompiledNode, workflow.max_nodes + 1);
    const node: workflow.CompiledNode = .{
        .id = workflow.WorkflowNodeId.parse("node").?,
        .contract_id = workflow.RegisteredRef.parse("core.noop@1").?,
        .parameters = &.{},
        .requires = &.{},
        .produces = &.{},
        .replaces = &.{},
        .invalidates = &.{},
        .outcomes = &.{.ok},
        .side_effect = .none,
        .gates = &.{},
        .capabilities = &.{},
    };
    @memset(nodes, node);
    const graph: workflow.CompiledWorkflow = .{
        .source_ordinal = 1,
        .shortcode = @import("../../domain/telemetry.zig").WorkflowShortcode.parse("SIZE") catch unreachable,
        .authority = .{
            .workflow_id = workflow.WorkflowId.parse("size-boundary").?,
            .workflow_version = 1,
            .invocation_contract_id = workflow.RegisteredRef.parse("core.empty@1").?,
            .policy_profile_id = workflow.RegisteredRef.parse("core.safe@1").?,
            .entry_node_id = node.id,
            .invocation_outputs = &.{},
            .nodes = nodes,
            .transitions = &.{},
        },
    };
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, (Action{}).execute(arena.allocator(), &.{graph}));
}
