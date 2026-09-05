High-level execution flow for the Implement workflow.

```mermaid
flowchart TD
    START["Run Implement"] --> GATE{"Current specification, plan, tasks and approvals valid;<br/>all required clarifications resolved?"}
    GATE -->|No| BLOCKED["End blocked;<br/>resolve the owning workflow's outstanding decisions"]
    GATE -->|Yes| TASK["Select the next eligible task"]
    TASK --> CHANGE["Generate candidate changes<br/>for the task's approved files and operations"]
    CHANGE --> COMMANDS["Run the task's named validation commands<br/>against the private candidate workspace"]
    COMMANDS --> CHECK{"Authorized changes and required evidence valid?"}
    CHECK -->|Repairable code defect| REPAIR["Repair only authorized changes<br/>within the declared retry limits"]
    REPAIR -->|Repaired candidate| COMMANDS
    REPAIR -->|Exhausted or disallowed| BLOCKED
    CHECK -->|Unresolved upstream decision| BLOCKED
    CHECK -->|Yes| MORE{"More tasks?"}
    MORE -->|Yes| TASK
    MORE -->|No| FINAL["Validate the complete project candidate<br/>and all required task evidence"]
    FINAL -->|Valid| OUTPUT["Publish project changes, evidence and workflow state together;<br/>mark tasks complete"]
    FINAL -->|Invalid| FAILED["End failed;<br/>discard candidate output"]
```

Candidate work stays private until the whole workflow succeeds. Failure,
blocking, cancellation or interruption ends the run without publishing partial
task completion. A later invocation starts the workflow again.
