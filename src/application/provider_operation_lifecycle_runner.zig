const std = @import("std");
const advance_action = @import("../actions/model/advance_provider_operation_lifecycle.zig");
const lifecycle = @import("../domain/provider_operation_lifecycle.zig");
const identity = @import("../domain/model_request_identity.zig");
const provider = @import("../domain/llm_provider_operation.zig");
const pipeline = @import("../domain/pipeline.zig");

pub const Runner = struct {
    owner: *lifecycle.Owner,
    ledger: *const lifecycle.Ledger,
    action: advance_action.Action = .{},

    pub fn init(allocator: std.mem.Allocator, epoch: identity.StageRunEpochId) lifecycle.Error!Runner {
        const owner = try lifecycle.createInitial(allocator, epoch);
        return .{ .owner = owner, .ledger = lifecycle.initial(owner) };
    }

    pub fn deinit(self: *Runner) void {
        lifecycle.deinitOwner(self.owner);
        self.* = undefined;
    }

    pub fn advance(
        self: *Runner,
        authority: lifecycle.Authority,
        expected_revision: lifecycle.Revision,
        operation_id: provider.ProviderOperationId,
        expected_operation_revision: ?lifecycle.Revision,
        command: lifecycle.Command,
    ) lifecycle.Error!lifecycle.Effect {
        const envelope = pipeline.PipelineEnvelope.init(&.{.model_request_identity_ledger});
        envelope.validateInvocation(advance_action.Action.contract) catch return error.InvalidProviderOperationTransition;
        const delta = try self.action.execute(self.ledger, authority, expected_revision, operation_id, expected_operation_revision, command);
        _ = envelope.apply(advance_action.Action.contract, delta) catch return error.InvalidProviderOperationTransition;
        const transition = switch (delta.runner_accounting_transition.?) {
            .advance_provider_operation => |value| value,
            else => unreachable,
        };
        self.ledger = try lifecycle.apply(self.ledger, authority, transition);
        return lifecycle.projectEffect(self.ledger.record(operation_id).?.*, expected_operation_revision);
    }

    pub fn current(self: *const Runner) *const lifecycle.Ledger {
        return self.ledger;
    }
};
