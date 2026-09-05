const std = @import("std");
const contracts = @import("../../domain/llm_provider_contracts.zig");
const config_schema = @import("../../domain/llm_provider_config_schema.zig");
const document = @import("../../domain/llm_provider_document.zig");
const identity = @import("../../domain/llm_provider_identity.zig");
const pipeline = @import("../../domain/pipeline.zig");
const registry = @import("../../domain/llm_provider_registry.zig");

pub const Error = error{LLMProviderRegistryInvalid};

pub const Action = struct {
    contracts: *const contracts.Registry,

    pub const contract: pipeline.NodeContract = .{
        .id = "build-llm-provider-registry@1",
        .kind = .action,
        .requires = &.{.raw_llm_provider_document},
        .produces = &.{.llm_provider_registry_candidate},
        .side_effect = .none,
    };

    pub fn execute(
        self: Action,
        allocator: std.mem.Allocator,
        raw: *const document.RawLLMProviderDocument,
    ) Error!registry.Candidate {
        self.contracts.validate() catch return error.LLMProviderRegistryInvalid;

        var total: usize = 0;
        for (raw.providers, 0..) |provider, provider_index| {
            const provider_id = identity.ProviderId.parse(provider.provider) orelse {
                return error.LLMProviderRegistryInvalid;
            };
            if (!self.contracts.containsProvider(provider_id)) {
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
                const registered = self.contracts.resolve(provider_id, model_id) orelse {
                    return error.LLMProviderRegistryInvalid;
                };
                candidate.entries[entry_index] = .{
                    .provider = provider_id,
                    .model = model_id,
                    .implementation_id = registered.implementation_id,
                    .config = config_schema.decode(registered.config_schema, model.config) orelse {
                        return error.LLMProviderRegistryInvalid;
                    },
                    .supported_reasoning_efforts = registered.supported_reasoning_efforts,
                    .capabilities = registered.capabilities,
                };
                entry_index += 1;
            }
        }
        std.mem.sort(registry.CandidateEntry, candidate.entries, {}, registry.lessThan);
        return candidate;
    }
};
