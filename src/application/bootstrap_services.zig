const sddtoolkit_config_service = @import("sddtoolkit_config_service.zig");
const bootstrap_root_registry_service = @import("bootstrap_root_registry_service.zig");
const log_service = @import("log_service.zig");
const workflow_definition_registry_service = @import("workflow_definition_registry_service.zig");

pub const BootstrapServices = struct {
    config: sddtoolkit_config_service.SDDToolKitConfigService,
    roots: bootstrap_root_registry_service.BootstrapRootRegistryService,
    logs: log_service.LogService,
    workflows: workflow_definition_registry_service.WorkflowDefinitionRegistryService,

    pub fn deinit(self: *BootstrapServices) void {
        self.workflows.deinit();
        self.logs.deinit();
        self.roots.deinit();
        self.config.deinit();
        self.* = undefined;
    }
};
