# TASKS01 — Tasks workflow intent

The Tasks workflow's intent ([convention](README.md)).
[ADR 0034](../design/decisions/0034-spec-quality-gate.md) "What waits" governs when Tasks work
starts; [SPEC01](SPEC01.md) §1 records the gate's status.

## Intent

> An actionable work breakdown with dependencies, verification expectations and links to
> governing requirements and design.

[intent.md](../design/intent.md):36. The statement orients judgment and isn't contract
authority (intent.md:3-9).

## Owners

- **Stage design:** design.md §19 and [19-tasks.md](../design/contracts/19-tasks.md), as amended
  by the accepted ADRs (design.md §32); **Proposed design**.
- **Model and engine split:** design.md §4 (design.md:259, 262, 266-267) and
  [21-validation.md](../design/contracts/21-validation.md) §21.4's semantic remainders and
  §21.6 (21-validation.md:122).
- **Delivery:** design.md §30 Increment 4 (design.md:737-742).
- **Shared code:** the task-cluster owner and the cluster, definition-state and task ID types
  (`src/domain/model_request_identity.zig:17-19, 65-68`) and the clarification stage
  (`src/domain/clarification_inputs.zig:16`).
