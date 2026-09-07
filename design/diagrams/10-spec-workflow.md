High-level execution flow for the Specify workflow.

```mermaid
flowchart TD
    START["Run sdd specify<br/>--feature FEATURE --reference SOURCE"]
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
    CHECK -->|Missing or unsupported business knowledge| CLARIFY
    CLARIFY["Resolve clarification questions;<br/>reuse existing questions for the same subject"]
    CLARIFY -->|Protected answer needs reconsideration| BLOCKED["End blocked;<br/>user direction is required"]
    CLARIFY -->|Question can be created or refreshed| QUESTIONS["Create new forms; completely overwrite unresolved clarify/SNN.md at the same IDs;<br/>preserve user-resolved forms"]
    QUESTIONS --> NEEDSUSER["End needs_user;<br/>publish no partial specification"]
    NEEDSUSER -. User answers the questions and reruns the command .-> START

    CHECK -->|Mechanical validation defect| REPAIR["Repair only the invalid content<br/>within the declared retry limits"]
    REPAIR -->|Repaired candidate| CHECK
    REPAIR -->|Retry limit exhausted| BLOCKED
```

`FEATURE` is relative to the configured `paths.specs`; `SOURCE` is relative
to `paths.references`. The feature title and requirements come from reference
material and validated answers.

Markdown inline-code interiors are exact-value candidates; prose, quoted text
and fenced code are not candidates through that extractor. Preserved values
retain original bytes and citations, without implying semantic approval or
operational authority. This in-memory boundary and scripted hierarchical
reconciliation are implemented. H-008 implements the shared required-authority
contract and Specify projection; support is not inferred from citation presence.
The same gate is rebuilt against current inputs before generation/publication,
and stale source lineage cannot authorize a consumer. Group size is explicit
in YAML; the selected reference directory defines related documents. Unresolved conflicts block;
model-connected iteration, generation, coverage and bounded repair are
implemented by H-009/H-010. H-011/H-012 now connect unit-need forms to the shared
writer and render/reparse specifications in memory. Answer application and
complete specification publication remain open; the final definition is H-013.

The current generation YAML publishes unit-need forms; successful specification
content remains in memory until the complete sidecar/state set is available:

```mermaid
flowchart LR
    R["Captured references"] --> X["Model extraction and<br/>hierarchical reconciliation"]
    X --> A["Shared source-authority gate"]
    A --> G["Generate one typed unit"]
    G --> W{"Closed response schema?"}
    W -->|Malformed| Q["Bounded protocol correction;<br/>same request and valid schema example"]
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
    S --> M["Project, render and reparse in memory;<br/>no spec.md publication"]
```

Each model path uses the same request/provider operations and explicit cleanup.
Protocol correction keeps the original request/schema; atomic repair binds a
new request to an engine authorization. Workflow schemas and native decoding
share the closed `kind` alternatives; malformed root/nested variants fail
before request closure. Invalid, exhausted and unresolved paths
cannot reach accepted content. Model review is not deterministic semantic proof.

Every rerun starts the workflow from the beginning. A successful rerun completely
overwrites all registered replaceable outputs at the same paths. Clarification
publication completely overwrites unresolved forms at the same IDs/paths,
including open answer drafts, while user-resolved forms remain byte-for-byte
unchanged. This is the shared rule for every workflow execution. Failure,
blocking or cancellation ends the run without publishing a partial successful
specification.
If publication itself fails or is interrupted, already-replaced files may
remain; no new successful completion is recorded. A fresh rerun replaces the
output set without rollback or recovery machinery (Design §25).
