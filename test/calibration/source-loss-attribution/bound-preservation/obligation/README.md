# Explicit obligation qualification — FIX01-02 Phase 3

The user approved this 48-call comparison on 10 October 2026. Twelve cases ×
baseline/candidate × two repetitions; no retries, corrections, repairs, model
judges or whole-workflow E2E invocations. The preceding context-removal candidate
failed and is not used here.

The candidate supplies an explicit source-grounded `missing_obligation` as the
loss comparison target. Diagnostic detail and field purpose remain supporting
evidence. The baseline reconstructs the preceding production presentation from
the same native evidence, with its original prompt. Both retain the full
candidate context and identical comparison collections and response schema.
This comparison measures the combined contract/guidance change; it does not
isolate each wording change.

`cases.json` owns synthetic sources and labels. The existing
`src/test_fixtures/source_loss_calibration.zig` prepares both requests through
production packet construction, schema projection and Bedrock encoding; it admits
responses through production comparison validation and attribution. Frozen
request copies are checked against regeneration by
`zig build test-specification-generation`. Do not edit generated requests.

`comparison.json` freezes hashes, controls, counterbalanced trial order, response
paths, actual-usage stop and acceptance criteria before dispatch. The existing
authenticated request-debugger replay executes each prepared edit using the
retained call named by that manifest. Actual requests must equal the frozen
provider request. An uncertain dispatch consumes its allowance and stops the
campaign without resending. No secret or debugger session token belongs in
retained artifacts.

Settings: Bedrock `openai.gpt-oss-20b-1:0`, `ap-southeast-2`, low reasoning,
temperature 0, native schema, 16,384 output allowance; no seed or top-p supplied.
Stop after 48 sends or 300,000 accounted input-plus-output tokens. The latter is
an experiment spending stop, checked after completion, not a runtime token
reservation. Transport uncertainty, unknown usage or hash drift also stop sending.

The original eight cases cover candidate, extraction, signal and role loss,
joint source support, and genuinely unresolved ownership. The latest captured
story is retained. Three new families cover a negative safety obligation,
joint prerequisites and equal literal bytes from distinct source occurrences.
A separate reviewer checked labels before dispatch. The loan label was corrected
before freezing to preserve a conditional duty rather than invent an only-if
prohibition; historical experiments are unchanged. These three new families
cease to be unused qualification data after this comparison.

Assess every planned trial in `scorecard.template.json`: completion, native
admission, each preservation verdict, evidence adequacy, derived ownership,
false attribution, uncertainty, tokens and latency. Manual assessment is
unblinded and uses no additional model. Keep disputed labels and failed trials
visible; do not change expectations to make results pass. An evidence statement
must identify the source-supported obligation and explain presence or absence
in the complete assigned collection. A member's omission alone is insufficient
when another member or their combination preserves the meaning.

The original eight-case candidate gate remains: at least 15/16 complete and
admitted; zero false upstream/candidate attributions; both correct extraction,
signal, role and unresolved results; at least 7/8 correct candidate-loss results;
at most one unnecessary uncertainty; adequate evidence on at least 14/16;
at least two more correct attributions than baseline and no case-level regression.
Both captured-story trials and all six fresh-case trials must also complete,
pass admission, have adequate evidence and match the predeclared correct result.
High baseline scores can make superiority inconclusive; no threshold is lowered.

## Source-review boundary

Each case also has a frozen `review.edit.json` and `review.request.json` for the
new source-review contract. Offline tests feed a real decoded review through
`Source.collectFocused`, then build the loss request from its admitted obligation.
Optional captured live responses use
`.zig-cache/source-loss-obligation/<case>.review.response-<repeat>.json`;
the same preparation test produces `review.native-<repeat>.json` and, only for
an admitted omission, `handoff-<repeat>.edit.json` and its provider request.
The cohort's expected obligation never replaces the reviewer's answer.

The approved 48 calls assess loss judgment with a fixed admitted omission. They
do **not** establish live source-review fidelity or successful workflow recovery.
Additional source-review/handoff calls require a separately bounded allowance.
Score actual reviewed obligations for source fidelity, conditions, negation,
strength and omitted-meaning coverage before assessing their derived owner. A
faithful narrower obligation may have a different correct owner than the fixed
combined-obligation control; report completeness separately instead of imposing
an inapplicable oracle. No Phase 4 publication claim follows from diagnostic
admission alone.
