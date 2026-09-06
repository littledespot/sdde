High-level flow for turning selected reference material into supported workflow inputs.

```mermaid
flowchart TD
    START["Workflow selects a reference directory"] --> INVENTORY["Inventory all sources in deterministic order;<br/>validate containment, supported formats and resource bounds"]
    INVENTORY -->|Valid| CAPTURE["Capture source bytes through authorized readers"]
    CAPTURE --> DECODE["Decode sources and retain their exact locations;<br/>account for every source and block"]
    DECODE --> CHUNKS["Prepare bounded, citable chunks"]
    NAMING["Compile every selected toolchain naming rule"] --> GRAMMAR["Build shared path-token grammar;<br/>include every captured reference basename"]
    CHUNKS --> GRAMMAR
    GRAMMAR --> LITERALS["Scan source-backed display literals;<br/>assign IDs and validate exact origins"]
    LITERALS --> TEXT["Validate typed extraction text;<br/>reject inline paths and out-of-scope IDs"]
    CHUNKS --> FACTS["Extract eligible exact facts;<br/>Markdown inline code only, not prose, quotes or fenced code"]
    FACTS --> TOKENIDS["Assign source/extractor-local candidate IDs;<br/>retain exact source bytes and citations"]
    TOKENIDS --> EXTRACT["Propose typed claims and one preserve/irrelevant<br/>classification per supplied candidate"]
    EXTRACT --> TEXT
    TEXT --> CLASSIFY["Validate total chunk-local token classifications;<br/>reject missing, duplicate, foreign or stale candidates"]
    CLASSIFY --> TOKENS["Assign preserved-token IDs and build deterministic claims;<br/>keep exact bytes and derive obligation identities"]
    TOKENS --> ACCOUNT["Validate and identify all claims and citations;<br/>prove total chunk coverage and one claim per preserved token"]
    ACCOUNT -->|Valid| ITEMS["Retain typed claims, original citations and token references"]
    ITEMS --> WITHIN["Partition within each source in claim order;<br/>explicit YAML group-size"]
    WITHIN --> CROSS["Validate complete summary membership;<br/>group across the selected directory's sources"]
    CROSS --> GLOBAL["Group global summaries recursively;<br/>retain original claim membership and payloads"]
    GLOBAL --> DISPOSITIONS["Require one retained / superseded / duplicate / conflicting<br/>disposition per original claim; validate every relationship"]
    DISPOSITIONS --> RECORDS["Validate signal / citation / token / conflict joins;<br/>assign engine IDs and validate complete lineage"]
    RECORDS -->|Unresolved conflict| BLOCKED
    RECORDS -->|Structurally valid candidate| CHECK{"Required meaning supported and conflicts resolved?"}
    CHECK -->|Yes| CANDIDATE["Retain validated reference inputs<br/>for subsequent workflow steps"]
    CHECK -->|Clarification required| CLARIFY["Save or reuse questions for the same subject;<br/>preserve protected answers and end needs_user"]
    CHECK -->|Repairable candidate defect| REPAIR["Repair the authorized unit<br/>within the declared retry limits"]
    REPAIR -->|Revalidate repaired candidate| TEXT
    REPAIR -->|Exhausted| BLOCKED["End blocked or failed"]
    INVENTORY -->|Unsafe, unreadable or unsupported| FAILED["End failed;<br/>publish no partial workflow output"]
    CAPTURE -->|Failed| FAILED
    DECODE -->|Incomplete or invalid| FAILED
    ACCOUNT -->|Invalid| FAILED
    TEXT -->|Invalid| FAILED
    FACTS -->|Uncitable or over-limit value| FAILED
    CLASSIFY -->|Invalid| FAILED
    TOKENS -->|Preservation contradicts positive empty| FAILED
    LITERALS -->|Invalid or stale| FAILED
    DISPOSITIONS -->|Missing, duplicate, foreign or invalid| FAILED
    RECORDS -->|Incomplete or invalid| FAILED
```

Citation checks establish where content came from. Semantic interpretation is
model-assisted and remains subject to validation and user review. Reference
candidates stay inside the current execution until whole-workflow publication;
clarifications are retained when a new run is needed.

The registered naming compiler, grammar builder and detector are implemented.
Scanning returns byte spans, not file authority or validated business text.
Typed-text/passive-literal validation is implemented for execution-local
reference candidates. Inline-code eligibility and exact-value classification,
identity and accounting are implemented with scripted results. A positive
`no_feature_claim` cannot retain a preserved-token claim. Hierarchical grouping,
summary/disposition accounting and identified signals/conflicts are implemented
with scripted results. Unresolved conflicts return `blocked`; no resolution is
invented. The clarification/semantic-review continuation is still future work. Full
environment/repository bindings, live semantic extraction, review and publication
remain separate work. See [F0100 §§3.6–3.9](../features/F0100-SpecWorkflow.md#39-reference-reconciliation-boundary).
