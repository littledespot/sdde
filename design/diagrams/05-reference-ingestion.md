Reference ingestion within one atomic workflow execution. These are required
responsibilities, not a hidden engine route; the selected YAML declares the
operations and transitions.

```mermaid
flowchart TD
    START[Workflow start with --feature directory<br/>and independent reference selector] --> TARGET[Resolve feature directory beneath paths.specs from .sddtoolkit.json;<br/>validate target and required state;<br/>no repeated root generated name or ownership registry]
    TARGET -- Valid --> INVENTORY[Validate complete bounded reference inventory<br/>containment supported kinds and deterministic order]
    TARGET -- Invalid or unsafe --> ABANDON
    INVENTORY --> CAPTURE[Capture immutable source bytes through authorized readers]
    CAPTURE --> DECODE[Decode Markdown to lossless source blocks;<br/>validate complete source and block accounting]
    DECODE --> IDENTIFY["assign-reference-identities@1<br/>Fresh reference state; total source/block identity mappings"]
    IDENTIFY --> CHUNKS["build-reference-chunks@1<br/>One identified chunk per source block; no source reread"]
    CHUNKS --> CITABLE["validate-reference-chunks@1<br/>Prove exact source mappings and complete chunk coverage"]
    CITABLE --> EXTRACT[Run YAML-declared extraction operations<br/>not implemented in the read-only increment]
    EXTRACT --> CITE["validate-source-citations@1<br/>Check exact call scope, source spans and optional quotations"]
    CITE --> VALIDATE[Validate complete extraction coverage and candidate facts;<br/>semantic support is not deterministic citation proof]
    VALIDATE -- Invalid candidate --> REPAIR[Only declared bounded repair or failure transition]
    REPAIR --> CITE
    VALIDATE -- Required authority missing --> CLARIFY[Preserve one clarification per stable subject<br/>end execution without partial workflow output]
    VALIDATE -- Valid --> CANDIDATE[Retain complete reference candidate for subsequent YAML steps]
    CANDIDATE --> FINAL[Whole-workflow validation and successful output]
    INVENTORY -- Failure --> ABANDON[Abandon execution]
    CAPTURE -- Failure or interruption --> ABANDON
    DECODE -- Failure --> ABANDON
    IDENTIFY -- Failure --> ABANDON
    CITABLE -- Invalid --> ABANDON
    CITE -- Failed --> ABANDON
    REPAIR -- Unresolved or exhausted --> ABANDON
```

Implemented: Markdown capture/accounting, reference identities, chunk preparation
and citation validation. The test-only ingestion YAML stops at `CITABLE`;
citation tests supply typed proposals. Extraction, reconciliation, persistent
snapshots and downstream output publication remain unfinished.

No reference-stage transaction or durable extraction checkpoint is created.
An interrupted execution is abandoned; a later invocation starts at the
workflow's beginning and reuses relevant clarification answers. See
[ADR 0009](../decisions/0009-atomic-workflow-execution.md). The supplied-directory
contract is [ADR 0010](../decisions/0010-explicit-feature-directory.md).
