const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const retry = @import("../../domain/model_protocol_retry.zig");
const preparation = @import("../../domain/model_request_preparation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-model-protocol-retry", .kind = .action, .requires = &.{ .model_request_identity_ledger, .validated_model_request, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .model_payload_schema_result }, .replaces = &.{.prepared_model_request}, .invalidates = &@import("../../domain/model_transport.zig").attempt_keys, .produces = &.{}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, source: preparation.Source, base_content: []const @import("../../domain/llm_provider_operation.zig").ModelVisibleContent, rejected: *const @import("../../domain/provider_invocation_validation.zig").CompleteCandidate, diagnostic: retry.Diagnostic, prompt: []const u8) preparation.Error!preparation.Owned {
        return retry.build(allocator, source, base_content, rejected, diagnostic, prompt);
    }
};
