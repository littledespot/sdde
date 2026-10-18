const std = @import("std");
const independence = @import("judge_independence.zig");
const contracts = @import("contracts.zig");
const configuration = @import("configuration.zig");
const config = @import("../../src/domain/config.zig");

const generator: contracts.GenerationModel = .{
    .slot = "spec_generation",
    .provider = "aws-bedrock",
    .model = "openai.gpt-oss-20b-1:0",
};

fn judge() configuration.Config {
    return .{
        .schema = "evaluation-config/v2",
        .api = .bedrock_converse,
        .model = generator.model,
        .region = .@"ap-southeast-2",
        .reasoning_effort = .low,
        .temperature = 0.1,
        .timeout_ms = 120000,
        .retry_limit = 0,
        .retry_delay_ms = 0,
        .total_token_budget = 150000,
        .max_output_tokens = .{ .tokens = 16000 },
    };
}

fn distinctJudge() configuration.Config {
    var value = judge();
    value.model = "global.openai.gpt-6-luna";
    value.reasoning_effort = null;
    value.temperature = null;
    return value;
}

test "judge independence compares every configured role without a fixed slot registry" {
    var models: config.ModelsConfig = .{ .slots = .{} };
    defer models.slots.deinit(std.testing.allocator);
    try models.slots.map.put(std.testing.allocator, "arbitrary generation role", .{ .provider = generator.provider, .model = "global.openai.gpt-6-luna" });
    try std.testing.expectEqual(.independent, std.meta.activeTag(try independence.fromConfigured(&models, judge())));
    for ([_][]const u8{ "source_review", "repair", "spec_generation" }) |slot| {
        try models.slots.map.put(std.testing.allocator, slot, .{ .provider = generator.provider, .model = generator.model });
        const result = try independence.fromConfigured(&models, judge());
        try std.testing.expectEqualStrings(slot, result.self_grading.slot);
        try std.testing.expectEqualStrings(generator.model, result.self_grading.model);
        try std.testing.expect(models.slots.map.swapRemove(slot));
    }
}

test "judge independence compares observed repair and review identities as well as generation" {
    for ([_][]const u8{ "source_review", "repair", "arbitrary authoring role" }) |slot| {
        const observed = [_]contracts.GenerationModel{
            .{ .slot = generator.slot, .provider = generator.provider, .model = "global.openai.gpt-6-luna" },
            .{ .slot = slot, .provider = generator.provider, .model = generator.model },
        };
        const result = try independence.fromObserved(&observed, judge());
        try std.testing.expectEqualStrings(slot, result.self_grading.slot);
    }
    try std.testing.expectEqual(.independent, std.meta.activeTag(try independence.fromObserved(&.{generator}, distinctJudge())));
}

test "different judge request controls do not make the same model independent" {
    var changed = judge();
    changed.reasoning_effort = .high;
    changed.timeout_ms = 30000;
    changed.total_token_budget = 50000;
    changed.retry_limit = 1;
    changed.retry_delay_ms = 10;
    const result = try independence.fromObserved(&.{generator}, changed);
    try std.testing.expectEqualDeep(generator, result.self_grading);
}

test "missing generation identities remain unknown after judge validation" {
    var models: config.ModelsConfig = .{ .slots = .{} };
    defer models.slots.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unknown_generation, std.meta.activeTag(try independence.fromConfigured(&models, judge())));
    try std.testing.expectEqual(.unknown_generation, std.meta.activeTag(try independence.fromObserved(&.{}, judge())));
    var malformed = judge();
    malformed.timeout_ms = 0;
    try std.testing.expectError(error.InvalidEvaluationContract, independence.fromObserved(&.{}, malformed));
    try std.testing.expectError(error.InvalidEvaluationContract, independence.fromConfigured(&models, malformed));
}

test "malformed and unregistered identities cannot claim independence or hide behind a match" {
    for ([_]contracts.GenerationModel{
        .{ .slot = "", .provider = generator.provider, .model = generator.model },
        .{ .slot = "repair", .provider = "AWS-bedrock", .model = generator.model },
        .{ .slot = "repair", .provider = generator.provider, .model = "" },
        .{ .slot = "repair", .provider = generator.provider, .model = "unknown-model" },
        .{ .slot = "repair", .provider = "openai", .model = generator.model },
    }) |malformed| {
        try std.testing.expectError(error.InvalidGenerationIdentity, independence.fromObserved(&.{ generator, malformed }, judge()));
        var models: config.ModelsConfig = .{ .slots = .{} };
        defer models.slots.deinit(std.testing.allocator);
        try models.slots.map.put(std.testing.allocator, generator.slot, .{ .provider = generator.provider, .model = generator.model });
        try models.slots.map.put(std.testing.allocator, malformed.slot, .{ .provider = malformed.provider, .model = malformed.model });
        try std.testing.expectError(error.InvalidGenerationIdentity, independence.fromConfigured(&models, judge()));
    }
    try std.testing.expectError(error.InvalidGenerationIdentity, independence.fromObserved(&.{ generator, generator }, judge()));
    var malformed = judge();
    malformed.model = "unknown-model";
    try std.testing.expectError(error.InvalidEvaluationContract, independence.fromObserved(&.{generator}, malformed));
}
