# Native assessment scope

**Executed diagnostic comparison — 11 October 2026.** All 72 approved sends
completed; the allowance is consumed. [Results](results.md) and
[scorecard](scorecard.json) record admission/attribution improving **22/24 → 24/24**
and the unchanged diagnostic gates passing. Both arms already had correct
judgments on **24/24** decisions; one candidate answer still omits a source
citation. Production performs its complete loss review in one call; diagnostic
isolation is not a production split or a fallback.

The [completed isolation comparison](../isolation/results.md) returned correct
preservation labels on 24/24 assembled candidate trials, but two empty returned
member selections failed the old native response contract. This experiment tests
whether making the assessed collection native-owned removes that reporting defect
without harming meaning or attribution. Exact internal reasons for the empty
selections remain unknown.

## Frozen inputs and one changed contract

Reuse the twelve [canonical obligation cases](../obligation/cases.json), original
comparison IDs, complete member collections and two repetitions. Baseline edit
and provider request files are byte-for-byte copies of the preceding isolation
candidate requests. The new candidate is generated from the current shared
packet/schema/prompt owners. Both arms receive the same isolated business-input
bytes: explicit obligation, original sources, one complete assigned comparison,
and all supporting producer/candidate context.

The intended changes are the closed response contract and its shared prompt:
`comparison_id` binds the whole collection; the model returns its verdict,
original-source citations and explanation, without selecting `members`. The
engine retains the full native assignment. Old responses are not amended or
readmitted under the new policy. Missing/duplicate comparisons, foreign sources,
stale assignments and unauthorized repair remain rejected.

Both arms use AWS Bedrock `openai.gpt-oss-20b-1:0` in `ap-southeast-2`, low reasoning,
temperature 0, native schema and 16,384 output tokens. No seed or top-p is supplied.
Use the existing authenticated request-debugger replay and verify actual provider
requests against the frozen bodies. The [manifest](comparison.json) pins these
requests, evidence, settings, order, expected responses and acceptance criteria.
It does not authorize dispatch.

| Arm | Comparisons per repetition | Repetitions | Physical sends | Assembled decisions |
| --- | ---: | ---: | ---: | ---: |
| Baseline: frozen returned-member contract | 18 | 2 | 36 | 24 |
| Candidate: native-owned complete collection | 18 | 2 | 36 | 24 |
| Total | 36 | 2 | 72 | 48 |

Stop after 72 physical sends, unknown usage, uncertain dispatch/transport outcome,
hash or request drift, or 300,000 accounted input-plus-output tokens. Check actual
usage after each completed exchange; an in-flight completion may cross the stop.
There are no retries, corrections, repairs, model judges or whole-workflow E2E
runs in this comparison. Restarting does not renew the allowance.

## Admission and assessment

Keep every physical response and origin. Candidate receipts bind each child to
its original comparison, case/repetition and frozen request hash. Aggregate only
a complete set, then use current native full-assignment admission and attribution.
No verdict, citation or member is filled by the harness. Historical baseline
native acceptance uses the unchanged owner from source revision
`6830129f6ce41baa1cd9982e77aa208345b2a8b1`, run in a separate temporary source
snapshot through `build.zig`; the manifest pins its source archive. Old payloads
never pass the current codec or a compatibility reader. Retain planned,
dispatched and completed denominators and every rejection.

The frozen owner has been checked offline with
`zig build test-specification-generation --summary all -j2` in the extracted
source snapshot: 290/290 tests passed and all twelve original/current native
assignments matched. Passing the unchanged historical isolation responses through
that owner reproduced its 22/24 admissions and both original rejections. The
baseline [receipt](../../../../../zig-out/source-loss-native-scope-baseline/offline-receipts.json)
records this check. It validates the concurrent comparison mechanism; it does
not turn old outputs into new evidence or authorize more live calls.

Measure completion/schema validity, verdict accuracy, explanation/source-evidence
adequacy, native admission and correct admitted attribution independently. Report
per-physical-call and per-assembled-decision token cost and latency. The unchanged
gates from the preceding isolation manifest apply to complete decisions, including
zero false upstream/candidate attribution, original-eight minima and improvement
over concurrent baseline, both captured-story trials and all six previously fresh
regression trials. The latter are now known regressions, not unseen qualification.
Keep the existing assembled-evidence scoring rule; report individual child
adequacy separately. Do not lower a gate if the baseline becomes too good to
demonstrate the required improvement. Manual assessment is unblinded and is not
deterministic semantic proof.

## Actual source-review handoff

Offline preparation also exports fourteen source-review requests: the twelve
regression cases and [two controls](handoff.controls.json) for supported behavior
and a genuinely unselected release policy. Received review values
go through current source-review admission before any loss packet is constructed;
the admitted `missing_obligation` is retained unchanged. A model's supported or
genuine-gap result does not manufacture a loss assignment. These requests are
separate from the 72 fixed-omission sends and need their own frozen live panel and
bounded approval. They must measure faithful conditions, negation, obligation
strength and omissions, supported controls and genuine missing user choices.
Fixed oracle obligations in this comparison do not establish handoff reliability.
The [handoff preparation](handoff.preparation.json) proposes two review repetitions
(28 review calls); any subsequent loss-stage requests and counts must be derived
from actual admitted omissions and separately frozen before dispatch.
Current handoff probes are offline and carry no live review origin. Before that
panel launches, bind each actual review output to its trial, request hash and call
origin, and retain decoding/admission rejections in its denominator. Do not treat
the prepared probes as live handoff evidence.

Publication, recovery and rubric quality require subsequent E2E qualification.
This comparison cannot mark those criteria complete.

## Offline verification — 11 October 2026

- Specification generation: **292/292**.
- Model payload, candidate codec, request workflow and architecture: **613/613**.
- `zig build verify --summary all -j2`: **1,463/1,463 tests**, **142/142 steps**,
  including integration and clean packaged-executable smoke checks.
- Frozen prior owner: **290/290**, exact historical admission reproduction above.
- All **106 manifest pins**, identical paired business inputs, unchanged settings
  and gates verified. `git diff --check` passed.

Those offline checks preceded dispatch. The subsequent [execution results](results.md)
retain all 72 fresh live answers and both native admission checks. Actual
source-review handoff and E2E qualification remain separate.
