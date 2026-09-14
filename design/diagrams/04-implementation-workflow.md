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
    FINAL -->|Valid| OUTPUT["Publish the complete validated output;<br/>write workflow state last and mark completion only on success"]
    OUTPUT -->|Write failure or interruption| WRITEFAIL["End without new successful completion;<br/>replaced files may remain"]
    FINAL -->|Invalid| FAILED["End failed;<br/>discard candidate output"]
```

Candidate work stays private until whole-workflow success; a failed or abandoned
run publishes no partial task completion. See
[Design §20](../design.md#20-implement-stage-design) and
[ADR 0009](../decisions/0009-atomic-workflow-execution.md).
