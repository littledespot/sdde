//! Internal evaluator settings. Selection comes only from the test environment.
const std = @import("std");
const c = @import("contracts.zig");
const Api = enum { openai_responses };
const ReasoningEffort = enum { none, minimal, low, medium, high, xhigh };
pub const Selection = struct { api: Api, model: c.ModelId };

/// Complete non-secret configuration retained in each evaluation report.
pub const Config = struct {
    schema: []const u8,
    api: Api,
    model: []const u8,
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
}
