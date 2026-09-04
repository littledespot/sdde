const lifecycle = @import("../../domain/provider_operation_lifecycle.zig");
const provider = @import("../../domain/llm_provider_operation.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "advance-provider-operation-lifecycle@1",
        .kind = .action,
        .requires = &.{.model_request_identity_ledger},
        .produces = &.{},
        .side_effect = .none,
        .runner_accounting = .advance_provider_operation,
    };

    pub fn execute(
        _: Action,
        current: *const lifecycle.Ledger,
        authority: lifecycle.Authority,
        expected_revision: lifecycle.Revision,
        operation_id: provider.ProviderOperationId,
        expected_operation_revision: ?lifecycle.Revision,
        command: lifecycle.Command,
    ) lifecycle.ValidationError!pipeline.NodeDelta {
        const transition = try lifecycle.propose(current, authority, expected_revision, operation_id, expected_operation_revision, command);
        var delta: pipeline.NodeDelta = .{};
        delta.runner_accounting_transition = .{ .advance_provider_operation = transition };
        return delta;
    }
};
