//! A single evaluator operation; no workflow, file, scoring or tool capability.
const std = @import("std");
const c = @import("contracts.zig");
const configuration = @import("configuration.zig");
const report = @import("report.zig");
pub const Identity = union(enum) {
    unavailable,
    openai_response: struct { response_id: []const u8, actual_model: []const u8 },
    bedrock_target: struct { model: []const u8, region: @import("../../src/domain/llm_provider_contracts.zig").BedrockRegion },

    pub fn validFor(self: Identity, config: configuration.Config) bool {
        return switch (self) {
            .unavailable => false,
            .openai_response => |value| config.api == .openai_responses and c.id(value.response_id) and c.ModelId.parse(value.actual_model) != null,
            .bedrock_target => |value| config.api == .bedrock_converse and config.region == value.region and std.mem.eql(u8, config.model, value.model),
        };
    }
};
pub const Observation = struct {
    request_id: ?[]const u8 = null,
    identity: Identity = .unavailable,
    usage: ?report.Usage = null,
    failure: ?report.Failure = null,
    payload: ?[]const u8 = null,
};
pub const Context = opaque {};
pub const Error = std.mem.Allocator.Error || error{Cancelled};
pub const Port = struct {
    context: *Context,
    invoke_fn: *const fn (*Context, std.mem.Allocator, []const u8, u32) Error!Observation,
    pub fn invoke(self: Port, a: std.mem.Allocator, body: []const u8, timeout_ms: u32) Error!Observation {
        return self.invoke_fn(self.context, a, body, timeout_ms);
    }
};
