const identity = @import("../../domain/model_request_identity.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "build-immutable-unit-owner-id@1",
        .kind = .action,
        .requires = &.{},
        .produces = &.{},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        descriptor: identity.ImmutableUnitOwnerId,
    ) identity.ValidationError!identity.ImmutableUnitOwnerId {
        try identity.validateUnitOwner(descriptor);
        return descriptor;
    }
};
