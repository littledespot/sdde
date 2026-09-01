const std = @import("std");
const contracts = @import("../../domain/llm_provider_contracts.zig");
const pipeline = @import("../../domain/pipeline.zig");
const registry = @import("../../domain/llm_provider_registry.zig");

pub const Error = error{LLMProviderRegistryInvalid};

pub const Action = struct {
    contracts: *const contracts.Registry,

    pub const contract: pipeline.NodeContract = .{
        .id = "validate-llm-provider-registry@1",
        .kind = .action,
        .requires = &.{.llm_provider_registry_candidate},
        .produces = &.{.llm_provider_registry},
        .side_effect = .none,
    };

    pub fn execute(
        self: Action,
        allocator: std.mem.Allocator,
        candidate: registry.Candidate,
    ) Error!*registry.Owner {
        return registry.createValidated(allocator, candidate, self.contracts.*) catch {
            return error.LLMProviderRegistryInvalid;
        };
    }
};
