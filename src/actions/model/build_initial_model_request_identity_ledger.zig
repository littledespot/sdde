const std = @import("std");
const identity = @import("../../domain/model_request_identity.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "build-initial-model-request-identity-ledger@1",
        .kind = .action,
        .requires = &.{},
        .produces = &.{.model_request_identity_ledger},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        stage_run_epoch_id: identity.StageRunEpochId,
        purpose_registry: identity.RequestPurposeRegistry,
    ) identity.Error!*identity.Owner {
        return identity.createInitial(allocator, stage_run_epoch_id, purpose_registry);
    }
};
