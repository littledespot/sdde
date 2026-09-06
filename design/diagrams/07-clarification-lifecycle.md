High-level lifecycle of a workflow clarification and the user's answer.

```mermaid
flowchart TD
    START["Start a workflow"] --> LOAD["Load existing questions and protected answers;<br/>validate answers against current inputs"]
    LOAD --> GATE{"Required knowledge and predecessor gates satisfied?"}
    GATE -->|Yes| RUN["Continue the workflow"]
    GATE -->|Missing or conflicting knowledge| OWNER["Identify the workflow that owns the decision;<br/>invalidate affected downstream authority when needed"]
    RUN -->|New knowledge gap| OWNER
    OWNER --> SUBJECT["Find the existing question for the same subject<br/>or identify a new question"]
    SUBJECT --> PROTECTED{"Does a protected answer need reconsideration?"}
    PROTECTED -->|Yes| BLOCKED["End blocked;<br/>request explicit user direction"]
    PROTECTED -->|No| SAVE["Create new forms; completely overwrite unresolved forms at the same IDs/paths;<br/>preserve user-resolved forms"]
    SAVE -->|Writes succeed| WAIT["End needs_user;<br/>publish no partial workflow output"]
    SAVE -->|Write failure| FAIL["End failed; replaced writable files may remain;<br/>protected forms unchanged; fresh rerun required"]
    WAIT --> USER["User answers the question"]
    USER --> RERUN["Rerun the owning workflow from the beginning"]
    RERUN --> LOAD
```

The same subject retains the same clarification identity across runs. Every
workflow completely overwrites unresolved forms from current validated state,
including open answer drafts, while user-resolved forms remain byte-for-byte
unchanged. Applicable validated answers become inputs to a new
execution, which regenerates and validates the owning workflow's complete output.
