const operation = @import("../../domain/llm_provider_operation.zig");
const pipeline = @import("../../domain/pipeline.zig");
const accounting = @import("../../domain/workflow_token_accounting.zig");

pub const Error = accounting.ProposalError;

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "reconcile-workflow-token-usage@1",
        .kind = .action,
        .requires = &.{},
        .produces = &.{},
        .side_effect = .none,
        .runner_accounting = .reconcile_workflow_tokens,
    };

    pub fn execute(
        _: Action,
        ledger: *const accounting.Ledger,
        expected_revision: accounting.Revision,
        inference_operation_id: operation.ProviderOperationId,
        reconciliation: accounting.Reconciliation,
    ) Error!pipeline.NodeDelta {
        const transition = try accounting.proposeReconciliation(
            ledger,
            expected_revision,
            inference_operation_id,
            reconciliation,
        );
        var delta: pipeline.NodeDelta = .{};
        delta.runner_accounting_transition = .{ .reconcile_workflow_tokens = transition };
        return delta;
    }
};
