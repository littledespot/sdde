//! Shared closed projection of one physically captured E2E provider exchange.
//! New captures are `model-call-evidence/v2`, which names the provider and its
//! catalogue configuration (ADR 0028). Version 1 captures, which could only
//! describe a Bedrock region, stay readable as historical evidence through the
//! explicit reader selected by their exact schema value; they grant no current
//! authority.
const std = @import("std");
const operation = @import("../../../src/domain/llm_provider_operation.zig");
const ids = @import("../../../src/domain/llm_provider_identity.zig");
const workflow = @import("../../../src/domain/workflow.zig");
const contracts = @import("../../../src/domain/llm_provider_contracts.zig");
const strict = @import("../../../src/domain/strict_json.zig");

pub const CallContext = struct {
    schema: enum { @"model-call-evidence/v2" },
    call: usize,
    origin: @import("../../../src/domain/model_candidate_origin.zig").Origin,
    request_step: []const u8,
    slot: []const u8,
    attempt: u32,
    provider: []const u8,
    model: []const u8,
    provider_config: contracts.ValidatedProviderConfig,
    kind: operation.ProviderOperationKind,
    reasoning_effort: ?[]const u8,
    content: []const operation.ModelVisibleContent,
    response_schema: []const u8,
    response_mode: @import("../../../src/domain/model_controls.zig").ResponseGuidanceMode,

    pub fn decode(a: std.mem.Allocator, bytes: []const u8) !CallContext {
        const value = try strict.decode(CallContext, a, bytes, .{ .maximum_depth = 64 });
        try validCommon(value.common());
        // The configuration's family must be the named provider's own.
        const family = std.meta.activeTag(value.provider_config).providerId() orelse return error.InvalidCallContext;
        if (ids.ProviderId.parse(value.provider) == null or !std.mem.eql(u8, family, value.provider)) return error.InvalidCallContext;
        return value;
    }

    pub fn common(self: CallContext) Common {
        return .{ .call = self.call, .origin = self.origin, .request_step = self.request_step, .slot = self.slot, .attempt = self.attempt, .model = self.model, .kind = self.kind, .reasoning_effort = self.reasoning_effort, .content = self.content, .response_schema = self.response_schema, .response_mode = self.response_mode };
    }
};

/// The retired v1 shape, read only as historical evidence.
pub const HistoricalCallContextV1 = struct {
    schema: enum { @"model-call-evidence/v1" },
    call: usize,
    origin: @import("../../../src/domain/model_candidate_origin.zig").Origin,
    request_step: []const u8,
    slot: []const u8,
    attempt: u32,
    model: []const u8,
    region: contracts.BedrockRegion,
    kind: operation.ProviderOperationKind,
    reasoning_effort: ?[]const u8,
    content: []const operation.ModelVisibleContent,
    response_schema: []const u8,
    response_mode: @import("../../../src/domain/model_controls.zig").ResponseGuidanceMode,

    pub fn common(self: HistoricalCallContextV1) Common {
        return .{ .call = self.call, .origin = self.origin, .request_step = self.request_step, .slot = self.slot, .attempt = self.attempt, .model = self.model, .kind = self.kind, .reasoning_effort = self.reasoning_effort, .content = self.content, .response_schema = self.response_schema, .response_mode = self.response_mode };
    }
};

/// Fields every evidence version records identically.
pub const Common = struct {
    call: usize,
    origin: @import("../../../src/domain/model_candidate_origin.zig").Origin,
    request_step: []const u8,
    slot: []const u8,
    attempt: u32,
    model: []const u8,
    kind: operation.ProviderOperationKind,
    reasoning_effort: ?[]const u8,
    content: []const operation.ModelVisibleContent,
    response_schema: []const u8,
    response_mode: @import("../../../src/domain/model_controls.zig").ResponseGuidanceMode,
};

/// One captured context, dispatched by its exact schema value.
pub const Captured = union(enum) {
    current: CallContext,
    historical_v1: HistoricalCallContextV1,

    pub fn decode(a: std.mem.Allocator, bytes: []const u8) !Captured {
        const Header = struct { schema: []const u8 };
        var header = std.json.parseFromSlice(Header, a, bytes, .{ .ignore_unknown_fields = true }) catch return error.InvalidCallContext;
        defer header.deinit();
        if (std.mem.eql(u8, header.value.schema, "model-call-evidence/v2")) return .{ .current = try CallContext.decode(a, bytes) };
        if (std.mem.eql(u8, header.value.schema, "model-call-evidence/v1")) {
            const value = try strict.decode(HistoricalCallContextV1, a, bytes, .{ .maximum_depth = 64 });
            try validCommon(value.common());
            return .{ .historical_v1 = value };
        }
        return error.InvalidCallContext;
    }

    pub fn common(self: Captured) Common {
        return switch (self) {
            inline else => |value| value.common(),
        };
    }

    /// Whether a request description's provider configuration is the one this
    /// capture recorded. A v1 capture records only a Bedrock region.
    pub fn recordsConfig(self: Captured, provider: []const u8, config: contracts.ValidatedProviderConfig) bool {
        return switch (self) {
            .current => |value| std.mem.eql(u8, value.provider, provider) and std.meta.eql(value.provider_config, config),
            .historical_v1 => |value| std.mem.eql(u8, provider, "aws-bedrock") and config == .aws_bedrock and config.aws_bedrock.region == value.region,
        };
    }
};

fn validCommon(value: Common) error{InvalidCallContext}!void {
    if (value.call == 0 or value.attempt == 0 or value.origin.attempt.value != value.attempt or value.origin.kind != value.kind or
        workflow.WorkflowStepId.parse(value.request_step) == null or ids.ModelSlotId.parse(value.slot) == null or
        ids.ModelId.parse(value.model) == null or value.content.len == 0 or value.response_schema.len == 0) return error.InvalidCallContext;
}
