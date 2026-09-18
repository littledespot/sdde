# Configured JSON response composition

Design pending implementation, governed by
[ADR 0016](../decisions/0016-configured-json-response-composition.md). Two parts
illustrate one dependency; property names and shapes come from configuration.

```mermaid
flowchart TD
    Config["Workflow resources: complete schema and part partition"] --> Compile["Existing compiler: resolve schema, ownership and dependencies"]
    Compile --> Plan["Sealed part schemas and ordinary workflow bindings"]
    Evidence["Current source, policy and declared evidence"] --> A
    Plan --> A["Existing model-request flow: part A"]
    A --> AdmitA{"Decode and validate A"}
    AdmitA -->|Rejected; allowance remains| CorrectA["Correct complete A; same assignment"]
    CorrectA --> A
    AdmitA -->|Admitted| RetainA["Retain A with real producer and dependency revisions"]
    RetainA --> B["Existing model-request flow: dependent part B"]
    Evidence --> B
    Plan --> B
    B --> AdmitB{"Decode and validate B"}
    AdmitB -->|Rejected; allowance remains| CorrectB["Correct complete B; preserve current A"]
    CorrectB --> B
    AdmitB -->|Admitted| RetainB["Retain B with real producer and dependency revisions"]
    RetainA --> Assemble["Pure native assembly: configured structural placement; no LLM or prompt"]
    RetainB --> Assemble
    Plan --> Assemble
    Assemble --> Candidate["One current unvalidated candidate with captured evidence;<br/>retire staging, retain history"]
    Candidate --> Full["Validate complete schema and existing domain obligations"]
    Full -->|Valid| Continue["Continue workflow; full output validation precedes publication"]
    Full -->|Authorized defect| Repair["Existing native atomic repair and dependent rebuilding"]
    Repair --> Full
    AdmitA -->|Exhausted| Stop["Failed or blocked; no partial successful output"]
    AdmitB -->|Exhausted| Stop
    Full -->|No authorized recovery| Stop
```

All arrows represent declared runner-owned child bindings. Every model call uses
the existing request lifecycle and shared actual-token budget; assembly adds no
call or counter. Configured dependencies govern active part staging; existing
native repair owners govern the complete candidate after handoff. Changing producer
attribution cannot reset its stable repair association. Captured handoff preserves
source/policy freshness without a dependency on the retired staging slot.
The finite compiler ceiling may increase under the user's explicit approval;
its new value and storage/overflow behavior must be verified during implementation.
Admission includes successful logical-request closure; schema evidence alone cannot
authorize retention. Candidate handoff and staging retirement use one runner delta.
Native repair returns to validation and derived rebuilding, never to part assembly.
