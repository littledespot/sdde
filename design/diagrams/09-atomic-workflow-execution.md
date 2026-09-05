High-level lifecycle of one workflow execution.

```mermaid
flowchart TD
    START["Start a new workflow invocation"] --> INPUTS["Validate current inputs, gates and approvals;<br/>reuse applicable clarification answers"]
    INPUTS --> RUN["Execute the declared workflow;<br/>keep candidate output private"]
    RUN --> RESULT{"Workflow outcome"}
    RESULT -->|Success| VALIDATE["Validate the complete output and evidence"]
    VALIDATE -->|Valid| OUTPUT["Publish complete artifacts and state together;<br/>replace the workflow's existing outputs"]
    OUTPUT --> COMPLETE["Report successful completion"]
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

Each invocation begins at the workflow's start. Step or task progress is not a
saved continuation. User-closed clarification files remain unchanged, and
clarification answers survive output replacement and abandoned executions.
