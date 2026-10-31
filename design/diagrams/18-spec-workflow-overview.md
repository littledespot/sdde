# Specification workflow overview

The supplied definition uses `spec-generation`. This view includes the accepted
[ADR 0023](../decisions/0023-advisory-post-generation-review.md) amendment; the
overall governing design remains proposed.

```mermaid
flowchart TD
    START["Run Specify with a feature directory and reference selector"]
    START --> PREPARE["Load configuration and workflow;<br/>validate inputs and applicable answers"]
    PREPARE --> REFERENCES["Account for sources;<br/>extract and reconcile claims"]
    REFERENCES --> AUTHORITY{"Pre-generation preservation and<br/>required source authority resolved?"}
    AUTHORITY -->|Yes| GENERATE["Generate brief, story, entities and records;<br/>native validation owns admission and bounded unit repair"]
    AUTHORITY -->|Authorized source loss| SOURCE_REPAIR["Bounded source repair before generation;<br/>renew affected dependencies"]
    SOURCE_REPAIR --> AUTHORITY
    GENERATE --> REVIEW["Source and principle review by whole native assignment;<br/>retain original semantic findings as advice"]
    REVIEW --> RESULT{"Native candidate valid and<br/>bound assessments complete?"}
    RESULT -->|Yes, including adverse advice| OUTPUT["Render, reparse and validate outputs,<br/>canonical state and current inputs"]
    RESULT -->|Advice incomplete: marked and logged| OUTPUT
    OUTPUT --> PUBLISH["Replace registered outputs;<br/>write workflow state last"]
    PUBLISH -->|All writes succeed| DONE["Specification available for user review and Plan gate"]
    AUTHORITY -->|Required business decision missing| CLARIFY
    GENERATE -->|Declared knowledge gap| CLARIFY
    CLARIFY["Prepare exact required decision;<br/>refresh stable question IDs and protect resolved files"]
    CLARIFY -->|Valid forms saved| NEEDSUSER["End needs_user; publish incomplete specification"]
    NEEDSUSER -. User answers and starts a fresh invocation .-> START
    RESULT -->|Correctable native metadata defect| CORRECTION["Bounded correction with current scope and unchanged verdict"]
    CORRECTION --> RESULT
    AUTHORITY -->|Unknown ownership or exhausted correction| STOP["Typed blocked or failed outcome"]
    GENERATE -->|Unsafe or exhausted repair| STOP
    RESULT -->|Invalid authority or exhausted correction| STOP
    OUTPUT -->|Invalid output or stale input| STOP
    CLARIFY -->|Write failure or protected answer needs review| STOP
    PUBLISH -->|Write failure or interruption| STOP
```

- Semantic review is advisory, including principle findings. It supplies no
  automatic content repair, upstream rebuild, question or mandatory Plan obligation.
  Incomplete review is still published, marked and logged
  ([ADR 0040](../decisions/0040-incomplete-review-published-marked-logged.md)).
- Native requiredness, provenance, exact coverage, citations, current authority
  and publication gates remain mandatory. Source repair rejects once generation
  starts, including direct use through a custom workflow.
- Clarifications persist across invocations; fresh invocations start at `start`.
  Failed publication may leave replaced files without recording new completion.
- Open Spec questions stop Plan; open Spec or Plan questions stop Tasks. Plan
  independently validates required current policy.
- Failed, blocked, cancelled and completed remain distinct outcomes.

See the [Specify contract](../contracts/17-specify.md),
[workflow definition](../workflows/spec.workflow.yaml),
[publication decision](../decisions/0009-atomic-workflow-execution.md) and
[detailed specification flow](10-spec-workflow.md).
