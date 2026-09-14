High-level lifecycle of one workflow execution.

```mermaid
flowchart TD
    START["Start a new workflow invocation"] --> INPUTS["Validate current inputs, gates and approvals;<br/>reuse applicable clarification answers"]
    INPUTS --> RUN["Execute the declared workflow;<br/>keep candidate output private"]
    RUN --> RESULT{"Workflow outcome"}
    RESULT -->|Success| VALIDATE["Validate the complete output and evidence"]
    VALIDATE -->|Valid| OUTPUT["Publish validated registered artifacts;<br/>write canonical workflow state last"]
    OUTPUT -->|All writes succeed| COMPLETE["Report successful completion"]
    OUTPUT -->|Write failure or interruption| WRITEFAIL["No new successful completion;<br/>already-replaced files may remain"]
    WRITEFAIL -. Fresh invocation .-> START
    VALIDATE -->|Invalid| FAILED["End failed;<br/>discard candidate output"]
    RESULT -->|Needs user| CLARIFY["Preserve clarification questions and answers;<br/>publish no partial successful output"]
    RESULT -->|Failed| FAILED
    RESULT -->|Blocked| BLOCKED["End blocked;<br/>discard candidate output"]
    RESULT -->|Cancelled or interrupted| ABANDON["End the execution;<br/>discard candidate output"]
    CLARIFY -. After user input: new invocation .-> START
    FAILED -. Later invocation .-> START
    BLOCKED -. After resolving the blocker: new invocation .-> START
    ABANDON -. Later invocation .-> START
```

[ADR 0009](../decisions/0009-atomic-workflow-execution.md) defines fresh execution
from `start` and whole-workflow publication. Failed writes may leave replaced
files but cannot record new success. Clarification identity/answer persistence
and user-closed byte protection follow
[§23.2](../design.md#232-workflow-reruns-and-protected-clarification-files).
