# FIX04 Phase 2 review and repair cost investigation — 16 October 2026

The user selected **investigate review/repair cost within current budgets** after
the approved diagnostic exhausted the 100,000-token workflow budget. This
investigation reads that retained capture; it performs no additional model calls,
changes no budget or production contract, and does not close Phase 2's live exit
gate. The applicable boundaries are design §§3–4, 17, 21–22 and FIX04 §5.5:
semantic judgments remain model-assisted, complete review and publication gates
remain required, and actual failures stay in the resource denominator.

## Measured cost

The [native report](../zig-out/e2e-spec/2026-10-15T22-18-35Z-a8740d575019326cb5b63f994c3dc426/report.json)
and [per-call analysis](../zig-out/phase2-review-cost-analysis-2026-10-16.json)
account for every physical send and cross-check all 41 native usage records
against the original provider responses.

| Stage | Sends | Input tokens | Output tokens | Actual total | Share |
| --- | ---: | ---: | ---: | ---: | ---: |
| Extraction and reconciliation | 6 | 7,250 | 637 | 7,887 | 7.80% |
| Specification generation | 5 | 10,227 | 704 | 10,931 | 10.81% |
| Review, including protocol correction | 29 | 72,489 | 5,444 | 77,933 | 77.06% |
| Semantic repair | 1 | 4,322 | 61 | 4,383 | 4.33% |
| **Total** | **41** | **94,288** | **6,846** | **101,134** | **100%** |

Stage attribution reconstructs captured native result-definition selections,
composition contracts and exact call lineage. Direct purpose/owner receipts were
absent in this historical E2E capture; the analysis is diagnostic attribution,
not new engine authority. No call is unclassified and no usage is unknown.

Review comprises 21 singleton `finding` sends costing 55,356 tokens, four
`record_findings` sends costing 13,298 tokens, and four
`preservation_comparisons` sends costing 9,279 tokens. Counts include repeated
assignments and the correction; they are not distinct semantic-subject counts.
The 478 `report.corrections` records are native observations, not 478 paid calls.

Call 23 is the only protocol retry: request 22, attempt 2, costing 3,533 tokens.
It is already included in review. Removing only this retry would leave 97,601
tokens at the same unfinished workflow position, with required work outstanding;
that is not evidence that the workflow could complete within budget.
Input tokens account for 93.23% of total usage. The capture does not provide
provider token counts for individual prompt/schema/evidence components, so byte
sizes must not be reported as measured component token savings.

## Findings and owning contracts

**A source-review judgment confused field instructions with original source
obligations.** Call 15 correctly notices the defective story
`Hello, World!Hello, World!`, but its `missing_obligation` copies the engine's
instruction to write a narrative. The original source states startup, greeting
and UTC-output behavior; it does not demand a prewritten story. Call 16 then
reports that the extracted claims lost that narrative instruction, even though
the compared collection contains all three source behaviors. This is a
source-backed, model-assisted assessment of the captured outputs, not
deterministic semantic proof or human adjudication.

The owning boundary is the source-review assignment and omission statement in
[`specification_support.zig`](../src/domain/specification_support.zig), its
[`support.prompt.md`](../design/workflows/spec/support.prompt.md), and
[§§17.3/22.1](../design/contracts/22-repair.md). Native membership validation
cannot prove that the statement is faithful to its source. A universal rewrite
from `candidate_omission` to `candidate_invalid` would be wrong: the duplicated
literal really omits behavior, and call 37 later states concrete missing source
behavior. No admitted verdict was changed during this investigation.

**The semantic repair made no progress.** Call 8 generates the story using two
`exact_copy` fragments and no narrative. Call 36 returns the same two fragments.
The native merge records `changed: false`, revision 6 → 7. The repair costs 4,383
tokens; the five observed subsequent review calls cost another 13,933. Their
combined 18,316 tokens are observed cost, not a claim that all revalidation could
be removed. The story is still defective and no specification was published.

The owning boundaries are
[`specification_coverage_repair.zig`](../src/domain/specification_coverage_repair.zig),
[`atomic_repair.zig`](../src/domain/atomic_repair.zig), and the shared retry and
dependent-validation contracts. A no-progress outcome could save failure cost
only through an explicit shared contract; treating an unchanged defective value
as repaired or skipping required validation would violate the existing design.

**Review retention already works and has deliberate exclusions.** After repair,
the paid calls reassess the negative story finding, its loss comparison, the
negative scenario-coverage finding, its loss comparison, and the previously
protocol-corrected second AC assignment. Clean eligible assignments are reused.
[§22.4](../design/contracts/22-repair.md) explicitly excludes omissions and their
revision-bound preservation comparisons from reuse, and conservatively reassesses
protocol-corrected assignments without an additional complete dependency witness.
Adding another cache or accepting equal text alone is not the fix.
The full provider request bytes are identical for calls 15/37 (story), 19/39
(scenario coverage), and 22/41 (second AC). Their repetition follows those
exclusions; it does not establish that their required judgments can be skipped.

## Next implementation work and evidence needed

1. Qualify the source-review omission contract against original sources, field
   purposes and loss localization. Use the captured false narrative obligation
   and unrelated examples; preserve real missing-behavior findings and all native
   evidence checks. Do not introduce semantic verdict retries without authority.
2. Investigate the model-facing repair projection at the existing rule/packet
   owners. The current omission repair sends both generation context and the
   native preservation evidence structure. Call 36's user payload is 14,705
   bytes: its repair rule is 10,668 bytes, including 9,876 bytes of native
   preservation proof (67.2% of the payload); the candidate adds 2,808 bytes.
   `Rule.guidance()` currently returns the full `ReviewEvidence`, which the
   shared atomic packet serializes. These are measured UTF-8 byte sizes, not
   independently measured token costs or guaranteed savings. Any smaller typed projection must
   retain the authorized old value, target, actual source meaning and internal
   dependency proof. Prove its coverage offline before claiming token savings.
3. If call reduction is still required, propose a bounded review-assignment
   batching amendment with exact per-subject findings, origins, rejection,
   correction and repair tests. The current accepted batch is Given/When/Then;
   broader batching needs an explicit contract decision and semantic comparison.
   It must preserve all independent support and collection judgments.

These are production-owner follow-up work, not missing acquisition/scorer
implementation. No production optimization is implemented or claimed by this
read-only investigation.

The experiment-wide feasibility problem remains separate from one workflow's
100,000-token stop. The declared 360–504-workload scope allows only about
5,556–3,968 tokens and 2.78–1.98 sends per workload on average under the current
2,000,000-token/1,000-send stops. In this one diagnostic, extraction plus
generation alone used 18,818 tokens and 11 sends. Applying that observed initial
cost to the whole scope would already exceed both stops before review; this is
an explicit planning comparison, not a measured cost estimate for unseen cases
or changed candidate architectures. The
[feasibility report](../zig-out/baseline/2026-10-15T22-38-08Z-4ae44015f25ecde96580bc1c4c065da1/budget-feasibility.json)
therefore remains insufficient. Review-cost work cannot itself authorize a
freeze, a smaller panel, larger limits, or another live run.

The implementation checks recorded in the [Phase 2 audit](FIX04-phase2-audit.md)
remain the latest code validation: 535/535 targeted tests and 1,659/1,659 complete
verification tests passed. This investigation changed only tracking documents
and wrote ignored diagnostic artifacts; text whitespace checks passed.
