High-level execution flow for the Specify workflow, following
[Design Section 17](../design.md#17-specify-stage-design) and
[F0100](../features/F0100-SpecWorkflow.md).

```mermaid
flowchart TD
    START["Run sdd specify<br/>--feature FEATURE --reference SOURCE"]
    START --> SETUP["Load project configuration and select the Specify workflow;<br/>prepare the required model provider"]
    SETUP --> INPUTS["Validate feature and reference locations;<br/>load existing feature state and clarification answers"]
    INPUTS --> READ["Read the selected reference material;<br/>account for every source"]
    READ --> UNDERSTAND["Extract and reconcile reference meaning;<br/>apply current validated clarification answers"]
    UNDERSTAND --> BRIEF["Generate the feature title, description and goal"]
    BRIEF --> SPEC["Generate scenarios, outcomes, edge cases and acceptance criteria;<br/>requirements, business rules and scope;<br/>key entities when the feature involves business data"]
    SPEC --> CHECK{"Is the complete specification<br/>valid and fully supported?"}

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

Every rerun starts the workflow from the beginning. A successful rerun replaces
the workflow's existing outputs at the same paths while preserving user-closed
clarification files. Failure, blocking or cancellation ends the run without
publishing a partial successful specification.

Within reference understanding, native operations now parse scripted extraction
results, validate citation integrity, assign claim/citation IDs and require
complete chunk accounting. They produce unreviewed in-memory candidates, not
reconciled authority. Model extraction, semantic reconciliation and the later
generation/publication stages remain unfinished
([F0100 §3.5](../features/F0100-SpecWorkflow.md#35-extraction-candidate-accounting)).
