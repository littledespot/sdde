const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const operation = @import("../../domain/llm_provider_operation.zig");
const preparation = @import("../../ports/provider_operation_authorization.zig");

pub const Outcome = union(enum) {
    prepared: pipeline.NodeDelta,
    failed: operation.ProviderFailure,
    cancelled,
};

pub const Action = struct {
    authorization: preparation.Port,

    pub const contract: pipeline.NodeContract = .{
        .id = "prepare-provider-operation-authorization@1",
        .kind = .action,
        .requires = &.{.validated_provider_model_binding},
        .produces = &.{.validated_provider_authorization},
        .side_effect = .none,
    };

    pub fn execute(self: Action, facts: preparation.Facts, slot: preparation.AllocatedSlot, runtime: pipeline.NodeRuntime) std.mem.Allocator.Error!Outcome {
        switch (runtime.status()) {
            .cancelled => return .cancelled,
            .deadline_exhausted => return failure(facts.operation_id, .timeout),
            .active => {},
        }
        const observation = self.authorization.prepare(facts, slot.deposit) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Cancelled => return .cancelled,
            error.AuthorizationExpired => return failure(facts.operation_id, .timeout),
            error.AuthorizationDenied, error.ClockUnavailable => return failure(facts.operation_id, .authorization_denied),
        };
        return switch (observation) {
            .prepared => prepared(slot) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Cancelled => .cancelled,
                error.AuthorizationExpired => failure(facts.operation_id, .timeout),
                error.AuthorizationDenied, error.ClockUnavailable => failure(facts.operation_id, .authorization_denied),
            },
            .failed => |cause| failure(facts.operation_id, switch (cause) {
                .authentication_failed => .authentication_failed,
                .authorization_denied => .authorization_denied,
            }),
        };
    }
};

fn prepared(slot: preparation.AllocatedSlot) preparation.Error!Outcome {
    var delta: pipeline.NodeDelta = .{};
    delta.data_writes[@intFromEnum(pipeline.DataKey.validated_provider_authorization)] = try slot.publish();
    return .{ .prepared = delta };
}

fn failure(id: operation.ProviderOperationId, cause: operation.ProviderFailureCause) Outcome {
    return .{ .failed = .{ .operation_id = id, .cause = cause, .retry_class = .never, .delivery = .not_sent } };
}
