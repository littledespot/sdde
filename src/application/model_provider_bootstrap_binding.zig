const config = @import("../domain/config.zig");
const bootstrap_root_registry = @import("../domain/bootstrap_root_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const orchestrator = @import("model_provider_bootstrap_orchestrator.zig");

pub const Binding = struct {
    context: *anyopaque,
    invoke_fn: *const fn (
        *anyopaque,
        *const execution.SelectedWorkflow,
        *const config.ModelsConfig,
        *const bootstrap_root_registry.LLMProviderConfigCapability,
    ) orchestrator.Outcome,

    pub fn invoke(
        self: Binding,
        selected: *const execution.SelectedWorkflow,
        models: *const config.ModelsConfig,
        capability: *const bootstrap_root_registry.LLMProviderConfigCapability,
    ) orchestrator.Outcome {
        return self.invoke_fn(self.context, selected, models, capability);
    }
};
