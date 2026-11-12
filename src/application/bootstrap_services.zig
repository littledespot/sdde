const sddtoolkit_config_service = @import("sddtoolkit_config_service.zig");
const bootstrap_root_registry_service = @import("bootstrap_root_registry_service.zig");
const log_service = @import("log_service.zig");
const workflow_definition_registry_service = @import("workflow_definition_registry_service.zig");

const bootstrap_error = @import("../domain/bootstrap_error.zig");

/// The result of startup: the services, each built only after its complete validation, or a
/// public failure, or an explicit cancellation.
pub const Outcome = union(enum) {
    ready: BootstrapServices,
    failed: bootstrap_error.PublicError,
    cancelled,

    pub fn deinit(self: *Outcome) void {
        switch (self.*) {
            .ready => |*services| services.deinit(),
            .failed, .cancelled => {},
        }
        self.* = undefined;
    }
};

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
