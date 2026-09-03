const std = @import("std");
const pipeline = @import("../domain/pipeline.zig");
const bootstrap_root_registry = @import("../domain/bootstrap_root_registry.zig");
const config = @import("../domain/config.zig");
const contracts = @import("../domain/llm_provider_contracts.zig");
const execution = @import("../domain/workflow_execution.zig");
const llm_provider_config_source = @import("../adapters/filesystem/llm_provider_config_source.zig");
const locate_llm_provider_config = @import("../actions/provider/locate_llm_provider_config.zig");
const read_llm_provider_config = @import("../actions/provider/read_llm_provider_config.zig");
const binding = @import("../application/model_provider_bootstrap_binding.zig");
const llm_provider_config_runner = @import("../application/llm_provider_config_runner.zig");
const orchestrator = @import("../application/model_provider_bootstrap_orchestrator.zig");
const runner = @import("../application/model_provider_bootstrap_runner.zig");

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
        capability: *const bootstrap_root_registry.LLMProviderConfigCapability,
    ) orchestrator.Outcome {
        const self: *Assembly = @ptrCast(@alignCast(context));
        var source_adapter = llm_provider_config_source.Adapter.init(self.io, self.project_root);
        var config_runner = llm_provider_config_runner.Runner.init(
            self.allocator,
            self.runtime,
            capability,
            locate_llm_provider_config.Action{ .locator = source_adapter.locator() },
            read_llm_provider_config.Action{},
        );
        defer config_runner.deinit();

        var provider_runner = runner.Runner.init(
            self.allocator,
            self.runtime,
            selected,
            models,
            &config_runner,
            self.registered_contracts,
        );
        defer provider_runner.deinit();
        return orchestrator.run(provider_runner.childBindings());
    }
};
