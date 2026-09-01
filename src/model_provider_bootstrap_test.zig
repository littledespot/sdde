const std = @import("std");
const compile = @import("actions/workflow/compile_workflow_graphs.zig");
const derive = @import("actions/provider/derive_provider_requirement.zig");
const requirement = @import("domain/model_provider_requirement.zig");
const pipeline = @import("domain/pipeline.zig");
const telemetry = @import("domain/telemetry.zig");
const workflow = @import("domain/workflow.zig");
const compilation = @import("domain/workflow_compilation.zig");
const definition = @import("domain/workflow_definition.zig");
const execution = @import("domain/workflow_execution.zig");

test "compiler-owned model-provider capability alone activates the requirement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const capable = try compileOne(arena.allocator(), &compiler_registry, "test.model@1");
    try std.testing.expectEqual(requirement.Requirement.required, deriveGraph(&capable));

    const capability_free = try compileOne(arena.allocator(), &compiler_registry, "test.noop@1");
    try std.testing.expectEqual(requirement.Requirement.not_required, deriveGraph(&capability_free));

    var denied = compiler_registry;
    denied.policies = &.{.{
        .id = "test.safe@1",
        .allowed_capabilities = &.{},
        .allowed_terminal_outcomes = &.{.ok},
    }};
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        compileOne(arena.allocator(), &denied, "test.model@1"),
    );
}

fn compileOne(
    allocator: std.mem.Allocator,
    registry: *const compilation.CompilerRegistry,
    contract_id: []const u8,
) !compilation.CompiledWorkflow {
    const nodes = try allocator.alloc(workflow.DeclarativeNode, 1);
    nodes[0] = .{
        .id = workflow.WorkflowNodeId.parse("run").?,
        .contract_id = workflow.RegisteredRef.parse(contract_id).?,
        .parameters = &.{},
    };
    const transitions = try allocator.alloc(workflow.Transition, 1);
    transitions[0] = .{
        .from = nodes[0].id,
        .outcome = .ok,
        .target = .{ .terminal = .ok },
    };
    const definitions = try allocator.alloc(definition.Definition, 1);
    definitions[0] = .{
        .source_ordinal = 1,
        .workflow_id = workflow.WorkflowId.parse("model-provider").?,
        .workflow_version = 1,
        .shortcode = telemetry.WorkflowShortcode.parse("TEST") catch unreachable,
        .invocation_contract_id = workflow.RegisteredRef.parse("test.empty@1").?,
        .policy_profile_id = workflow.RegisteredRef.parse("test.safe@1").?,
        .entry_node_id = nodes[0].id,
        .nodes = nodes,
        .transitions = transitions,
    };
    const graphs = try (compile.Action{ .registry = registry }).execute(allocator, definitions);
    return graphs[0];
}

fn deriveGraph(graph: *const compilation.CompiledWorkflow) requirement.Requirement {
    const selected: execution.SelectedWorkflow = .{
        .invocation = .{ .workflow_id = graph.authority.workflow_id, .arguments = &.{} },
        .graph = graph,
    };
    return (derive.Action{}).execute(&selected);
}

const compiler_registry: compilation.CompilerRegistry = .{
    .invocations = &.{.{
        .id = "test.empty@1",
        .capability_free = true,
        .produces = &.{},
    }},
    .nodes = &.{
        .{
            .id = "test.model@1",
            .parameters = &.{},
            .requires = &.{},
            .produces = &.{},
            .outcomes = &.{.ok},
            .side_effect = pipeline.SideEffect.none,
            .capabilities = &.{requirement.capability_id},
        },
        .{
            .id = "test.noop@1",
            .parameters = &.{},
            .requires = &.{},
            .produces = &.{},
            .outcomes = &.{.ok},
            .side_effect = pipeline.SideEffect.none,
        },
    },
    .policies = &.{.{
        .id = "test.safe@1",
        .allowed_capabilities = &.{requirement.capability_id},
        .allowed_terminal_outcomes = &.{.ok},
    }},
    .gates = &.{},
    .capabilities = &.{requirement.capability_id},
};
