```mermaid
%% Logical Specify behavior from design Section 17.
%% Exact serializable node boundaries and registered contract IDs remain registry-owned.
flowchart TD
    A[Resolve workflowId specify] --> P[Fixed model-provider preparation from selected graph capabilities<br/>ready or not_required continues; failure or cancellation terminates]
    P --> B[Registered Specify invocation contract]
    B --> C[Registered parser and validator<br/>required --feature directory and independent --reference selector]
    C --> FD[Resolve --feature relative to paths.specs from .sddtoolkit.json;<br/>normalize validate and inspect with containment no-follow and archive exclusion;<br/>no repeated root generated name or ownership registry]
    FD --> C1[normalize-reference-selector@1<br/>Shared pinned NFC; separators and literal dots]
    FD -->|Invalid or unsafe| PF
    C1 --> C2[validate-reference-selector@1<br/>Lexical safety and bounds]
    C2 --> C3[inspect-reference-directory@1<br/>Bound root identity; no-follow readable directory]
    C3 --> D[Validate the selected feature's required existing state<br/>and complete reference corpus; no cross-feature scan]
    D --> CL[Load retained clarification history and forms;<br/>preserve user-closed bytes before ingestion and consume applicable validated answers;<br/>accepted closure commits its response without rerendering the submitted form]
    CL --> E[Ingest and reconcile complete reference authority]
    CL -->|Stale or invalid user close, or protected answer requires reconsideration| CB[Block for explicit user direction;<br/>do not overwrite the form or allocate a duplicate clarification]

    E -->|All required authority resolved| F[Generate and validate reference-grounded feature brief]
    E -->|Specification-owned gap| S[Create or refresh only unprotected clarify/SNN.md forms;<br/>retain protected forms in the complete view set and commit spec_clarification_pending;<br/>no new partial SpecificationIR or spec.md]

    F --> G[Generate typed User Scenarios and Testing units:<br/>Primary User Story, AC, UO and EC]
    G --> H[Generate typed Requirements units:<br/>FR, BR, assumptions, non-goals and prohibited behaviors]
    H --> Q{Validated Key Entities applicability}
    Q -->|Feature involves data| EN[Generate and validate EN records]
    Q -->|Validated not applicable| V
    Q -->|Missing or ambiguous| S
    EN --> V[Run deterministic unit and complete-candidate validation;<br/>retry and atomic-repair operations and transitions are explicit in YAML;<br/>each retry-capable operation declares its own retry-limit]

    V -->|Clarification required| S
    V -->|Valid complete content| I[Assign record IDs and build complete SpecificationIR]
    I --> J[Validate fixed heading order, required groups,<br/>conditional entities, and absence of placeholders or inline clarification]
    J --> K[Render spec.md and reference-context.md]
    K --> M[Reparse spec.md and compare normalized IR]
    M --> N[Publish only the complete validated workflow output;<br/>reruns MUST overwrite existing Specify outputs at the same registered paths;<br/>no separate overwrite approval;<br/>user-closed clarification files MUST remain byte-for-byte unchanged;<br/>never clear the feature directory]
    N --> O[Workflow state specified]

    S --> NU[Terminal needs_user; preserve clarifications and end execution;<br/>a later invocation starts the entire workflow again]
    C -->|Rejected invocation| PF[Terminal failed; no feature or artifact writes]
    C1 -->|Failed| PF
    C2 -->|Failed| PF
    C3 -->|Failed| PF
    D -->|Blocked| BL[Terminal blocked]
    D -->|Failed| FL[Terminal failed]
    V -->|Repair exhausted or blocked| BL
    V -->|Operational failure| FL
    V -->|Cancelled| CA[Terminal cancelled]
```
