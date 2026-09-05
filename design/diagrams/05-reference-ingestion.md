High-level flow for turning selected reference material into supported workflow inputs.

```mermaid
flowchart TD
    START["Workflow selects a reference directory"] --> INVENTORY["Inventory all sources in deterministic order;<br/>validate containment, supported formats and resource bounds"]
    INVENTORY -->|Valid| CAPTURE["Capture source bytes through authorized readers"]
    CAPTURE --> DECODE["Decode sources and retain their exact locations;<br/>account for every source and block"]
    DECODE --> CHUNKS["Prepare bounded, citable chunks"]
    NAMING["Compile every selected toolchain naming rule"] --> GRAMMAR["Build shared path-token grammar;<br/>include every captured reference basename"]
    CHUNKS --> GRAMMAR
    GRAMMAR -. "Typed-text validation input" .-> ACCOUNT
    CHUNKS --> EXTRACT["Extract candidate claims, context and exact values"]
    EXTRACT --> ACCOUNT["Validate citations and source coverage;<br/>account for chunks containing no relevant claims"]
    ACCOUNT -->|Valid| RECONCILE["Reconcile meaning across the complete reference set;<br/>apply current validated clarification answers"]
    RECONCILE --> CHECK{"Required meaning supported and conflicts resolved?"}
    CHECK -->|Yes| CANDIDATE["Retain validated reference inputs<br/>for subsequent workflow steps"]
    CHECK -->|Clarification required| CLARIFY["Save or reuse questions for the same subject;<br/>preserve protected answers and end needs_user"]
    CHECK -->|Repairable candidate defect| REPAIR["Repair the authorized unit<br/>within the declared retry limits"]
    REPAIR -->|Repaired candidate| ACCOUNT
    REPAIR -->|Exhausted| BLOCKED["End blocked or failed"]
    INVENTORY -->|Unsafe, unreadable or unsupported| FAILED["End failed;<br/>publish no partial workflow output"]
    CAPTURE -->|Failed| FAILED
    DECODE -->|Incomplete or invalid| FAILED
    ACCOUNT -->|Invalid| FAILED
```

Citation checks establish where content came from. Semantic interpretation is
model-assisted and remains subject to validation and user review. Reference
candidates stay inside the current execution until whole-workflow publication;
clarifications are retained when a new run is needed.

The registered naming compiler, grammar builder and detector are implemented.
Scanning returns byte spans, not file authority or validated business text.
Typed-text/passive-literal validation and full environment/repository bindings
remain separate work. See [F0100 §3.6](../features/F0100-SpecWorkflow.md#36-shared-naming-policy-and-path-token-grammar).
