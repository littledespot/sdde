const registry_contract = @import("../domain/llm_provider_registry.zig");

pub const LLMProviderRegistryService = struct {
    owner: *registry_contract.Owner,

    pub fn init(owner: *registry_contract.Owner) LLMProviderRegistryService {
        return .{ .owner = owner };
    }

    pub fn registry(
        self: *const LLMProviderRegistryService,
    ) *const registry_contract.ValidatedLLMProviderRegistry {
        return registry_contract.registry(self.owner);
    }

    pub fn deinit(self: *LLMProviderRegistryService) void {
        registry_contract.deinitOwner(self.owner);
        self.* = undefined;
    }
};
