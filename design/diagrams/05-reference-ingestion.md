High-level flow for turning selected reference material into supported workflow inputs.
Extraction uses the configured content/classification split of
[ADR 0016](../decisions/0016-configured-json-response-composition.md).

```mermaid
flowchart TD
    START["Workflow selects a reference directory"] --> INVENTORY["Inventory all sources in deterministic order;<br/>validate containment, supported formats and resource bounds"]
    INVENTORY -->|Valid| CAPTURE["Capture source bytes through authorized readers"]
    CAPTURE --> DECODE["Decode sources and retain their exact locations;<br/>account for every source and block"]
    DECODE --> CHUNKS["Prepare bounded, citable chunks"]
    NAMING["Compile every selected toolchain naming rule"] --> GRAMMAR["Build shared path-token grammar;<br/>include every captured reference basename"]
    CHUNKS --> GRAMMAR
    GRAMMAR --> LITERALS["Scan source-backed display literals;<br/>assign IDs and validate exact origins"]
    LITERALS --> TEXT["Quote each claim's cited lines as written,<br/>one claim per top-level list item;<br/>validate typed text: reject inline paths and out-of-scope IDs"]
    CHUNKS --> FACTS["Extract eligible exact facts;<br/>Markdown inline code, fenced code and link destinations,<br/>not prose or quotes"]
    FACTS --> TOKENIDS["Assign source/extractor-local candidate IDs;<br/>retain exact source bytes and citations"]
    TOKENIDS --> EXTRACT["Configured content request:<br/>claims as a category and supplied line IDs,<br/>or no_feature_claim with its reason"]
    EXTRACT --> PARTS["Configured dependent request:<br/>classify supplied exact-token candidates"]
    TOKENIDS --> PARTS
    PARTS --> ASSEMBLE["Generic native assembly with each producer's provenance;<br/>no LLM prompt or call; validate complete JSON shape"]
    ASSEMBLE --> TEXT
    TEXT --> CLASSIFY["Validate total chunk-local token classifications;<br/>canonical business/scope byte matches force preservation;<br/>kind cannot remove the native exact duty"]
    CLASSIFY --> TOKENS["Assign preserved-token IDs and build deterministic claims;<br/>keep exact bytes and derive obligation identities"]
    TOKENS --> ACCOUNT["Validate and identify all claims and citations;<br/>prove total chunk coverage and one claim per preserved token"]
    ACCOUNT -->|Valid| ITEMS["Retain typed claims, original citations and token references"]
    ITEMS --> WITHIN["Partition within each source in claim order;<br/>explicit YAML group-size"]
    WITHIN --> CROSS["Validate complete summary membership;<br/>group across the selected directory's sources"]
    CROSS --> GLOBAL["Group global summaries recursively;<br/>retain original claim membership and payloads"]
    GLOBAL --> DISPOSITIONS["Models dispose semantic claims only;<br/>native tokens retain distinct bytes or directly duplicate<br/>their earliest equal-byte original; validate all joins"]
    DISPOSITIONS --> SIGNALS["Validated dispositions feed the signals request;<br/>validate signal content and claim joins"]
    SIGNALS --> CONFLICTS["Validated signals feed conflict explanations<br/>over native group handles; validate joins"]
    CONFLICTS --> RECORDS["Validate signal / citation / token / conflict joins;<br/>assign engine IDs and validate complete lineage"]
    RECORDS -->|Candidate and conflict evidence| CHECK{"Shared authority gate:<br/>required meaning supported and conflicts resolved?"}
    CHECK -->|Yes| CANDIDATE["Retain validated reference inputs<br/>for subsequent workflow steps"]
    CHECK -->|Clarification required| CLARIFY["Reuse subject IDs; completely overwrite unresolved forms;<br/>preserve user-resolved forms and end needs_user"]
    CHECK -->|Supported candidate omission| DIAGNOSTIC
    DIAGNOSTIC{"Native diagnostic classification"} -->|Repairable candidate defect| REPAIR["Repair only the authorized unit;<br/>retain owner, revision, old value and dependencies"]
    REPAIR -->|Merged within the declared limit| REVALIDATE["Rerun the owning validator, impacted dependents<br/>and complete candidate validation"]
    REVALIDATE -->|Valid| CHECK
    REVALIDATE -->|Rejected| DIAGNOSTIC
    DIAGNOSTIC -->|Invalid trusted context or no safe target| BLOCKED["End blocked or failed"]
    REPAIR -->|Exhausted, stale or unauthorized| BLOCKED
    INVENTORY -->|Unsafe, unreadable or unsupported| FAILED["End failed;<br/>publish no partial workflow output"]
    CAPTURE -->|Failed| FAILED
    DECODE -->|Incomplete or invalid| FAILED
    ACCOUNT -->|Invalid| FAILED
    TEXT -->|Invalid candidate| DIAGNOSTIC
    FACTS -->|Uncitable or over-limit value| FAILED
    CLASSIFY -->|Invalid candidate| DIAGNOSTIC
    TOKENS -->|Preservation contradicts positive empty| DIAGNOSTIC
    LITERALS -->|Invalid or stale| FAILED
    DISPOSITIONS -->|Invalid record, relationship or cycle| DIAGNOSTIC
    DISPOSITIONS -->|"Missing or repeated claim after correction (ADR 0046)"| FAILED
    SIGNALS -->|Invalid| DIAGNOSTIC
    CONFLICTS -->|Invalid| DIAGNOSTIC
    RECORDS -->|Incomplete or invalid| DIAGNOSTIC
```

Citation checks prove source location; semantic interpretation requires
validation and user review. Scanning yields byte spans, not file authority.
Candidates remain execution-local; permitted clarification state survives reruns.

Contracts and implementation evidence: [Design §16](../design.md#16-reference-ingestion-and-normalization)
and [F0100 §§3.6–3.9](../features/F0100-SpecWorkflow.md#39-reference-reconciliation-boundary),
as amended by [ADR 0022](../decisions/0022-native-reference-phase-handoffs.md),
[ADR 0024](../decisions/0024-native-exact-token-authority.md),
[ADR 0036](../decisions/0036-source-quoted-claims.md) and
[ADR 0038](../decisions/0038-record-claims-and-scenario-coverage.md).
Scripted verification does not establish live completion or semantic quality.
