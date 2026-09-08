//! Internal test environment only; never imported by the production executable.
const std = @import("std");
const c = @import("contracts.zig");
const configuration = @import("configuration.zig");
const http = @import("http.zig");

/// Selection borrows the invocation's immutable environment snapshot.
pub fn selection(environment: *const std.process.Environ.Map) c.Error!configuration.Selection {
    const provider = environment.get("TEST_EVALUATION_PROVIDER") orelse return error.InvalidEvaluationContract;
    const Provider = enum { openai, bedrock };
    const parsed = std.meta.stringToEnum(Provider, provider) orelse return error.InvalidEvaluationContract;
    const model = c.ModelId.parse(environment.get("TEST_EVALUATION_MODEL") orelse return error.InvalidEvaluationContract) orelse return error.InvalidEvaluationContract;
    const raw_region = environment.get("TEST_EVALUATION_REGION");
    return switch (parsed) {
        .openai => blk: {
            if (raw_region) |region| if (region.len != 0) return error.InvalidEvaluationContract;
            break :blk .{ .api = .openai_responses, .model = model };
        },
        .bedrock => .{ .api = .bedrock_converse, .model = model, .region = std.meta.stringToEnum(@import("../../src/domain/llm_provider_contracts.zig").BedrockRegion, raw_region orelse return error.InvalidEvaluationContract) orelse return error.InvalidEvaluationContract },
    };
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
