# 13.8 Whole-workflow output boundary

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.


Section 25 replaces the former transaction-action catalogue. Validation,
path authorization, rendering and candidate construction remain separate
responsibilities. They prepare one complete workflow output without
publishing a step or task independently. Successful whole-workflow completion
publishes it; non-success abandons it, preserving clarifications under their
explicit contract.

There are no transaction-ID, WAL, prepare/apply/marker, checkpoint,
durable-result-handoff or recovery actions to implement.
