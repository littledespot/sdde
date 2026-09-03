const bootstrap_orchestrator = @import("bootstrap_orchestrator.zig");
const bootstrap_services = @import("bootstrap_services.zig");
const model_provider_bootstrap = @import("model_provider_bootstrap_binding.zig");
const workflow_pipeline_runner = @import("workflow_pipeline_runner.zig");
const workflow_engine = @import("workflow_engine_orchestrator.zig");
const parse_invocation = @import("../actions/workflow/parse_workflow_invocation.zig");
const select_workflow = @import("../actions/workflow/select_compiled_workflow.zig");
const compilation = @import("../domain/workflow_compilation.zig");
const execution = @import("../domain/workflow_execution.zig");
const implementations = @import("../ports/workflow_node_implementation.zig");
const run_outcome = @import("../domain/run_outcome.zig");

pub fn run(
    boot: *bootstrap_orchestrator.Outcome,
    arguments: []const []const u8,
    implementation_registry: implementations.Registry,
    compiler_registry: compilation.CompilerRegistry,
    provider_bootstrap: model_provider_bootstrap.Binding,
) run_outcome.Outcome {
    return switch (boot.*) {
        .failed => |failure| .{ .bootstrap_failed = failure },
        .cancelled => .{ .execution = .cancelled },
        .ready => |*services| execute(
            services,
            arguments,
            implementation_registry,
            compiler_registry,
            provider_bootstrap,
        ),
    };
}

fn execute(
    services: *bootstrap_services.BootstrapServices,
    arguments: []const []const u8,
    implementation_registry: implementations.Registry,
    compiler_registry: compilation.CompilerRegistry,
    provider_bootstrap: model_provider_bootstrap.Binding,
) run_outcome.Outcome {
    if (!implementation_registry.matchesCompiler(compiler_registry)) {
        return .{ .execution = .failed };
    }
    const invocation = (parse_invocation.Action{}).execute(arguments) catch return .invocation_invalid;
    const selected = (select_workflow.Action{ .registry = services.workflows.registry() }).execute(invocation) catch {
        return .invocation_invalid;
    };

    var provider = provider_bootstrap.invoke(
        &selected,
        &services.config.config().models,
        services.roots.registry().llmProviderConfig(),
    );
    defer provider.deinit();
    return switch (provider) {
        .not_required, .ready => executeSelected(
            services,
            selected,
            implementation_registry,
        ),
        .failed => |failure| .{ .bootstrap_failed = failure },
        .cancelled => .{ .execution = .cancelled },
    };
}

fn executeSelected(
    services: *bootstrap_services.BootstrapServices,
    selected: execution.SelectedWorkflow,
    implementation_registry: implementations.Registry,
) run_outcome.Outcome {
    var runner: workflow_pipeline_runner.Runner = .{
        .selected = selected,
        .implementations = implementation_registry,
        .barrier = services.logs.barrier(),
        .runtime = .{},
    };
    return .{ .execution = workflow_engine.run(selected.graph, runner.bindings()) };
}
