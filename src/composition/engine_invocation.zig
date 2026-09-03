const std = @import("std");
const pipeline = @import("../domain/pipeline.zig");
const bootstrap_services = @import("../application/bootstrap_services.zig");
const model_provider_binding = @import("../application/model_provider_bootstrap_binding.zig");
const model_provider_orchestrator = @import("../application/model_provider_bootstrap_orchestrator.zig");
const workflow_bindings = @import("../application/workflow_engine_child_bindings.zig");
const workflow_pipeline_runner = @import("../application/workflow_pipeline_runner.zig");
const workflow_selection_runner = @import("../application/workflow_selection_runner.zig");
const compilation = @import("../domain/workflow_compilation.zig");
const execution = @import("../domain/workflow_execution.zig");
const workflow = @import("../domain/workflow.zig");
const operations = @import("../ports/workflow_operation_registry.zig");

pub const Assembly = struct {
    services: *bootstrap_services.BootstrapServices,
    provider_bootstrap: model_provider_binding.Binding,
    operation_registry: *const operations.Registry,
    selection: workflow_selection_runner.Runner,
    provider_outcome: ?model_provider_orchestrator.Outcome = null,
    pipeline_runner: ?workflow_pipeline_runner.Runner = null,

    pub fn init(
        services: *bootstrap_services.BootstrapServices,
        arguments: []const []const u8,
        operation_registry: *const operations.Registry,
        provider_bootstrap: model_provider_binding.Binding,
        runtime: pipeline.NodeRuntime,
    ) Assembly {
        return .{
            .services = services,
            .provider_bootstrap = provider_bootstrap,
            .operation_registry = operation_registry,
            .selection = workflow_selection_runner.Runner.init(
                runtime,
                arguments,
                services.workflows.registry(),
                operation_registry,
            ),
        };
    }

    pub fn deinit(self: *Assembly) void {
        if (self.provider_outcome) |*outcome| outcome.deinit();
        self.* = undefined;
    }

    pub fn bindings(self: *Assembly) workflow_bindings.ChildBindings {
        return .{ .context = self, .vtable = &vtable };
    }

    fn invokeValidateOperationRegistry(context: *anyopaque) workflow_bindings.SelectionStepOutcome {
        return cast(context).selection.invokeValidateOperationRegistry();
    }
    fn invokeParseInvocation(context: *anyopaque) workflow_bindings.SelectionStepOutcome {
        return cast(context).selection.invokeParseInvocation();
    }
    fn invokeSelectWorkflow(context: *anyopaque) workflow_bindings.SelectionStepOutcome {
        return cast(context).selection.invokeSelectWorkflow();
    }

    fn invokePrepareWorkflow(context: *anyopaque) workflow_bindings.PreparationOutcome {
        const self = cast(context);
        std.debug.assert(self.provider_outcome == null);
        const selected = self.selection.selected();
        self.provider_outcome = self.provider_bootstrap.invoke(
            selected,
            &self.services.config.config().models,
            self.services.roots.registry().llmProviderConfig(),
        );
        return switch (self.provider_outcome.?) {
            .not_required, .ready => ready: {
                self.pipeline_runner = .{
                    .selected = selected.*,
                    .operation_registry = self.operation_registry,
                    .barrier = self.services.logs.barrier(),
                    .runtime = self.selection.runtime,
                };
                break :ready .ok;
            },
            .failed => |failure| .{ .failed = failure },
            .cancelled => .cancelled,
        };
    }

    fn selectedGraph(context: *const anyopaque) *const compilation.CompiledWorkflow {
        const self: *const Assembly = @ptrCast(@alignCast(context));
        return self.selection.selected().graph;
    }
    fn invokeInvocation(context: *anyopaque) execution.Applied {
        return cast(context).pipeline_runner.?.bindings().invokeInvocation();
    }
    fn invokeStep(context: *anyopaque, id: workflow.WorkflowStepId) execution.Applied {
        return cast(context).pipeline_runner.?.bindings().invokeStep(id);
    }
    fn cast(context: *anyopaque) *Assembly {
        return @ptrCast(@alignCast(context));
    }
};

const vtable: workflow_bindings.ChildBindings.VTable = .{
    .validate_operation_registry = Assembly.invokeValidateOperationRegistry,
    .parse_invocation = Assembly.invokeParseInvocation,
    .select_workflow = Assembly.invokeSelectWorkflow,
    .prepare_workflow = Assembly.invokePrepareWorkflow,
    .selected_graph = Assembly.selectedGraph,
    .invoke_invocation = Assembly.invokeInvocation,
    .invoke_step = Assembly.invokeStep,
};
