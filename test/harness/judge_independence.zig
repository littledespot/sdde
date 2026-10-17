//! Pure model-identity evidence for development acceptance. This does not
//! authorize a model, invoke a provider, or establish grader accuracy.
const std = @import("std");
const contracts = @import("contracts.zig");
const configuration = @import("configuration.zig");
const config = @import("../../src/domain/config.zig");
const identity = @import("../../src/domain/llm_provider_identity.zig");
const registry = @import("../../src/composition/provider_model_contracts.zig").registry;

pub const Error = contracts.Error || error{InvalidGenerationIdentity};
pub const Result = union(enum) {
    independent,
    self_grading: contracts.GenerationModel,
    unknown_generation,
};

const Identity = struct {
    provider: identity.ProviderId,
    model: identity.ModelId,

    fn eql(left: Identity, right: Identity) bool {
        return left.provider.eql(right.provider) and left.model.eql(right.model);
    }
};

/// Preflight every configured slot, including repair and review roles. Returned
/// model strings borrow the caller's configuration.
pub fn fromConfigured(models: *const config.ModelsConfig, judge: configuration.Config) Error!Result {
    const selected = try judgeIdentity(judge);
    const slots = models.slots.map.keys();
    const values = models.slots.map.values();
    if (slots.len == 0) return .unknown_generation;
    var matching: ?contracts.GenerationModel = null;
    for (slots, values) |slot, value| {
        const generation: contracts.GenerationModel = .{
            .slot = slot,
            .provider = value.provider,
            .model = value.model,
        };
        const parsed = try generationIdentity(generation);
        if (matching == null and parsed.eql(selected)) matching = generation;
    }
    return if (matching) |value| .{ .self_grading = value } else .independent;
}

/// Recheck the actual observed generation models before grading. Missing model
/// provenance cannot establish independence; malformed provenance rejects.
pub fn fromObserved(models: []const contracts.GenerationModel, judge: configuration.Config) Error!Result {
    const selected = try judgeIdentity(judge);
    if (models.len == 0) return .unknown_generation;
    var matching: ?contracts.GenerationModel = null;
    for (models, 0..) |generation, index| {
        const parsed = try generationIdentity(generation);
        for (models[0..index]) |prior| {
            if (std.mem.eql(u8, prior.slot, generation.slot)) return error.InvalidGenerationIdentity;
        }
        if (matching == null and parsed.eql(selected)) matching = generation;
    }
    return if (matching) |value| .{ .self_grading = value } else .independent;
}

fn judgeIdentity(judge: configuration.Config) contracts.Error!Identity {
    try configuration.validate(judge);
    const selected: Identity = .{
        .provider = .{ .bytes = switch (judge.api) {
            .bedrock_converse => "aws-bedrock",
            .openai_responses => "openai",
        } },
        .model = identity.ModelId.parse(judge.model) orelse return error.InvalidEvaluationContract,
    };
    // A merely different unregistered name is no evidence of a different model.
    if (registry.resolve(selected.provider, selected.model) == null) return error.InvalidEvaluationContract;
    return selected;
}

fn generationIdentity(value: contracts.GenerationModel) error{InvalidGenerationIdentity}!Identity {
    _ = identity.ModelSlotId.parse(value.slot) orelse return error.InvalidGenerationIdentity;
    const selected: Identity = .{
        .provider = identity.ProviderId.parse(value.provider) orelse return error.InvalidGenerationIdentity,
        .model = identity.ModelId.parse(value.model) orelse return error.InvalidGenerationIdentity,
    };
    if (registry.resolve(selected.provider, selected.model) == null) return error.InvalidGenerationIdentity;
    return selected;
}
