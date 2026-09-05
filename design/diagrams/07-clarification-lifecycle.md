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
    PROTECTED -->|No| SAVE["Create or refresh the controlled clarification form;<br/>preserve protected answers"]
    SAVE --> WAIT["End needs_user;<br/>publish no partial workflow output"]
    WAIT --> USER["User answers the question"]
    USER --> RERUN["Rerun the owning workflow from the beginning"]
    RERUN --> LOAD
```

The same subject retains the same clarification identity across runs. User-closed
forms remain unchanged. Applicable validated answers become inputs to a new
execution, which regenerates and validates the owning workflow's complete output.
