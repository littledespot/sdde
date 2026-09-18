High-level lifecycle of a workflow clarification and the user's answer.

```mermaid
flowchart TD
    START["Start a workflow"] --> LOAD["Load existing questions and protected answers;<br/>validate answers against current inputs"]
    LOAD --> GATE{"Required knowledge and predecessor gates satisfied?"}
    GATE -->|Yes| RUN["Continue the workflow"]
    GATE -->|Missing or conflicting knowledge| OWNER["Identify the workflow that owns the decision;<br/>invalidate affected downstream authority when needed"]
    RUN -->|New knowledge gap| OWNER
    OWNER --> PREPARE["Prepare the affected requirement, current evidence<br/>and exact permitted user decision"]
    PREPARE --> SUBJECT["Find the existing question for the same subject<br/>or identify a new question"]
    SUBJECT --> PROTECTED{"Does a protected answer need reconsideration?"}
    PROTECTED -->|Yes| BLOCKED["End blocked;<br/>request explicit user direction"]
    PROTECTED -->|No| SAVE["Create new forms; completely overwrite unresolved forms at the same IDs/paths;<br/>preserve user-resolved forms"]
    SAVE -->|Writes succeed| WAIT["End needs_user;<br/>publish no partial workflow output"]
    SAVE -->|Write failure| FAIL["End failed; replaced writable files may remain;<br/>protected forms unchanged; fresh rerun required"]
    WAIT --> USER["User answers the question"]
    USER --> RERUN["Rerun the owning workflow from the beginning"]
    RERUN --> LOAD
```

[Design §23.2](../design.md#232-workflow-reruns-and-protected-clarification-files)
owns stable subject IDs, complete replacement of unresolved forms/drafts and
byte-preserved user-closed forms. Applicable validated answers feed a fresh
execution of the owning workflow.

Question preparation follows [§12.7](../contracts/12-model-boundary.md#127-workflow-defined-model-operations)
through existing builders; it adds no summary model or multi-subject answer authority.
Open Spec clarifications stop Plan at entry; open Spec or Plan clarifications stop
Tasks at entry. Authentication/application and the new preparation work remain
pending as recorded in [H-011](../harness/02-spec-workflow.md#h-011--complete-specification-clarification-handling).
