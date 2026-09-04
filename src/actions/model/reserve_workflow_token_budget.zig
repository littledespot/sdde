const operation = @import("../../domain/llm_provider_operation.zig");
const pipeline = @import("../../domain/pipeline.zig");
const accounting = @import("../../domain/workflow_token_accounting.zig");

pub const Error = accounting.ProposalError;

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "reserve-workflow-token-budget@1",
        .kind = .action,
        .requires = &.{},
        .produces = &.{},
        .side_effect = .none,
        .runner_accounting = .reserve_workflow_tokens,
    };

    pub fn execute(
        _: Action,
        ledger: *const accounting.Ledger,
        expected_revision: accounting.Revision,
        inference_operation_id: operation.ProviderOperationId,
        count_evidence: operation.ExactInputTokenCountEvidence,
        effective_maximum_output_tokens: u64,
    ) Error!pipeline.NodeDelta {
        const transition = try accounting.proposeReservation(
            ledger,
            expected_revision,
            inference_operation_id,
            count_evidence,
            effective_maximum_output_tokens,
        );
        var delta = pipeline.NodeDelta.successful(contract);
        delta.runner_accounting_transition = .{ .reserve_workflow_tokens = transition };
        return delta;
    }
};
