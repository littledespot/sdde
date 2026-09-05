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
    CITABLE --> EXTRACT["YAML-declared model extraction - future<br/>Tests supply engine-scoped scripted results"]
    EXTRACT --> PARSE["parse-reference-extraction-results@1<br/>Closed claims or positive no-feature-claim body"]
    PARSE --> CITE["validate-reference-claims@1<br/>Reuse the shared source-citation validator; complete chunk joins"]
    CITE --> IDS["assign-reference-claim-identities@1<br/>Engine-owned state-local claim and citation IDs"]
    IDS --> LEDGER["build-reference-extraction-ledger@1<br/>In-memory unreviewed claims and chunk outcomes"]
    LEDGER --> ACCOUNT["validate-reference-extraction-accounting@1<br/>Exact chunk, claim and citation coverage"]
    ACCOUNT -- Complete --> VALIDATE["Future semantic validation and reconciliation;<br/>citation integrity is not proof of meaning"]
    ACCOUNT -- Blocked chunk --> BLOCKED["End blocked; no specification publication"]
    ACCOUNT -- Invalid coverage --> ABANDON
    VALIDATE -- Invalid candidate --> REPAIR[Only declared bounded repair or failure transition]
    REPAIR --> VALIDATE
    VALIDATE -- Required authority missing --> CLARIFY[Preserve one clarification per stable subject<br/>end execution without partial workflow output]
    VALIDATE -- Valid --> CANDIDATE[Retain complete reference candidate for subsequent YAML steps]
    CANDIDATE --> FINAL[Whole-workflow validation and successful output]
    INVENTORY -- Failure --> ABANDON[Abandon execution]
    CAPTURE -- Failure or interruption --> ABANDON
    DECODE -- Failure --> ABANDON
    IDENTIFY -- Failure --> ABANDON
    CITABLE -- Invalid --> ABANDON
    PARSE -- Failed --> ABANDON
    CITE -- Failed --> ABANDON
    REPAIR -- Unresolved or exhausted --> ABANDON
```

Implemented: Markdown capture/accounting, citable inputs and extraction-candidate
parsing, structural validation, ID assignment and total accounting. The base
test-only ingestion YAML stops at `CITABLE`; scripted-result tests extend it
through `ACCOUNT`. Model extraction, token/passive-literal handling, semantic
reconciliation, snapshots and publication remain unfinished. See
[F0100 §3.5](../features/F0100-SpecWorkflow.md#35-extraction-candidate-accounting).

No reference-stage transaction or durable extraction checkpoint is created.
An interrupted execution is abandoned; a later invocation starts at the
workflow's beginning and reuses relevant clarification answers. See
[ADR 0009](../decisions/0009-atomic-workflow-execution.md). The supplied-directory
contract is [ADR 0010](../decisions/0010-explicit-feature-directory.md).
