const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const preparation = @import("../../domain/model_request_preparation.zig");
const validation = @import("../../domain/provider_invocation_validation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-model-runaway-resend", .kind = .action, .requires = &.{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .model_payload_schema_result }, .replaces = &.{.prepared_model_request}, .invalidates = &@import("../../domain/model_transport.zig").attempt_keys, .produces = &.{}, .side_effect = .none };
    /// ADR 0039: the one re-send of a first runaway is its identical prepared
    /// request at the runaway-retry temperature. It adds no diagnostic and no
    /// partial text; evidence of any other stop, or of a re-send, rejects.
    pub fn execute(_: Action, allocator: std.mem.Allocator, runaway: *const validation.Evidence) preparation.Error!preparation.Owned {
        if (runaway.runaway() != .first) return error.ModelRequestAssociationInvalid;
        return preparation.resend(allocator, runaway.request());
    }
};
