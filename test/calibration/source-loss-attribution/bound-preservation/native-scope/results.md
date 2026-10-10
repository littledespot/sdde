# Native assessment scope results — 11 October 2026

**The redundant member-selection rejection is resolved in this panel, and the
unchanged diagnostic gates pass.** All 72 approved calls completed. Native
admission and correct admitted attribution improved from **22/24 to 24/24**.
Preservation judgments were already correct in both arms: **24/24 each**. This
demonstrates improved admission of correct judgments, rather than better judgment
accuracy. One candidate response still lacks a required source citation.

## Execution and controls

- Frozen [manifest](comparison.json), [criteria](README.md) and complete
  [scorecard](scorecard.json).
- Execution: 11 October 2026, 07:42:55–07:44:47 AEDT
  (`2026-10-10T20:42:55Z`–`20:44:47Z`).
- [Execution journal](../../../../../zig-out/source-loss-native-scope-comparison/2026-10-10T20-42-55Z/results/execution.json).
  The artifact directory retains actual provider requests, raw responses, parsed
  answers, complete native assignments, per-call origins, native reports,
  independent reviews, the scoring script and frozen prior native source.
- Twelve known cases, two repetitions, 18 complete isolated collections per arm
  per repetition: **36 baseline + 36 candidate calls**, yielding **24 complete
  case/repetition decisions per arm**.
- Identical paired business inputs and settings: AWS Bedrock
  `openai.gpt-oss-20b-1:0`, `ap-southeast-2`, low reasoning, temperature 0, native
  schema and 16,384 output allowance. The shared response contract and its prompt
  are the changed factor; both arms use isolated comparisons.
- Actual provider request bytes matched all frozen projections. Every call ended
  with provider `stop`, valid JSON and a valid response schema. No truncation,
  retry, correction, repair, model judge or whole-workflow E2E invocation occurred.
- Baseline answers passed through the unchanged native owner from revision
  `6830129f6ce41baa1cd9982e77aa208345b2a8b1`. Candidate answers passed through the
  current owner. No answer was amended, supplied with missing IDs, or decoded by
  the other arm's contract. The **72-call allowance is consumed**.
- Credential and debugger-session-token scans found no retained matches.

## Results

| Measure | Returned-member baseline | Native-scope candidate |
| --- | ---: | ---: |
| Physical calls | 36 | 36 |
| Complete, JSON/schema-valid decisions | 24/24 | 24/24 |
| Correct preservation judgments | 24/24 | 24/24 |
| Native admission | 22/24 | 24/24 |
| Correct admitted attribution | 22/24 | 24/24 |
| Adequate contract-grounded assembled evidence | 22/24 | 23/24 |
| Adequate explanations and original-source citations | 24/24 | 23/24 |
| Adequate explanations/citations per physical response | 36/36 | 35/36 |
| False upstream / candidate attribution | 0 / 0 | 0 / 0 |
| Actual input tokens | 47,236 | 45,652 |
| Actual output tokens | 7,511 | 6,354 |
| Total tokens | 54,747 | 52,006 |
| Median serial round trip per complete decision | 1,822 ms | 1,673.5 ms |

Total usage was **106,753 tokens**. Candidate usage was **5.0% lower** with the
same number of calls. Round trips include debugger/transport overhead; provider
latency was unavailable. These figures do not establish dollar cost.

### The original rejection reproduced in the concurrent baseline

| Baseline decision | Defective response | Observed result |
| --- | --- | --- |
| `extraction-inherited-baseline-1` | Comparison 1 | Correctly identifies missing pump shutdown/until-recovery behavior, cites its source and explains the display/record collection, but returns `members: []`. |
| `unresolved-multiple-producers-baseline-2` | Comparison 1 | Correctly identifies missing eight-hour backup cooling and failure alarm, cites both sources and explains the temperature collection, but returns `members: []`. |

Both nonempty collections reject as `InvalidPreservationComparison` under the
unchanged old owner. Both candidate repetitions for those cases contain correct
judgments and pass native admission without a redundant member selection. Native
scope, freshness, completeness and repair boundaries remain checked; no old
rejected answer was repaired by the harness.

The previous isolation scorecard counted invalid required member selections as
inadequate contract-grounded evidence even when the prose and citations were
adequate. This report preserves that convention and additionally exposes
explanation/citation adequacy separately. The admission gain must not conceal a
decline in that separate semantic evidence measure.

### Remaining candidate defect: incomplete citations

`unresolved-multiple-producers-candidate-1-2` correctly returns `lost` and explains
that both eight-hour cooling and the backup-failure alarm are absent. It cites
only `chunk-1:1`, the cooling source, and omits `chunk-2:1`, the alarm source.
There is only one assigned comparison, so no sibling response supplies that
missing citation. Individual and assembled evidence adequacy both fail.

Native checks admit the authorized citation and derive the expected safe
`unlocalized` attribution. They do not prove that citations establish every
semantic premise. This is a real citation-quality regression against the paired
baseline, despite a correct judgment and improved admission. Do not label the
candidate as having no semantic regression.

Both captured-description and captured-story trials pass in both arms. The
sterile-door, voucher-release and distinct-source-occurrence cases all pass their
six candidate trials. Voucher answers cite both original premises individually;
the inherited assembled-evidence exception is not needed in this run.

## Gate decision and limits

The original eight-case subset now has **16/16** complete, schema-valid, natively
admitted correct candidate decisions, against **14/16** baseline. It meets all
inherited thresholds: zero false attributions; both extraction, signal, role and
safe-unresolved results; **8/8** candidate-defect results; no unnecessary
uncertainty; **15/16** adequate evidence; two additional correct admitted
attributions; and no case-level attribution-accuracy regression. Captured-story
passes **2/2** and the three previously fresh families pass **6/6**.

The inherited no-case-regression gate measures attribution/preservation accuracy,
with a separate evidence minimum. This is established by
[`no_case_accuracy_regression` in the earlier manifest](../meaning/comparison.json)
and the [obligation scorecard](../obligation/scorecard.json), whose gate passed
despite the separately reported extraction citation defect in
[its results](../obligation/results.md). No gate was expanded, lowered or changed
after seeing these answers. The citation regression above remains visible.

The panel qualifies the native-scope response change on these known isolated
inputs. It does not establish statistical reliability, behavior across models,
or performance of the production batched loss request. Production still performs
its complete loss review in one call; this result does not itself implement or
qualify a production orchestration split.

The next qualification boundary is actual source-review output: admit the
reviewer's own `missing_obligation` unchanged, bind its real request/call origin,
and assess faithful conditions, negation and obligation strength with supported
and genuine-gap controls. Fixed oracle obligations do not test that handoff.
That separately frozen live panel needs its own bounded approval. Useful repair,
actual publication and rubric quality remain unmet E2E acceptance criteria; no
E2E run was part of this allowance.

## Verification and assessment

- Current `zig build test-specification-generation --summary all -j2`:
  **292/292** passed while admitting these fresh candidate receipts.
- Frozen prior owner, the same build step: **290/290** passed while admitting
  these fresh baseline answers.
- Pre-dispatch `zig build verify --summary all -j2`: **1,463/1,463 tests**,
  **142/142 steps**, including integration and clean packaging smoke checks.
- Frozen hashes and actual request byte comparisons passed; text changes checked
  with `git diff --check`.

Assessment was manual and unblinded. Separate reviewers covered every response;
the primary reviewer checked the exceptions and an independent reviewer checked
the inherited gate interpretation. Two repetitions of twelve known cases are
regression evidence, not independent population samples or semantic proof.
