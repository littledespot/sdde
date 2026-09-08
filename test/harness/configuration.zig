//! Internal evaluator settings. Selection comes only from the test environment.
const std = @import("std");
const c = @import("contracts.zig");
const contracts = @import("../../src/domain/llm_provider_contracts.zig");
const registry = @import("../../src/composition/provider_model_contracts.zig").registry;
pub const Api = enum { openai_responses, bedrock_converse };
const ReasoningEffort = enum { none, minimal, low, medium, high, xhigh };
pub const Selection = struct { api: Api, model: c.ModelId, region: ?contracts.BedrockRegion = null };

/// Complete non-secret configuration retained in each evaluation report.
pub const Config = struct {
    schema: []const u8,
    api: Api,
    model: []const u8,
    region: ?contracts.BedrockRegion,
    reasoning_effort: ?ReasoningEffort,
    temperature: ?f64,
    timeout_ms: u32,
    retry_limit: u16,
    retry_delay_ms: u32,
    total_token_budget: u64,
};

/// Closed JSON input: provider/model and credentials cannot be supplied here.
const Settings = struct {
    schema: []const u8,
    reasoning_effort: ?ReasoningEffort,
    temperature: ?f64,
    timeout_ms: u32,
    retry_limit: u16,
    retry_delay_ms: u32,
    total_token_budget: u64,
};

/// Values borrow from the caller-owned selection and JSON decoding arena.
pub fn parse(a: std.mem.Allocator, bytes: []const u8, selection: Selection) c.Error!Config {
    const settings = try c.decode(Settings, a, bytes);
    const value: Config = .{
        .schema = settings.schema,
        .api = selection.api,
        .model = selection.model.bytes,
        .region = selection.region,
        .reasoning_effort = settings.reasoning_effort,
        .temperature = settings.temperature,
        .timeout_ms = settings.timeout_ms,
        .retry_limit = settings.retry_limit,
        .retry_delay_ms = settings.retry_delay_ms,
        .total_token_budget = settings.total_token_budget,
    };
    try validate(value);
    return value;
}

pub fn validate(value: Config) c.Error!void {
    if (!std.mem.eql(u8, value.schema, "evaluation-config/v1") or c.ModelId.parse(value.model) == null or value.timeout_ms == 0 or
        value.total_token_budget == 0 or (value.retry_limit != 0 and value.retry_delay_ms == 0)) return error.InvalidEvaluationContract;
    if (value.temperature) |temperature| if (!std.math.isFinite(temperature) or temperature < 0 or temperature > 2) return error.InvalidEvaluationContract;
    switch (value.api) {
        .openai_responses => if (value.region != null) return error.InvalidEvaluationContract,
        .bedrock_converse => {
            const region = value.region orelse return error.InvalidEvaluationContract;
            const model = registry.resolve(.{ .bytes = "aws-bedrock" }, c.ModelId.parse(value.model).?) orelse return error.InvalidEvaluationContract;
            if (!model.acceptsConfig(.{ .aws_bedrock = .{ .region = region } }) or !model.capabilities.inference or
                !contracts.supportsReasoningEffort(model.supported_reasoning_efforts, if (value.reasoning_effort) |effort| @tagName(effort) else null)) return error.InvalidEvaluationContract;
            if (value.temperature) |temperature| if (!model.capabilities.temperature or temperature > 1) return error.InvalidEvaluationContract;
        },
    }
}
