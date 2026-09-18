const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const identity = @import("../../domain/model_request_identity.zig");
const handoff = @import("../../domain/model_request_handoff.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "prepare-model-request",
        .kind = .action,
        .requires = &.{.model_request_identity_ledger},
        .optional = &.{.model_input_packet},
        .produces = &.{ .assigned_model_request, .validated_model_request, .prepared_model_request },
        .replaces = &.{.model_request_identity_ledger},
        .side_effect = .none,
    };

    pub fn execute(_: Action, allocator: std.mem.Allocator, current: *const identity.ModelRequestIdentityLedger, revision: identity.LedgerRevision, selected: handoff.Selection) (handoff.Error || identity.Error)!handoff.Prepared {
        return handoff.prepare(allocator, current, revision, selected);
    }
};
