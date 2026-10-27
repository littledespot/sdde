High-level execution flow for the Specify workflow, including the accepted
[ADR 0023](../decisions/0023-advisory-post-generation-review.md) review policy.
The governing design remains proposed; live quality evidence is tracked in FIX06.

```mermaid
flowchart TD
    START["Run configured Specify workflow<br/>with feature directory and reference selector"]
    START --> SETUP["Load configuration, workflow and provider;<br/>validate inputs and applicable clarification answers"]
    SETUP --> READ["Account for every source;<br/>extract exact values and reconcile claims"]
    READ --> AUTH{"Pre-generation preservation and<br/>required source authority resolved?"}
    AUTH -->|Yes| BRIEF["Generate brief, story and entity applicability"]
    AUTH -->|Authorized source loss| SOURCE_REPAIR["Bounded pre-generation source repair;<br/>renew dependencies and revalidate"]
    SOURCE_REPAIR --> AUTH
    AUTH -->|Genuine missing business decision| CLARIFY
    AUTH -->|Unregistered ownership or exhausted correction| BLOCKED
    BRIEF --> RECORDS["Generate assigned records;<br/>admit prose and reconstruct eligible exact occurrences"]
    BRIEF -->|Declared knowledge gap| CLARIFY
    RECORDS -->|Declared knowledge gap| CLARIFY
    RECORDS --> NATIVE{"Native shape, provenance,<br/>membership and exact coverage valid?"}
    NATIVE -->|Authorized unit defect| REPAIR["Repair only the authorized unit;<br/>retain current bindings and bounded retries"]
    REPAIR --> NATIVE
    REPAIR -->|Exhausted or unsafe| BLOCKED
    NATIVE -->|Yes| REVIEW["Assess source and selected principles by whole native unit;<br/>retain every finding as advice with its origin"]
    SETUP -. Canonical selected principle spans .-> REVIEW
    REVIEW --> ASSESSMENT{"Complete current assessment membership,<br/>citations and native bindings valid?"}
    ASSESSMENT -->|Correctable metadata defect| CORRECT["Correct selected finding metadata;<br/>retain verdict, siblings and retry bounds"]
    CORRECT --> ASSESSMENT
    ASSESSMENT -->|Missing or stale authority; exhausted correction| BLOCKED
    ASSESSMENT -->|Yes, including adverse advice| RENDER["Render and reparse specification and reference context;<br/>validate canonical state and captured inputs"]
    RENDER --> PUBLISH["Replace registered outputs;<br/>workflow state written last"]
    PUBLISH -->|All writes succeed| DONE["End ok; ready for user review and Plan gate"]
    PUBLISH -->|Write failure or interruption| WRITEFAIL["No new successful completion;<br/>replaced files may remain; fresh invocation starts at start"]

    CLARIFY["Prepare the exact unresolved required decision;<br/>reuse subject identity and protect resolved answers"]
    CLARIFY -->|Protected answer needs reconsideration| BLOCKED["End with typed blocked or failed outcome"]
    CLARIFY -->|Valid writable question| QUESTIONS["Publish incomplete specification and question links"]
    QUESTIONS --> NEEDSUSER["End needs_user"]
    NEEDSUSER -. User answers and starts a fresh invocation .-> START
```

- Feature and source selectors are relative to their configured roots. The supplied
  definition declares `id: spec-generation`; its filename does not choose identity.
- Model review proves no semantic truth. Positive and adverse findings complete
  the same bound advisory assessment. Neither triggers content repair, upstream
  rebuilding, a clarification or a mandatory Plan obligation by itself.
- Source-repair authorization, packet preparation and merge reject once generation
  starts, even if a workflow routes directly to those operations.
- Source repair retains its original required review purpose. Generation-ready
  references still need that validation; active repair obligations block generation.
- Native validation and current authority remain mandatory. A real defect uses
  its owning deterministic validator and typed outcome.
- Open Spec questions prevent Plan; open Spec or Plan questions prevent Tasks.
  Plan independently validates current required project policy.

[Specify](../contracts/17-specify.md), [repair](../contracts/22-repair.md) and
[publication](../contracts/25-publication.md) own the detailed
contracts. Model protocol correction retains the original request and schema;
separate authorized native repairs receive fresh bound requests.
