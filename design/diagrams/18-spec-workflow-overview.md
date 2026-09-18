# Specification workflow overview

High-level view of the proposed Specify workflow. The supplied workflow definition
uses the ID `spec-generation`.
Principle assessment and question preparation below include the accepted, pending
[ADR 0015](../decisions/0015-specification-principle-review.md) additions.

```mermaid
flowchart TD
    START["Run spec-generation<br/>with a feature directory and reference selector"]
    START --> PREPARE["Load configuration and workflow;<br/>validate inputs and reuse applicable clarification answers"]
    PREPARE --> REFERENCES["Read and account for every reference;<br/>extract and reconcile source claims"]
    REFERENCES --> AUTHORITY{"Required source meaning<br/>and authority resolved?"}
    AUTHORITY -->|Yes| POLICY["Assess requirement–principle consistency;<br/>preserve business intent and cite Plan policy obligations"]
    PREPARE -. Canonical selected principle spans .-> POLICY
    POLICY --> GENERATE["Generate the feature brief<br/>and business specification candidates"]
    GENERATE --> REVIEW["Validate structure, citations and coverage;<br/>review source support and refresh affected policy assessments"]
    REVIEW --> RESULT{"Candidate complete,<br/>supported and valid?"}
    RESULT -->|Yes| OUTPUT["Render and verify spec.md and reference-context.md;<br/>validate the complete output, state and current inputs"]
    OUTPUT -->|Valid; clarifications resolved| PUBLISH["Replace registered outputs;<br/>write workflow state last"]
    PUBLISH -->|All writes succeed| DONE["Specification complete;<br/>available for user review and the Plan gate"]

    AUTHORITY -->|Missing or conflicting business knowledge| CLARIFY
    GENERATE -->|Clarification needed| CLARIFY
    RESULT -->|Genuine knowledge gap| CLARIFY
    OUTPUT -->|Unresolved clarification| CLARIFY
    CLARIFY["Prepare the affected requirement, evidence and exact decision;<br/>refresh forms with stable IDs and preserve user-closed files"]
    CLARIFY -->|Forms saved| NEEDSUSER["End needs_user;<br/>no partial specification published"]
    NEEDSUSER -. User answers and starts a fresh run .-> START

    RESULT -->|Repairable candidate defect| REPAIR["Repair only authorized content<br/>within the declared retry limit"]
    REPAIR -->|Revalidate repaired candidate| REVIEW
    REPAIR -->|Exhausted or disallowed| STOP["Stop without successful completion"]
    AUTHORITY -->|Cannot establish ownership or policy| STOP
    POLICY -->|Invalid or incomplete assessment evidence| STOP
    OUTPUT -->|Invalid output or stale inputs| STOP
    CLARIFY -->|Write failure or protected answer needs review| STOP
    PUBLISH -->|Write failure or interruption| STOP
```

- The feature directory is relative to `paths.specs`; the reference selector is
  relative to `paths.references`.
- Model output remains a candidate. Semantic review is model-assisted; the engine
  owns validation, repair authorization, rendering and publication.
- Upstream omission repair uses [shared dependency renewal](../../fixes/IMP_001.md#r32-follow-up--shared-protocol-progress-and-recurrence)
  and complete rebuilding. Progress requires a stable semantic-subject join;
  regenerated ordinals alone cannot establish recovery.
- Clarifications persist across runs, but each rerun starts from the beginning.
  Publication failure may leave replaced files without recording new completion.
- Open Spec clarifications stop Plan before planning work; open Spec or Plan
  clarifications stop Tasks before task generation. Policy obligations do not bypass
  either gate. Once Spec is valid, Plan resolves its mandatory policy obligations.
- Failures and cancellation can end any applicable step. The shared stop node
  simplifies the picture; `invalid`, `blocked`, `failed` and `cancelled` remain
  distinct outcomes.

See the [Specify contract](../contracts/17-specify.md),
[workflow definition](../workflows/spec.workflow.yaml),
[execution and publication decision](../decisions/0009-atomic-workflow-execution.md)
and [detailed specification flow](10-spec-workflow.md).
