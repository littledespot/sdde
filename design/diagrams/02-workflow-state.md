High-level progression through the Specify, Plan, Tasks and Implement workflows.

```mermaid
flowchart TD
    SPEC["Run Specify"] --> SPECOUT["Publish a validated specification"]
    SPECOUT --> PLAN["Run Plan<br/>Revalidate the current specification and clarification answers"]
    PLAN --> PLANOUT["Publish a validated plan"]
    PLANOUT --> PLANAPPROVAL["User approves the exact current plan"]
    PLANAPPROVAL --> TASKS["Run Tasks<br/>Revalidate the approved plan and clarification gates"]
    TASKS --> TASKOUT["Publish a validated task graph"]
    TASKOUT --> TASKAPPROVAL["User approves the exact current task graph"]
    TASKAPPROVAL --> IMPLEMENT["Run Implement<br/>Revalidate both approvals and all predecessor gates"]
    IMPLEMENT --> COMPLETE["Publish completed project changes<br/>with passing validation and task evidence"]

    GAP["Required knowledge is missing during a workflow"] --> CLARIFY["Reuse subject IDs; completely overwrite unresolved forms;<br/>preserve user-resolved forms and end needs_user"]
    CLARIFY --> ANSWERS["User answers the questions"]
    ANSWERS --> RERUN["Start a new execution of the owning workflow"]

    CHANGE["Upstream inputs change"] --> INVALIDATE["Invalidate affected downstream authority and approvals"]
    INVALIDATE --> RERUN
```

These predecessor gates apply to the initial SDD suite; unrelated workflows
follow their own compiled transitions. See [Design §24](../design.md#24-state-sequence-and-recovery-without-fingerprints).

Every invocation starts at `start`. [ADR 0009](../decisions/0009-atomic-workflow-execution.md)
owns whole-workflow publication and failure behavior;
[§23.2](../design.md#232-workflow-reruns-and-protected-clarification-files)
owns unresolved-form replacement and byte-preserved user-closed forms.
