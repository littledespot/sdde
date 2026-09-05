Reference ingestion within one atomic workflow execution. These are required
responsibilities, not a hidden engine route; the selected YAML declares the
operations and transitions.

```mermaid
flowchart TD
    START[Workflow start with --feature directory<br/>and independent reference selector] --> TARGET[Resolve feature directory beneath paths.specs from .sddtoolkit.json;<br/>validate target and required state;<br/>no repeated root generated name or ownership registry]
    TARGET -- Valid --> INVENTORY[Validate complete bounded reference inventory<br/>containment supported kinds and deterministic order]
    TARGET -- Invalid or unsafe --> ABANDON
    INVENTORY --> CAPTURE[Capture immutable source bytes through authorized readers]
    CAPTURE --> EXTRACT[Run YAML-declared extraction operations<br/>retain exact source spans and provenance]
    EXTRACT --> VALIDATE[Validate complete coverage identities citations and candidate facts]
    VALIDATE -- Invalid candidate --> REPAIR[Only declared bounded repair or failure transition]
    REPAIR --> VALIDATE
    VALIDATE -- Required authority missing --> CLARIFY[Preserve one clarification per stable subject<br/>end execution without partial workflow output]
    VALIDATE -- Valid --> CANDIDATE[Retain complete reference candidate for subsequent YAML steps]
    CANDIDATE --> FINAL[Whole-workflow validation and successful output]
    INVENTORY -- Failure --> ABANDON[Abandon execution]
    CAPTURE -- Failure or interruption --> ABANDON
    REPAIR -- Unresolved or exhausted --> ABANDON
```

No reference-stage transaction or durable extraction checkpoint is created.
An interrupted execution is abandoned; a later invocation starts at the
workflow's beginning and reuses relevant clarification answers. See
[ADR 0009](../decisions/0009-atomic-workflow-execution.md). The supplied-directory
contract is [ADR 0010](../decisions/0010-explicit-feature-directory.md).
