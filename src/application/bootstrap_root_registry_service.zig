const bootstrap_root_registry = @import("../domain/bootstrap_root_registry.zig");

pub const BootstrapRootRegistryService = struct {
    owner: *bootstrap_root_registry.Owner,

    pub fn init(owner: *bootstrap_root_registry.Owner) BootstrapRootRegistryService {
        return .{ .owner = owner };
    }

    pub fn registry(
        self: *const BootstrapRootRegistryService,
    ) *const bootstrap_root_registry.BootstrapRootRegistry {
        return bootstrap_root_registry.registry(self.owner);
    }

    pub fn deinit(self: *BootstrapRootRegistryService) void {
        bootstrap_root_registry.deinitOwner(self.owner);
        self.* = undefined;
    }
};
