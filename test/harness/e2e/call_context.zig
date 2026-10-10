//! Shared closed projection of one physically captured E2E provider exchange.
const std = @import("std");
const operation = @import("../../../src/domain/llm_provider_operation.zig");
const ids = @import("../../../src/domain/llm_provider_identity.zig");
const workflow = @import("../../../src/domain/workflow.zig");

pub const CallContext = struct {
    schema: enum { @"model-call-evidence/v1" },
    call: usize,
    origin: @import("../../../src/domain/model_candidate_origin.zig").Origin,
    request_step: []const u8,
    slot: []const u8,
    attempt: u32,
    model: []const u8,
    region: @import("../../../src/domain/llm_provider_contracts.zig").BedrockRegion,
    kind: operation.ProviderOperationKind,
    reasoning_effort: ?[]const u8,
    content: []const operation.ModelVisibleContent,
    response_schema: []const u8,
    response_mode: @import("../../../src/domain/model_controls.zig").ResponseGuidanceMode,

    pub fn decode(a: std.mem.Allocator, bytes: []const u8) !CallContext {
        const value = try @import("../../../src/domain/strict_json.zig").decode(CallContext, a, bytes, .{ .maximum_depth = 64 });
        if (value.call == 0 or value.attempt == 0 or value.origin.attempt.value != value.attempt or value.origin.kind != value.kind or
            workflow.WorkflowStepId.parse(value.request_step) == null or ids.ModelSlotId.parse(value.slot) == null or
            ids.ModelId.parse(value.model) == null or value.content.len == 0 or value.response_schema.len == 0) return error.InvalidCallContext;
        return value;
    }
};
