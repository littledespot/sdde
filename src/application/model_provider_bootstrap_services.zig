const allowlist_contract = @import("../domain/repository_model_allowlist.zig");
const registry_contract = @import("../domain/llm_provider_registry.zig");
const registry_service = @import("llm_provider_registry_service.zig");

pub const ModelProviderBootstrapServices = struct {
    provider_registry: registry_service.LLMProviderRegistryService,
    allowlist_owner: *allowlist_contract.Owner,

    pub fn init(
        provider_registry: registry_service.LLMProviderRegistryService,
        allowlist_owner: *allowlist_contract.Owner,
    ) ModelProviderBootstrapServices {
        return .{
            .provider_registry = provider_registry,
            .allowlist_owner = allowlist_owner,
        };
    }

    pub fn registry(
        self: *const ModelProviderBootstrapServices,
    ) *const registry_contract.ValidatedLLMProviderRegistry {
        return self.provider_registry.registry();
    }

    pub fn allowlist(
        self: *const ModelProviderBootstrapServices,
    ) *const allowlist_contract.ValidatedRepositoryModelAllowlist {
        return allowlist_contract.allowlist(self.allowlist_owner);
    }

    pub fn deinit(self: *ModelProviderBootstrapServices) void {
        allowlist_contract.deinitOwner(self.allowlist_owner);
        self.provider_registry.deinit();
        self.* = undefined;
    }
};
