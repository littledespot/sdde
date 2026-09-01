const std = @import("std");
const config = @import("../../domain/config.zig");
const allowlist = @import("../../domain/repository_model_allowlist.zig");
const pipeline = @import("../../domain/pipeline.zig");
const registry = @import("../../domain/llm_provider_registry.zig");

pub const Error = error{LLMProviderModelBindingInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-repository-model-allowlist@1",
        .kind = .action,
        .requires = &.{ .engine_config, .llm_provider_registry },
        .produces = &.{.repository_model_allowlist},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        models: *const config.ModelsConfig,
        provider_registry: *const registry.ValidatedLLMProviderRegistry,
    ) Error!*allowlist.Owner {
        return allowlist.createValidated(allocator, models, provider_registry) catch {
            return error.LLMProviderModelBindingInvalid;
        };
    }
};
