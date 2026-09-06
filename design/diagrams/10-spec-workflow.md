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
    RENDER --> PUBLISH["Publish the complete artifacts and workflow state together;<br/>preserve user-closed clarification files"]
    PUBLISH --> DONE["Mark the feature specified;<br/>ready for user review and then plan"]

    UNDERSTAND -->|Missing or conflicting meaning| CLARIFY
    BRIEF -->|Clarification required| CLARIFY
    SPEC -->|Clarification required| CLARIFY
    CHECK -->|Missing or unsupported business knowledge| CLARIFY
    CLARIFY["Resolve clarification questions;<br/>reuse existing questions for the same subject"]
    CLARIFY -->|Protected answer needs reconsideration| BLOCKED["End blocked;<br/>user direction is required"]
    CLARIFY -->|Question can be created or refreshed| QUESTIONS["Save clarification questions in clarify/SNN.md;<br/>retain existing protected answers"]
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
live model iteration, answer application, clarification writing and the complete
Specify generation/publication flow shown here remain unfinished.

Every rerun starts the workflow from the beginning. A successful rerun replaces
the workflow's existing outputs at the same paths while preserving user-closed
clarification files. Failure, blocking or cancellation ends the run without
publishing a partial successful specification.
