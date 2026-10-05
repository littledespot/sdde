# Spec model call tree

These diagrams describe the current [Spec workflow YAML](../workflows/spec.workflow.yaml),
whose workflow ID is `spec-generation`. They document its configured calls, not
new design authority or evidence of a successful live run. The governing design
remains **Proposed design**; see [§17](../contracts/17-specify.md) and
[§12](../contracts/12-model-boundary.md).

In the first two diagrams, arrows mean **contains or calls**, not execution
order or parallel execution. Dashed arrows mark conditional branches. Blue nodes
are model requests using `spec_generation`; orange nodes use `repair`.
Deterministic preparation, validation, assembly and publication are collapsed.
Every model node uses the shared request path in the third diagram.

## Reference processing

The workflow extracts all reference chunks, rebuilds and validates extraction,
then reconciles summary partitions and the global result. Composition assembly
is deterministic and adds no model call.

```mermaid
flowchart LR
    ROOT["spec-generation<br/>Reference processing"]
    ROOT --> EX["extract-references<br/>Repeat for each reference chunk"]
    EX --> CONTENT["content-request<br/>extraction-content-prompt<br/>1 call per chunk"]
    EX --> CLASSIFICATIONS["classifications<br/>extraction-classifications-prompt<br/>1 call per chunk, after content"]
    EX -. "Invalid extracted text" .-> TEXT_REPAIR["model-request-with-context<br/>repair-prompt<br/>Authorized text repair"]

    ROOT --> VALIDATE_EX["validate-extraction"]
    VALIDATE_EX -. "Invalid selections or claims" .-> EX_REPAIR["model-request-with-context<br/>repair-prompt<br/>Authorized extraction repair"]

    ROOT --> RC["reconcile-references"]
    RC --> SUMMARY["summary<br/>reconciliation-prompt<br/>1 call per summary partition"]
    RC --> GLOBAL["Global composition<br/>4 sequential calls"]
    GLOBAL --> DISPOSITIONS["dispositions<br/>dispositions-prompt"]
    GLOBAL --> SIGNALS["signals<br/>signals-prompt"]
    GLOBAL --> ROLES["roles<br/>roles-prompt"]
    GLOBAL --> CONFLICTS["conflicts<br/>conflicts-prompt"]
    RC -. "Invalid summary" .-> RC_REPAIR["repair-reconciliation-candidate<br/>repair-prompt<br/>Authorized reconciliation repair"]

    ROOT --> VALIDATE_RC["validate-reconciliation"]
    VALIDATE_RC -. "Invalid global candidate" .-> RC_REPAIR

    ROOT -. "Source readiness requires review,<br/>or preservation check enabled" .-> SOURCE["review-source"]
    SOURCE --> SUPPORT["review-support<br/>See generation and review tree"]
    ROOT -. "Source-authority gate selects repair" .-> UPSTREAM["Source omission repair"]
    UPSTREAM --> SOURCE_EX["repair-source-extraction<br/>model-request-with-context<br/>repair-prompt"]
    UPSTREAM --> SOURCE_RC["repair-source-candidate<br/>repair-prompt<br/>Reconciliation schema"]

    classDef model fill:#dbeafe,stroke:#2563eb,color:#111827;
    classDef repair fill:#ffedd5,stroke:#ea580c,color:#111827;
    class CONTENT,CLASSIFICATIONS,SUMMARY,DISPOSITIONS,SIGNALS,ROLES,CONFLICTS model;
    class TEXT_REPAIR,EX_REPAIR,RC_REPAIR,SOURCE_EX,SOURCE_RC repair;
```

Global calls execute in this order: **dispositions → signals → roles → conflicts**.
Summary partitions are consumed before the global composition. The YAML sets
reconciliation `group-size: 8`; the resulting partition count depends on the
extracted claims and hierarchy.

The [Hello World configuration](../../test/e2e/wf-001-hello-world/.sddtoolkit.json)
sets `validation.sourcePreservationCheck: false`. This skips optional source
preservation review when source readiness passes. A source-readiness block still
routes through source review and the authority gate.

## Specification generation and review

Generation runs **brief → primary user story → entities → record groups**.
After assembly and deterministic coverage validation, source review runs before
applicable principle review. Each review request assesses one native subject;
it is not one request for the entire specification.

```mermaid
flowchart LR
    ROOT["spec-generation<br/>Generation and review"]
    ROOT --> GENERATE["generate-specification"]
    GENERATE --> BRIEF["generate-unit: brief<br/>generation-prompt<br/>1 call"]
    GENERATE --> STORY["generate-unit: primary_user_story<br/>story-prompt<br/>1 call"]
    GENERATE --> ENTITIES["generate-unit: entities<br/>entities-prompt<br/>1 call"]
    GENERATE --> RECORDS["generate-unit: records<br/>records-prompt<br/>1 call per active record group"]
    GENERATE -. "Unit validation authorizes repair" .-> UNIT_REPAIR["generate-unit: repair<br/>Same prompt as the affected unit<br/>Authorized replacement"]

    ROOT --> REVIEW["review-specification"]
    REVIEW --> CANDIDATE["review-candidate"]
    CANDIDATE --> SOURCE["source: review-support<br/>support-prompt"]
    CANDIDATE -. "Selected principle spans apply" .-> POLICY["policy: review-support<br/>principle-prompt"]
    ROOT -. "Pre-generation source review" .-> PRE["review-source<br/>support-prompt"]

    SOURCE --> SUPPORT["review-support<br/>Repeat for each pending subject"]
    POLICY --> SUPPORT
    PRE --> SUPPORT
    SUPPORT --> FINDING["model-request<br/>Assigned support or principle prompt<br/>1 call per subject"]
    SUPPORT -. "Source finding needs omission localization" .-> LOSS["loss-model<br/>loss-prompt<br/>Additional localization call"]
    SUPPORT -. "Review validation authorizes repair" .-> SUPPORT_REPAIR["repair<br/>Assigned support or principle prompt<br/>Authorized finding repair"]

    REVIEW -. "Source-backed candidate omission" .-> OMISSION["repair-omission<br/>repair-prompt<br/>Generation schema; then reassemble and review"]
    ROOT -. "Review returns upstream rework" .-> UPSTREAM["repair-upstream"]
    UPSTREAM --> EX["repair-source-extraction<br/>model-request-with-context<br/>repair-prompt"]
    UPSTREAM --> RC["repair-source-candidate<br/>repair-prompt<br/>Reconciliation schema"]

    classDef model fill:#dbeafe,stroke:#2563eb,color:#111827;
    classDef repair fill:#ffedd5,stroke:#ea580c,color:#111827;
    class BRIEF,STORY,ENTITIES,RECORDS,FINDING,LOSS model;
    class UNIT_REPAIR,SUPPORT_REPAIR,OMISSION,EX,RC repair;
```

Record-group assignments come from active reconciled signals with the `records`
role; one group may produce several specification records. Review subjects come
from the shared required-authority ledger. Empty principle selection requires no
principle model call. Repairs and upstream rebuilding can cause renewed review
or reconciliation calls; they do not independently commit a unit.

The `model-request-with-context` subgraph retains the workflow-selected context
for extraction repairs and specification authoring. Generation, native unit repair
and reviewed omission repair use one shared `generation-context` resource. It explains
ordered text fragments and literal insertion; the selected schema still defines
the response shape. Story purpose comes from the shared native requirement descriptions.
Brief and story packets contain source evidence without sibling drafts; entities
receive the brief, and record requests receive the brief and entity decision.
Corrections retain their selected context, purpose prompt and dynamic input.

Coverage repair, authority gates, clarification forms, rendering and publication
are deterministic in this YAML and do not add model requests.

## Shared model-request execution

This diagram uses arrows for **execution order**. `model-request`,
`model-request-with-context` and `composition-request` prepare
a request before entering `model-request-body`. The extraction content step prepares its request
directly and enters through `composition-request-body`.

```mermaid
flowchart TD
    REQUEST["Prepared model request<br/>Bound slot, prompt, schema and input"]
    REQUEST --> BODY["model-request-body"]
    BODY --> ACCOUNT["Account model attempt<br/>Enforce supplied retry limit and execution budget"]
    ACCOUNT --> AUTHORIZE["Assign and authorize inference operation<br/>Advance request and operation lifecycles"]
    AUTHORIZE --> INVOKE["invoke-model<br/>1 provider inference call per attempt"]
    INVOKE --> OBSERVE["Validate invocation observation<br/>Complete provider operation"]
    OBSERVE --> ADMIT{"admit-model-response"}
    ADMIT -->|Accepted| CLOSE["complete-model-request"]
    ADMIT -->|Invalid response| CORRECT["build-model-protocol-retry<br/>Retain request identity and schema"]
    CORRECT -->|Correction available| ACCOUNT
    CORRECT -->|Correction unavailable| FAILED["End failed"]
    ADMIT -->|Failed or cancelled| CLOSE
    CLOSE --> OUTCOME["Return typed outcome to caller"]
    OUTCOME -->|Composition part accepted| RETAIN["retain-json-part<br/>Deterministic; no model call"]
    OUTCOME -->|Ordinary request accepted| COLLECT["Caller collects and validates candidate<br/>May authorize a separate repair request"]

    classDef model fill:#dbeafe,stroke:#2563eb,color:#111827;
    class INVOKE model;
```

Authorization, lifecycle or accounting failures terminate through their declared
outcomes; those terminal branches are collapsed above. Failed, cancelled and
invalid outcomes remain distinct. Model-assisted review is candidate evidence,
not deterministic semantic proof.

The call counts shown in the trees exclude protocol retries, authorized repairs,
localization and repeated work after upstream renewal. There is no fixed total
for the workflow. The configured `spec_generation` and `repair` slots select
models; a slot name does not imply a single call.
