Initial SDD suite: each workflow invocation is atomic and starts at its own
compiled `start`. These domain gates do not form a fixed engine registry.
Specify resolves `--feature` relative to `.sddtoolkit.json`'s `paths.specs`
and validates the independent `--reference` selector.

```mermaid
flowchart TD
    SPEC[New Specify execution] --> SOUT[Complete validated specification output]
    SOUT --> PLAN[New Plan execution<br/>revalidate current specification and clarification gates]
    PLAN --> POUT[Complete validated plan output]
    POUT --> PA[Explicit approval bound to current plan state]
    PA --> TASKS[New Tasks execution<br/>revalidate plan and clarification gates]
    TASKS --> TOUT[Complete validated tasks output]
    TOUT --> TA[Explicit approval bound to current task definition]
    TA --> IMPL[New Implement execution<br/>current approvals and no outstanding spec plan or tasks clarifications]
    IMPL --> IOUT[Complete validated implementation output<br/>all task evidence and final checks pass]
    GAP[Required authority missing in any execution] --> CLARIFY[Preserve deduplicated clarification and end needs_user]
    CLARIFY --> NEW[After answers: new owning workflow execution at start]
    FAILURE[Failure blocking cancellation or interruption] --> END[Abandon the whole execution<br/>no partial successful output]
    END --> RERUN[Later invocation starts the whole workflow again]
```

No task transaction, intermediate publication or checkpoint continuation exists.
Upstream changes invalidate affected downstream authority; the next invocation
revalidates current inputs and approvals. Relevant clarification answers survive,
and user-closed forms remain unchanged. See
[ADR 0009](../decisions/0009-atomic-workflow-execution.md).
