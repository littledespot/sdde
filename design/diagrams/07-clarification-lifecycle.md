Clarifications are the explicit persistence exception to
[atomic workflow execution](../decisions/0009-atomic-workflow-execution.md).
They preserve answers, not execution continuations.

```mermaid
flowchart TD
    START[New workflow invocation at start] --> LOAD[Load and validate clarification registry and protected forms]
    LOAD --> ANSWERS[Apply relevant validated answers to current inputs]
    ANSWERS --> GATE{Declared predecessor and clarification gates}
    GATE -- Satisfied --> RUN[Execute compiled YAML]
    GATE -- Outstanding spec plan or tasks clarification for implement --> BLOCK[Do not execute implementation work]
    RUN -- Required authority gap --> SUBJECT[Derive stable owner target subject and slot]
    SUBJECT --> FIND{Existing clarification identity}
    FIND -- Yes --> REUSE[Reuse identity; never duplicate or reopen a user-closed form]
    FIND -- No --> CREATE[Create one validated clarification and registered form]
    REUSE --> PRESERVE[Preserve registry answers and protected user-closed files]
    CREATE --> PRESERVE
    PRESERVE --> END[End needs_user execution<br/>publish no partial workflow output]
    END -. User supplies answers; new invocation .-> START
```

Changed wording, execution identity or authority revision does not create a
second clarification for the same subject. Invalid/stale protected answers
block rather than being overwritten. No clarification transaction, checkpoint
or saved-step resume is required.
