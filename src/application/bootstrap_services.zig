const sddtoolkit_config_service = @import("sddtoolkit_config_service.zig");
const bootstrap_root_registry_service = @import("bootstrap_root_registry_service.zig");

pub const BootstrapServices = struct {
    config: sddtoolkit_config_service.SDDToolKitConfigService,
    roots: bootstrap_root_registry_service.BootstrapRootRegistryService,

    pub fn deinit(self: *BootstrapServices) void {
        self.roots.deinit();
        self.config.deinit();
        self.* = undefined;
    }
};
