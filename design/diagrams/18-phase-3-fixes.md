# Phase 3 fixes: authorized repair and revalidation

Flow for FIX_001 chunks **08–12**, including the R14/R15 and architecture-audit
follow-ups. The **14 September 2026** offline baseline was reopened by the
[15 September critical review](../../fixes/FIX_001.md#15-september-2026-critical-review).
Selection feasibility and disposition-set equivalence remain open. Shared
eligibility (C3) is consolidated; see the
[closure evidence](../../fixes/IMP_001.md#c3-and-chunk-20-validation--15-september-2026).
This diagram describes the required flow; Phase 3 completion, live E2E and rubric
quality remain unproven.

Each consumer enters the same repair contract. The diagram shows the shared
control flow; workflow YAML selects transitions through runner-owned bindings.

```mermaid
flowchart TD
    INPUT["Candidate from a Phase 3 consumer<br/>Summary, global reconciliation, specification,<br/>extraction or specification coverage"]
    INPUT --> VALIDATE["Run owning validators<br/>Retain native rejection, unit and producing origin"]
    VALIDATE -->|Candidate defect| FACTS
    VALIDATE -->|Local checks pass| FULL
    VALIDATE -->|Missing or conflicting source authority| GAP
    VALIDATE -->|Broken context or operational failure| FAILED

    subgraph REPAIR["08 — Shared authorization and repair"]
        FACTS["Select the next retained diagnostic<br/>Capture current rules and complete native dependencies"]
        FACTS --> SAFE{"Independent permitted target<br/>and mechanically eligible correction?"}
        SAFE -->|No| BLOCKED["Block with the exact reason<br/>G1 applies to unsafe coupled or survivor choices"]
        SAFE -->|Yes| AUTH["Engine selects replace, insert or delete<br/>Bind owner, revision, old value or anchor,<br/>rule authority and immutable read dependencies"]
        AUTH --> LIMIT{"Existing operation limit<br/>permits repair?"}
        LIMIT -->|No| EXHAUSTED["Terminate with exhaustion evidence<br/>Retain last candidate and exact diagnostics"]
        LIMIT -->|Yes| CHOICE{"Semantic value needed?"}
        CHOICE -->|No: engine-proven correction| CHECK
        CHOICE -->|Yes| REQUEST["Project bound facts into a repair request<br/>Supply unchanged context, eligible choices<br/>and the selected value schema"]
        REQUEST --> MODEL["Existing model-request path<br/>Authorize call, account actual tokens,<br/>strictly decode and validate the response schema"]
        MODEL -->|Schema-valid replacement| CHECK
        MODEL -->|JSON or schema rejection| PROTOCOL["Existing bounded protocol correction<br/>Original assignment and schema,<br/>latest rejected bytes and native diagnosis"]
        PROTOCOL -->|Another attempt authorized| MODEL
        PROTOCOL -->|Limit exhausted| EXHAUSTED
        MODEL -->|Failure, cancellation or exhausted budget| TERMINAL["Preserve the typed terminal outcome<br/>No successful continuation"]
        CHECK{"Association and exact preconditions match?<br/>Owner, revision, target, dependencies,<br/>old value or collection anchor"}
        CHECK -->|No| FAILED
        CHECK -->|Yes| MERGE["Apply only the authorized in-memory change<br/>Preserve valid siblings and their origins<br/>Record target origin and advance revision"]
        MERGE --> INVALIDATE["Discard affected derived validation<br/>Rebuild derived values through their owners"]
    end

    INVALIDATE --> RECHECK["Rerun the producing validator<br/>and every declared dependent check"]
    RECHECK -->|Remaining candidate defects| FACTS
    RECHECK -->|Local checks pass| FULL
    RECHECK -->|Authority gap| GAP
    RECHECK -->|Context or operational failure| FAILED
    FULL{"Full candidate validation passes<br/>with current authority?"}
    FULL -->|Candidate defect| FACTS
    FULL -->|Authority gap| GAP
    FULL -->|Context or operational failure| FAILED
    FULL -->|Yes| ACCEPT["Accept for the next workflow step<br/>Summary append or reference authority only after validation<br/>Publication still requires whole-workflow success"]
    GAP["Use the shared authority route<br/>Preserve the gap and its earliest owner<br/>Phase 4 refines support and clarification handling"]
    FAILED["Return the typed failure or rejection<br/>No semantic retry for broken context"]
```

The input has passed JSON/schema validation. Malformed replacements use protocol
correction; reading context grants no write authority. Revision changes and
unchanged invalid values do not establish acceptance.

The [authorized target matrix](../../fixes/IMP_001.md#3-authorized-repair-targets-and-dependency-checks)
owns each consumer's correction scope and required checks:

- **08:** shared native dependencies, exact association and compare-and-swap
  preconditions; immutable read context remains separate from writable scope.
- **09:** validate repaired content/claim membership before appending summary history.
- **10:** revalidate relationships, graph, signals/conflicts and full reconciliation;
  unresolved source conflicts remain blocking.
- **11:** preserve sibling origins while repairing text/provenance; revalidate the
  unit, IDs, coverage and authority. Whole-record repair requires inseparability.
- **12:** revalidate extraction through reconstruction/accounting; exact-copy proof
  may authorize model-free coverage repair. Unsafe/unsupported cases retain their block.

[Phase 3 delivery evidence](../../fixes/IMP_001.md#phase-3--complete-authorized-repair-and-revalidation)
tracks bounded retries, typed context failures and distinct candidate/replacement/
latest-attempt origins. Zero-merge exhaustion retains the original revision/origin;
redundancy cannot delete competing meaning or lose evidence/coverage.

Governing sources: [Design §22](../design.md#22-atomic-repair-protocol),
[invariants 1, 5–9 and 19–23](../design.md#33-non-negotiable-invariants),
[acceptance criteria 12–15, 30–31 and 36–40](../design.md#31-acceptance-criteria-for-the-design-implementation).
The design remains **Proposed design**. Phase 4 support/clarification,
publication/evaluation and live-run approval remain separate from open Phase 3 work.
