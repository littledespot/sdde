//! Internal evaluator settings. Selection comes only from the test environment.
const std = @import("std");
const c = @import("contracts.zig");
const contracts = @import("../../src/domain/llm_provider_contracts.zig");
const registry = @import("../../src/composition/provider_model_contracts.zig").registry;
pub const Api = enum { openai_responses, bedrock_converse };
const ReasoningEffort = enum { none, minimal, low, medium, high, xhigh };
pub const Selection = struct { api: Api, model: c.ModelId, region: ?contracts.BedrockRegion = null, family: ?contracts.BedrockFamily = null };

/// Complete non-secret configuration retained in each evaluation report.
pub const Config = struct {
    schema: []const u8,
    api: Api,
    model: []const u8,
    region: ?contracts.BedrockRegion,
    /// The compiled Bedrock family the judge model is selected with (ADR 0029).
    family: ?contracts.BedrockFamily,
    reasoning_effort: ?ReasoningEffort,
    temperature: ?f64,
    timeout_ms: u32,
    retry_limit: u16,
    retry_delay_ms: u32,
    total_token_budget: u64,
    /// The judge model's documented maximum output, sent so the provider cannot
    /// apply a smaller default (ADR 0011). It is never a narrower allowance.
    max_output_tokens: contracts.ModelMaximumOutput,
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
    max_output_tokens: contracts.ModelMaximumOutput,
};

/// Values borrow from the caller-owned selection and JSON decoding arena.
pub fn parse(a: std.mem.Allocator, bytes: []const u8, selection: Selection) c.Error!Config {
    const settings = try c.decode(Settings, a, bytes);
    var value: Config = .{
        .schema = settings.schema,
        .api = selection.api,
        .model = selection.model.bytes,
        .region = selection.region,
        .family = selection.family,
        .reasoning_effort = settings.reasoning_effort,
        .temperature = settings.temperature,
        .timeout_ms = settings.timeout_ms,
        .retry_limit = settings.retry_limit,
        .retry_delay_ms = settings.retry_delay_ms,
        .total_token_budget = settings.total_token_budget,
        .max_output_tokens = settings.max_output_tokens,
    };
    if (selection.api == .bedrock_converse) {
        const required = try bedrockTemperature(value);
        if (settings.temperature != null and !std.meta.eql(settings.temperature, required)) return error.InvalidEvaluationContract;
        value.temperature = required;
    }
    try validate(value);
    return value;
}

pub fn validate(value: Config) c.Error!void {
    if (!std.mem.eql(u8, value.schema, "evaluation-config/v2") or c.ModelId.parse(value.model) == null or value.timeout_ms == 0 or
        value.total_token_budget == 0 or (value.retry_limit != 0 and value.retry_delay_ms == 0)) return error.InvalidEvaluationContract;
    if (value.temperature) |temperature| if (!std.math.isFinite(temperature) or temperature < 0 or temperature > 2) return error.InvalidEvaluationContract;
    switch (value.api) {
        .openai_responses => if (value.region != null or value.family != null) return error.InvalidEvaluationContract,
        .bedrock_converse => {
            const model = try bedrockContract(value);
            if (!model.capabilities.supports(.native_schema, model.capabilities.inferenceControls()) or
                !contracts.supportsReasoningEffort(model.supported_reasoning_efforts, if (value.reasoning_effort) |effort| @tagName(effort) else null)) return error.InvalidEvaluationContract;
            if (!std.meta.eql(value.temperature, try bedrockTemperature(value))) return error.InvalidEvaluationContract;
        },
    }
}

/// The compiled family contract that covers the selected judge model, Region and family.
pub fn bedrockContract(value: Config) c.Error!*const contracts.ProviderModelContract {
    const model = c.ModelId.parse(value.model) orelse return error.InvalidEvaluationContract;
    const config: contracts.ValidatedProviderConfig = .{ .aws_bedrock = .{
        .region = value.region orelse return error.InvalidEvaluationContract,
        .family = value.family orelse return error.InvalidEvaluationContract,
        .max_output_tokens = value.max_output_tokens,
    } };
    return registry.resolve(.{ .bytes = "aws-bedrock" }, model, config) orelse error.InvalidEvaluationContract;
}

fn bedrockTemperature(value: Config) c.Error!?f64 {
    const controls = (try bedrockContract(value)).capabilities.inferenceControls();
    return if (controls.temperature) |temperature| temperature.wireValue() else null;
}
