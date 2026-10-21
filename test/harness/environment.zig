//! Internal test environment only; never imported by the production executable.
const std = @import("std");
const c = @import("contracts.zig");
const configuration = @import("configuration.zig");
const http = @import("http.zig");

/// Selection borrows the invocation's immutable environment snapshot.
pub fn selection(environment: *const std.process.Environ.Map) (c.Error || @import("model_cost_policy.zig").Error)!configuration.Selection {
    const provider = environment.get("TEST_EVALUATION_PROVIDER") orelse return error.InvalidEvaluationContract;
    const Provider = enum { openai, bedrock };
    const parsed = std.meta.stringToEnum(Provider, provider) orelse return error.InvalidEvaluationContract;
    const model = c.ModelId.parse(environment.get("TEST_EVALUATION_MODEL") orelse return error.InvalidEvaluationContract) orelse return error.InvalidEvaluationContract;
    const raw_region = environment.get("TEST_EVALUATION_REGION");
    const raw_family = environment.get("TEST_EVALUATION_FAMILY");
    const domain = @import("../../src/domain/llm_provider_contracts.zig");
    const selected: configuration.Selection = switch (parsed) {
        .openai => blk: {
            if (raw_region) |region| if (region.len != 0) return error.InvalidEvaluationContract;
            if (raw_family) |family| if (family.len != 0) return error.InvalidEvaluationContract;
            break :blk .{ .api = .openai_responses, .model = model };
        },
        .bedrock => .{
            .api = .bedrock_converse,
            .model = model,
            .region = std.meta.stringToEnum(domain.BedrockRegion, raw_region orelse return error.InvalidEvaluationContract) orelse return error.InvalidEvaluationContract,
            .family = std.meta.stringToEnum(domain.BedrockFamily, raw_family orelse return error.InvalidEvaluationContract) orelse return error.InvalidEvaluationContract,
        },
    };
    try @import("model_cost_policy.zig").require(.judge, .{ .bytes = if (parsed == .bedrock) "aws-bedrock" else "openai" }, selected.model);
    return selected;
}

/// Credentials remain separate from configuration, requests and reports.
pub fn credentialName(api: configuration.Api) []const u8 {
    return switch (api) {
        .openai_responses => "TEST_OPENAI_API_KEY",
        .bedrock_converse => "TEST_AWS_BEARER_TOKEN_BEDROCK",
    };
}

pub fn credential(environment: *const std.process.Environ.Map, api: configuration.Api) error{ MissingTestApiKey, InvalidTestApiKey }![]const u8 {
    const key = environment.get(credentialName(api)) orelse return error.MissingTestApiKey;
    if (!http.validKey(key)) return error.InvalidTestApiKey;
    return key;
}

const Family = @import("../../src/adapters/provider/provider_api_key.zig").Family;

/// Test generation keys, one per provider family a case's slots select.
pub const GenerationKeys = std.EnumArray(Family, ?[]const u8);

/// The one test variable each generation family reads; production variables
/// never stand in (ADR 0028).
pub fn generationKeyName(family: Family) []const u8 {
    return switch (family) {
        .aws_bedrock => "TEST_AWS_BEARER_TOKEN_BEDROCK",
        .anthropic => "TEST_ANTHROPIC_API_KEY",
    };
}

/// Read exactly the keys of the families the configured slots select, after
/// the cost policy has accepted every slot.
pub fn generationKeys(environment: *const std.process.Environ.Map, models: *const @import("../../src/domain/config.zig").ModelsConfig) error{ MissingTestApiKey, InvalidTestApiKey, DisallowedTestModel }!GenerationKeys {
    var keys: GenerationKeys = .initFill(null);
    for (models.slots.map.values()) |slot| {
        const family = for (std.enums.values(Family)) |candidate| {
            if (std.mem.eql(u8, candidate.configSchema().providerId().?, slot.provider)) break candidate;
        } else return error.DisallowedTestModel;
        if (keys.get(family) != null) continue;
        const key = environment.get(generationKeyName(family)) orelse return error.MissingTestApiKey;
        if (!http.validKey(key)) return error.InvalidTestApiKey;
        keys.set(family, key);
    }
    return keys;
}

/// Every read generation key, for redaction from all captures.
pub fn secrets(allocator: std.mem.Allocator, keys: GenerationKeys) std.mem.Allocator.Error![]const []const u8 {
    var values: std.ArrayList([]const u8) = .empty;
    errdefer values.deinit(allocator);
    for (std.enums.values(Family)) |family| if (keys.get(family)) |key| try values.append(allocator, key);
    return values.toOwnedSlice(allocator);
}

/// A harness that fixes the frozen Bedrock cohort supplies only that key.
pub fn bedrockOnly(key: ?[]const u8) GenerationKeys {
    var keys: GenerationKeys = .initFill(null);
    keys.set(.aws_bedrock, key);
    return keys;
}

test "generation keys follow the configured slots' families and nothing else" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var models: @import("../../src/domain/config.zig").ModelsConfig = .{ .slots = .{} };
    defer models.slots.deinit(std.testing.allocator);
    try models.slots.map.put(std.testing.allocator, "generation", .{ .provider = "anthropic", .model = "claude-haiku-5-5" });
    // Production variables and another family's test key never stand in.
    try environment.put("ANTHROPIC_API_KEY", "production-key");
    try environment.put("TEST_AWS_BEARER_TOKEN_BEDROCK", "bedrock-test-key");
    try std.testing.expectError(error.MissingTestApiKey, generationKeys(&environment, &models));
    try environment.put("TEST_ANTHROPIC_API_KEY", "invalid key");
    try std.testing.expectError(error.InvalidTestApiKey, generationKeys(&environment, &models));
    try environment.put("TEST_ANTHROPIC_API_KEY", "anthropic-test-key");
    var keys = try generationKeys(&environment, &models);
    try std.testing.expectEqualStrings("anthropic-test-key", keys.get(.anthropic).?);
    try std.testing.expect(keys.get(.aws_bedrock) == null);
    try models.slots.map.put(std.testing.allocator, "repair", .{ .provider = "aws-bedrock", .model = "openai.gpt-oss-20b-1:0" });
    keys = try generationKeys(&environment, &models);
    const all = try secrets(std.testing.allocator, keys);
    defer std.testing.allocator.free(all);
    try std.testing.expectEqual(@as(usize, 2), all.len);
    try models.slots.map.put(std.testing.allocator, "audit", .{ .provider = "openai", .model = "gpt-6-sol" });
    try std.testing.expectError(error.DisallowedTestModel, generationKeys(&environment, &models));
}
