Implementation tasks remain candidate work inside one atomic workflow execution.
[ADR 0009](../decisions/0009-atomic-workflow-execution.md) prohibits independent
task commits and checkpoint recovery.

```mermaid
flowchart TD
    START[New implementation workflow at start] --> GATE[Validate current spec plan tasks and approvals<br/>outstanding clarifications prohibit execution]
    GATE -- Rejected --> END[End execution without candidate output]
    GATE -- Valid --> TASK[Execute next YAML-selected task operation<br/>within the private workflow candidate]
    TASK --> CHECK[Validate authorized changes and required evidence]
    CHECK -- Explicit YAML repair within local retry limit --> TASK
    CHECK -- Valid --> MORE{More candidate work}
    MORE -- Yes --> TASK
    MORE -- No --> FINAL[Validate the complete workflow candidate]
    FINAL -- Valid --> OUTPUT[Publish complete workflow output and evidence]
    CHECK -- Unhandled failure --> END
    FINAL -- Invalid --> END
    TASK -- Cancellation or interruption --> END
    END -. A later invocation starts again .-> START
```

No successful sibling task is independently published. A new execution reruns
the workflow rather than resuming an operation, command or task checkpoint.
