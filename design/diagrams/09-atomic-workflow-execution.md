One atomic workflow execution under
[ADR 0009](../decisions/0009-atomic-workflow-execution.md).

```mermaid
flowchart TD
    START[New invocation at compiled start<br/>fresh execution-local state and token usage] --> INPUT[Validate current inputs and declared gates<br/>reuse applicable clarification answers]
    INPUT --> RUN[Follow compiled YAML transitions<br/>keep candidate output private]
    RUN --> RESULT{Whole-workflow terminal outcome}
    RESULT -- Success --> OUTPUT[Publish complete validated workflow output<br/>replace existing registered outputs]
    RESULT -- Needs user --> CLARIFY[Preserve deduplicated clarifications<br/>end execution without partial workflow output]
    RESULT -- Failed blocked cancelled or interrupted --> ABANDON[Abandon execution and candidate output]
    CLARIFY -. Later invocation .-> START
    ABANDON -. Later invocation .-> START
```

No step/task transactions, provider journals, durable checkpoints, saved-step
continuations or recovery subsystem. User-closed clarification files remain
unchanged.
