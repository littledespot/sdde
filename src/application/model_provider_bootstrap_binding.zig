const bootstrap_error = @import("../domain/bootstrap_error.zig");
const config = @import("../domain/config.zig");
const bootstrap_root_registry = @import("../domain/bootstrap_root_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const registry_service = @import("llm_provider_registry_service.zig");
const routine = @import("model_provider_bootstrap_routine.zig");
const services = @import("model_provider_bootstrap_services.zig");

/// The result of provider bootstrap for the selected workflow. The services are built here, from the
/// routine's validated owners, only after every step has validated.
pub const Outcome = union(enum) {
    not_required,
    ready: services.ModelProviderBootstrapServices,
    failed: bootstrap_error.PublicError,
    cancelled,

    pub fn deinit(self: *Outcome) void {
        switch (self.*) {
            .ready => |*value| value.deinit(),
            .not_required, .failed, .cancelled => {},
        }
        self.* = undefined;
    }
};

pub fn fromRoutine(outcome: routine.Outcome) Outcome {
    return switch (outcome) {
        .not_required => .not_required,
        .ready => |ready| .{ .ready = services.ModelProviderBootstrapServices.init(
            registry_service.LLMProviderRegistryService.init(ready.provider_registry),
            ready.allowlist,
        ) },
        .failed => |failure| .{ .failed = failure },
        .cancelled => .cancelled,
    };
}

pub const Binding = struct {
    context: *anyopaque,
    invoke_fn: *const fn (
        *anyopaque,
        *const execution.SelectedWorkflow,
        *const config.ModelsConfig,
        @import("../domain/model_controls.zig").Temperatures,
        *const bootstrap_root_registry.LLMProviderConfigCapability,
    ) Outcome,

    pub fn invoke(
        self: Binding,
        selected: *const execution.SelectedWorkflow,
        models: *const config.ModelsConfig,
        temperatures: @import("../domain/model_controls.zig").Temperatures,
        capability: *const bootstrap_root_registry.LLMProviderConfigCapability,
    ) Outcome {
        return self.invoke_fn(self.context, selected, models, temperatures, capability);
    }
};
