//! Internal test environment only; never imported by the production executable.
const std = @import("std");
const c = @import("contracts.zig");
const configuration = @import("configuration.zig");
const http = @import("http.zig");

/// Selection borrows the invocation's immutable environment snapshot.
pub fn selection(environment: *const std.process.Environ.Map) c.Error!configuration.Selection {
    const provider = environment.get("TEST_EVALUATION_PROVIDER") orelse return error.InvalidEvaluationContract;
    const Provider = enum { openai };
    const parsed = std.meta.stringToEnum(Provider, provider) orelse return error.InvalidEvaluationContract;
    const model = c.ModelId.parse(environment.get("TEST_EVALUATION_MODEL") orelse return error.InvalidEvaluationContract) orelse return error.InvalidEvaluationContract;
    return .{ .api = switch (parsed) {
        .openai => .openai_responses,
    }, .model = model };
}

/// Credentials remain separate from configuration, requests and reports.
pub fn credential(environment: *const std.process.Environ.Map) error{ MissingTestApiKey, InvalidTestApiKey }![]const u8 {
    const key = environment.get("TEST_OPENAI_API_KEY") orelse return error.MissingTestApiKey;
    if (!http.validKey(key)) return error.InvalidTestApiKey;
    return key;
}
