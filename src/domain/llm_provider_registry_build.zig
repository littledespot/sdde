const std = @import("std");
const contracts = @import("llm_provider_contracts.zig");
const config_schema = @import("llm_provider_config_schema.zig");
const document = @import("llm_provider_document.zig");
const identity = @import("llm_provider_identity.zig");
const registry = @import("llm_provider_registry.zig");

pub const Error = error{LLMProviderRegistryInvalid};

/// Builds the unvalidated registry candidate from the decoded provider document and the registered
/// provider contracts. Validation is `registry.createValidated`, a distinct step.
pub fn build(
    registered: *const contracts.Registry,
    allocator: std.mem.Allocator,
    raw: *const document.RawLLMProviderDocument,
) Error!registry.Candidate {
    registered.validate() catch return error.LLMProviderRegistryInvalid;

    var total: usize = 0;
    for (raw.providers, 0..) |provider, provider_index| {
        const provider_id = identity.ProviderId.parse(provider.provider) orelse {
            return error.LLMProviderRegistryInvalid;
        };
        if (!registered.containsProvider(provider_id)) {
            return error.LLMProviderRegistryInvalid;
        }
        for (raw.providers[0..provider_index]) |previous| {
            if (std.mem.eql(u8, provider.provider, previous.provider)) {
                return error.LLMProviderRegistryInvalid;
            }
        }
        total = std.math.add(usize, total, provider.models.len) catch {
            return error.LLMProviderRegistryInvalid;
        };
    }
    if (total > document.max_models_total) return error.LLMProviderRegistryInvalid;

    var candidate = registry.Candidate.init(allocator, total) catch {
        return error.LLMProviderRegistryInvalid;
    };
    errdefer candidate.deinit();

    var entry_index: usize = 0;
    for (raw.providers) |provider| {
        const provider_id = identity.ProviderId.parse(provider.provider).?;
        for (provider.models, 0..) |model, model_index| {
            const model_id = identity.ModelId.parse(model.model) orelse {
                return error.LLMProviderRegistryInvalid;
            };
            for (provider.models[0..model_index]) |previous| {
                if (std.mem.eql(u8, model.model, previous.model)) {
                    return error.LLMProviderRegistryInvalid;
                }
            }
            // The provider's family decodes the configuration, which then selects
            // the contract: an exact model, or a Bedrock entry's named family.
            const config = config_schema.decode(registered.configSchema(provider_id).?, model.config) orelse {
                return error.LLMProviderRegistryInvalid;
            };
            const resolved = registered.resolve(provider_id, model_id, config) orelse {
                return error.LLMProviderRegistryInvalid;
            };
            candidate.entries[entry_index] = .{
                .provider = provider_id,
                .json = model.json,
                .model = model_id,
                .implementation_id = resolved.implementation_id,
                .config = config,
                .supported_reasoning_efforts = resolved.supported_reasoning_efforts,
                .capabilities = resolved.capabilities,
            };
            entry_index += 1;
        }
    }
    std.mem.sort(registry.CandidateEntry, candidate.entries, {}, registry.lessThan);
    return candidate;
}
