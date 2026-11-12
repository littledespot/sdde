const std = @import("std");
const pipeline = @import("../domain/pipeline.zig");
const bootstrap_root_registry = @import("../domain/bootstrap_root_registry.zig");
const config = @import("../domain/config.zig");
const contracts = @import("../domain/llm_provider_contracts.zig");
const execution = @import("../domain/workflow_execution.zig");
const llm_provider_config_source = @import("../adapters/filesystem/llm_provider_config_source.zig");
const binding = @import("../application/model_provider_bootstrap_binding.zig");
const routine = @import("../application/model_provider_bootstrap_routine.zig");

/// Builds the provider-bootstrap binding's one port and runs the routine on its behalf (ADR 0032).
pub const Assembly = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    project_root: std.Io.Dir,
    runtime: pipeline.NodeRuntime,
    registered_contracts: *const contracts.Registry,

    pub fn init(
        io: std.Io,
        allocator: std.mem.Allocator,
        project_root: std.Io.Dir,
        runtime: pipeline.NodeRuntime,
        registered_contracts: *const contracts.Registry,
    ) Assembly {
        return .{
            .io = io,
            .allocator = allocator,
            .project_root = project_root,
            .runtime = runtime,
            .registered_contracts = registered_contracts,
        };
    }

    pub fn bind(self: *Assembly) binding.Binding {
        return .{ .context = self, .invoke_fn = invoke };
    }

    fn invoke(
        context: *anyopaque,
        selected: *const execution.SelectedWorkflow,
        models: *const config.ModelsConfig,
        temperatures: @import("../domain/model_controls.zig").Temperatures,
        capability: *const bootstrap_root_registry.LLMProviderConfigCapability,
    ) binding.Outcome {
        const self: *Assembly = @ptrCast(@alignCast(context));
        var source_adapter = llm_provider_config_source.Adapter.init(self.io, self.project_root);
        var diagnostic: routine.Diagnostic = .{};
        return binding.fromRoutine(routine.run(
            .{ .locator = source_adapter.locator() },
            self.allocator,
            self.runtime,
            &diagnostic,
            .{
                .selected = selected,
                .models = models,
                .temperatures = temperatures,
                .capability = capability,
                .registered = self.registered_contracts,
            },
        ));
    }
};
