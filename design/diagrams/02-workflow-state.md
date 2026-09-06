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

Each workflow starts from its beginning and publishes its complete output only
on success. Failure, blocking or cancellation ends that execution. Relevant
clarification answers are retained for the next run. Every workflow completely
overwrites its registered replaceable outputs and unresolved forms at the same
paths on rerun, preserving user-resolved forms byte-for-byte. Other workflow
definitions follow their own declared gates and transitions under that shared
replacement rule.

All outputs validate before publication. A publication write failure or
interruption may leave already-replaced files, but cannot record new successful
completion. Rerunning replaces the complete output set; there is no rollback or
recovery store. User-closed clarification files remain protected throughout.
