High-level execution flow for the Specify workflow.

```mermaid
flowchart TD
    START["Run sdde WORKFLOW_ID<br/>--feature FEATURE --reference SOURCE"]
    START --> SETUP["Load project configuration and select the Specify workflow;<br/>prepare the required model provider"]
    SETUP --> INPUTS["Validate feature and reference locations;<br/>load existing feature state and clarification answers"]
    INPUTS --> READ["Read the selected reference material;<br/>account for every source"]
    READ --> EXACT["Prepare eligible source-backed exact values;<br/>require complete preserve/irrelevant classifications"]
    EXACT --> UNDERSTAND["Account for typed and preserved-token claims;<br/>reconcile within-source, cross-source and global groups"]
    UNDERSTAND --> RECONCILED["Validate total dispositions, signals and conflict joins;<br/>retain claim meaning, citations and exact tokens"]
    RECONCILED --> AUTH{"Shared required-authority gate:<br/>complete current support?"}
    AUTH -->|Supported| BRIEF["Generate the feature title, description and goal"]
    AUTH -->|Business/reference gap| CLARIFY
    AUTH -->|Unknown ownership or policy| BLOCKED
    BRIEF --> SPEC["Generate scenarios, outcomes, edge cases and acceptance criteria;<br/>requirements, business rules and scope;<br/>key entities when the feature involves business data"]
    SPEC --> CHECK{"Mechanical checks and shared<br/>required-authority gate pass?"}

    CHECK -->|Yes| RENDER["Render and verify spec.md<br/>and reference-context.md"]
    RENDER --> PUBLISH["Completely replace registered outputs with validated artifacts and state;<br/>preserve user-resolved clarification files"]
    PUBLISH -->|All writes succeed| DONE["Mark the feature specified;<br/>ready for user review and then plan"]
    PUBLISH -->|Write failure or interruption| WRITEFAIL["No new successful completion;<br/>replaced files may remain; fresh rerun from start"]

    UNDERSTAND -->|Missing or conflicting meaning| CLARIFY
    BRIEF -->|Clarification required| CLARIFY
    SPEC -->|Clarification required| CLARIFY
    CHECK -->|Genuine source-authority gap| CLARIFY
    CLARIFY["Resolve clarification questions;<br/>reuse existing questions for the same subject"]
    CLARIFY -->|Protected answer needs reconsideration| BLOCKED["End blocked;<br/>user direction is required"]
    CLARIFY -->|Question can be created or refreshed| QUESTIONS["Create new forms; completely overwrite unresolved clarify/SNN.md at the same IDs;<br/>preserve user-resolved forms"]
    QUESTIONS --> NEEDSUSER["End needs_user;<br/>publish no partial specification"]
    NEEDSUSER -. User answers the questions and reruns the command .-> START

    CHECK -->|Repairable candidate defect or supported omission| REPAIR["Repair only the authorized content<br/>within the declared retry limits"]
    REPAIR -->|Repaired candidate| CHECK
    REPAIR -->|Retry limit exhausted| BLOCKED
```

- `FEATURE` is relative to `paths.specs`; `SOURCE` is relative to `paths.references`.
- Reference material and validated answers supply the title and requirements.
- The supplied definition declares `id: spec-generation`; filenames do not
  determine workflow identity.

[F0100](../features/F0100-SpecWorkflow.md) owns exact-value extraction,
reconciliation, shared authority gates, content and publication contracts. Its
implementation-status sections distinguish H-008–H-012 evidence and remaining
work from live completion and semantic quality.

Generation YAML publishes unit-need forms or the complete validated
specification/sidecar/state set:

```mermaid
flowchart LR
    R["Captured references"] --> X["Model extraction and<br/>hierarchical reconciliation"]
    X --> A["Shared source-authority gate"]
    A --> G["Generate one typed unit"]
    G --> W{"Closed response schema?"}
    W -->|Malformed| Q["Bounded protocol correction;<br/>same request and precise schema guidance"]
    Q --> G
    Q -->|Exhausted| F["End failed"]
    W -->|Valid| V{"Unit valid?"}
    V -->|Repairable defect| P["Engine-selected replacement;<br/>bounded YAML repair"]
    P --> V
    V -->|Yes; more units| G
    V -->|All units| C["Assemble, revalidate,<br/>assign IDs and account coverage"]
    V -->|Knowledge gap| N["Refresh subject-keyed form<br/>and retain protected history"]
    N --> O["Prepare complete clarification view/state set"]
    O --> B["Recheck captured inputs;<br/>replace writable forms and registry"]
    B --> U["End needs_user; no spec.md"]
    B -->|Write failure| F
    C --> S["Model-assisted field support<br/>and shared authority gate"]
    S -->|Supported complete candidate| M["Project, render and reparse;<br/>prepare specification, sidecar and canonical states"]
    S -->|Genuine source gap| N
    S -->|Repairable candidate omission| P
    S -->|No independent supported repair target| F
    M --> PUB["Validate complete output and captured-input preconditions;<br/>replace registered files, workflow state last"]
    PUB -->|All writes succeed| DONE["End ok; published specification available to evaluator"]
    PUB -->|Write failure or interruption| FAIL["No new successful completion;<br/>replaced files may remain"]
```

- [Model request ownership](../decisions/0012-workflow-owned-model-request.md)
  keeps protocol correction on the original request/schema and binds repair to
  a fresh authorized request. Closed variants validate before request closure.
- [Design §23.2](../design.md#232-workflow-reruns-and-protected-clarification-files)
  owns rerun replacement and user-closed clarification protection.
- [Design §25](../design.md#25-atomic-workflow-execution-and-output) owns publication:
  failed writes may leave replaced files but cannot record new successful completion.
- Model-assisted review does not prove semantic correctness.
