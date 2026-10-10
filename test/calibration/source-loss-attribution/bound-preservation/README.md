# Bound preservation comparison — FIX01-01 Phase 3

Status: **32/32 approved calls executed; semantic acceptance failed.**
Phase 3 remains open. See the results below; the frozen requests, expected labels
and gate are unchanged. No Phase 4 E2E invocation ran.

This compares the preceding culprit-selection contract against Phase 2's native-bound
preservation contract as a bundle. It uses the existing modified-request debugger
replay, one model configuration, and no production shadow path or model judge.
The baseline prompt/schema are pinned to commit
`79b4ddc2d0970ea6215b65a567c7067bfc6efd43`. These are diagnostic historical
artifacts, not compatibility readers. Existing historical requests/results are unchanged.

## Cases and premises

| Case | Cohort | Fixed defect and expected result |
| --- | --- | --- |
| captured-description | Development | Reconstructed captured greeting/UTC claims and malformed JSON-looking description; complete authoring claims → candidate defect. |
| loan-candidate | Development | Eligibility/no-reservation survive upstream but are missing from description → candidate. |
| extraction-inherited | Development | Pump shutdown/duration absent from extraction and later assigned subset → extraction, not role selection or authoring. |
| fan-direct-signal | Development | Original fan claim includes operator confirmation; the reviewed **signal** omits it → signal. This is not a claim that authoring consumed signal prose. |
| joint-two-sources | Previously unused | Identity verification and payment confirmation jointly support parcel release; both missing from description → candidate. |
| wrong-role-assignment | Previously unused | Cancellation notification survives extraction but the description role receives only opening-hours claims → unsupported role, no existing upstream repair authorization. |
| unresolved-multiple-producers | Previously unused | Two obligations lost across separately owned sources → unresolved owner; neither arbitrary extraction target nor candidate is justified. |
| parking-candidate | Previously unused | Settlement condition and failed-payment behavior survive upstream → candidate. |

“Previously unused” means no previous live trial or prompt tuning on those inputs,
not a blinded external test set. Labels are review judgments, not engine semantic
proof. The captured case reconstructs source/claim/literal/deficient-description
facts through current native owners, with a brief-only subject. It is not an exact
replay of all historical canonical state or surrounding authored records.

`cases.json` supplies controlled producer responses. The existing native extraction,
reconciliation, authority, request, schema projection and comparison admission
owners build and check every case in
`src/test_fixtures/source_loss_calibration.zig`. `*.packet.json` freezes the resulting
native facts and model projection. No expected owner/verdict is included in either
model request. Following the projection revision, offline tests require the native
assignment and schema to remain identical and reproduce the frozen provider bodies
byte-for-byte. The [new presentation](projection/README.md) has separate current-packet checks;
it does not overwrite this historical model projection.

Both arms share original sources, extracted meaning, fixed finding and reviewed
subject. Candidate bindings and explicit comparisons are the experimental change.
The baseline reconstructs the preceding packet presentation and offers its old
response vocabulary. It cannot name a role owner: `unlocalized` is safe for the
wrong-role case, but does not identify that defect. Score safety and detection
separately. Baseline native admission is **not executed**: do not restore a legacy
production reader. Assess its schema, offered locations/source spans and semantic
assertions separately; label this limitation in the results.

## Frozen execution plan and gate

`comparison.json` records full replay edits, schema/packet/source hashes, settings,
trial order and the gate. `*.request.json` contains the complete provider body
from the existing Bedrock request encoder; offline tests reproduce it byte-for-byte. Each of eight cases runs baseline/candidate twice:
**32 physical sends maximum**. Repetition 2 reverses the arm order. Use Bedrock
`openai.gpt-oss-20b-1:0`, low reasoning, temperature 0, native schema and the parent's
16,384 output allowance in `ap-southeast-2`. No retries, corrections, repairs,
automatic judges, additional calls or E2E runs are authorized by this plan.

Before dispatch verify the manifest hashes, parent settings and complete effective
requests. Preserve the actual serialized provider request/response from each replay;
report their bytes, actual token usage, provider stop reason and latency separately
from HTTP roundtrip latency. If bootstrap, transport or request identity is uncertain,
stop instead of repeating a send. Every dispatched failure consumes a trial.

The candidate must satisfy **all** of these gates, with all 16 candidate trials in
the denominator:

- At least 15 completed, schema-valid, natively admitted responses.
- Zero false upstream and zero false candidate attributions.
- Correct extraction, direct-signal and role diagnosis on both repetitions each.
- Safe unresolved ownership on both multi-producer repetitions.
- At least 7/8 correct candidate-defect diagnoses; at most one unnecessary uncertain
  diagnosis outside the multi-producer case.
- Adequate evidence for at least 14/16 responses: valid source/member references,
  explanations comparing the complete assigned meaning, no invented obligations
  or unsupported allegations. Token/ID attachment alone is insufficient.
- At least two more correct attributions than baseline, with no case-level accuracy
  regression. Report development/unused results separately.

Score comparison verdict correctness as well as final native owner. A correct owner
obtained from false claims is not semantic success. Separately record false upstream,
false candidate, missed genuine loss, unnecessary uncertainty, evidence adequacy,
unsupported allegations, truncation, schema/native rejection, tokens and latency in
`scorecard.template.json`. Always-uncertain cannot pass. Any failed/inconclusive gate
leaves Phase 3 open. No prompt tuning or relabeling after seeing trial results;
revisions require a new frozen plan and new bounded approval.

## Execution and native readback

1. Run `zig build test-specification-generation --summary all` to reconstruct and
   verify native assignments and frozen provider bodies. This is offline evidence,
   not semantic performance.
2. Obtain fresh explicit approval for these 32 sends under
   [§28.8](../../../../design/contracts/28-testing.md#288-model-protocol-correction-and-semantic-calibration).
3. Follow the existing [debugger replay procedure](../README.md#bounded-replay-procedure)
   in an isolated copy of the recorded parent project. Resolve the exact recorded
   run/call ID from the manifest, not the API array index or latest replay.
   Use each frozen `*.edit.json` in its assigned `POST /api/replay` exactly once.
   Do not import any replay result into a workflow.
4. Store each candidate's adapter-normalized, schema-checked model JSON as
   `.zig-cache/source-loss-preservation/<case>.response-<1|2>.json` (including invalid
   candidates where JSON exists). Preserve the original raw response separately.
   Rerun the same offline build step. Its diagnostic readback reconstructs current
   native facts, proves equality with the frozen assignment, and calls production
   `Source.admitComparisons`. `*.native-<1|2>.json` records acceptance/attribution or
   rejection. No file means **not assessed**, never an accepted trial.
5. Retain those native reports beside the live evidence and complete manual semantic
   scoring against the fixed source facts. Native acceptance establishes joins and
   ownership derivation, not semantic truth. Do not claim repair/publication quality.

This bounded pilot cannot establish reliability across models, production recovery,
E2E publication or rubric quality. Those remain separate acceptance work.

## Preparation evidence

- `zig build test-specification-generation --summary all`: 288/288 passed,
  including construction of all eight cases, schema compilation, native expected
  derivation and missing-comparison rejection.
- `zig build verify --summary all`: final verification passed 142/142 steps and
  1,455/1,455 tests, including byte-for-byte provider-body checks, architecture,
  lint, separate integration tests and packaged-executable smoke checks.
- `zig build --summary all`: 4/4 build/install steps passed.
- Debugger preflight in an isolated copy verified original parent identity and
  low-reasoning/temperature/output-limit settings; **zero physical model sends**.
  Record: `/private/tmp/sdde-source-loss-attribution-ipknvg6x/results/execution.json`.
- `git diff --check` and Zig formatting checks passed.

No live quality score is available. Neither preparation nor the fixed offline
verdicts are evidence that semantic attribution improved.

## Results — 10 October 2026

**Executed; semantic gate failed.** The user approved all 32 calls and explicitly
approved sending the frozen synthetic evidence, project guidance and schemas to
AWS Bedrock after automatic approval review initially blocked launch. Exactly 32
calls then ran, with no retries, repairs, judges or E2E runs. The debugger stopped;
the retained artifact scan found no credential or session-token matches.

[Artifacts](../../../../zig-out/source-loss-preservation-comparison/2026-10-10T07-12-43Z-r9gpx8hq/),
[execution record](../../../../zig-out/source-loss-preservation-comparison/2026-10-10T07-12-43Z-r9gpx8hq/results/execution.json) and
[per-trial scorecard](../../../../zig-out/source-loss-preservation-comparison/2026-10-10T07-12-43Z-r9gpx8hq/results/scorecard.json)
retain frozen requests, actual responses, explanations and native admission reports.
The original parent, model/settings and provider-request bodies matched the frozen
plan. All provider finish reasons were `stop`.

All 32 responses passed JSON/schema admission, after the existing prefix
normalization in 30 cases. This did **not** establish native or semantic validity.
Production `Source.admitComparisons` accepted **7/16 candidate responses** and
rejected nine: seven used nonexistent source-line IDs and two used an ineligible
comparison-member ID. The offline readback command
`zig build test-specification-generation --summary all` passed 288/288 tests; its
native reports retain these rejections as diagnostic outcomes, not passing trials.

| Case | Baseline, repetitions 1 / 2 | Candidate, repetitions 1 / 2 |
| --- | --- | --- |
| Captured description | Wrong extraction / wrong extraction | Unresolved / unresolved; both upstream collections wrongly assessed lost |
| Loan candidate | Wrong extraction / wrong extraction | Rejected / rejected: correct preservation judgment, nonexistent line 2 |
| Inherited extraction loss | Unlocalized / unlocalized | Rejected / rejected: correct lost judgments, member 2 selected where only local member 1 exists |
| Direct signal loss | Wrong extraction / wrong extraction | Rejected: nonexistent line 2 / admitted wrong extraction; both judge the deficient signal instead of its complete upstream claim |
| Joint source support | Wrong extraction / wrong extraction | Unresolved / unresolved; complete upstream collection wrongly assessed lost |
| Wrong role assignment | Safe unlocalized, no role diagnosis / wrong extraction | Rejected / rejected: correct preserved/lost judgments, nonexistent line 3 |
| Multiple independent producers | Correct unresolved / correct unresolved | Correct unresolved / correct unresolved |
| Parking candidate | Wrong extraction / wrong extraction | Rejected / rejected: correct preservation judgment, nonexistent line 2 |

The candidate supplied correct comparison-verdict sets in **10/16** trials, but
only **2/16** yielded the correct admitted attribution; both were the deliberately
unresolved multi-producer case. Baseline also selected the expected location in
2/16. Development cases scored 0/8 in both arms; previously unused cases scored
2/8 in both. Baseline cannot name role ownership, and its native admission remains
unassessed; its safe unlocalized role answer is reported separately from diagnosis.

One admitted candidate response wrongly blamed extraction for the fan signal loss.
There were no false candidate attributions. Four admitted candidate responses
were unnecessarily unresolved. Only 2/16 combined adequate semantic explanation
with valid source/member evidence. No candidate-defect case achieved an admitted
candidate diagnosis (0/8); neither repetition of genuine extraction, signal or role
loss achieved the required admitted diagnosis. Every predeclared gate failed except
safe unresolved ownership for both multi-producer repetitions.

Baseline chose a wrong upstream location in 11/16 responses, eight of which also
had invalid source spans. Candidate native admission blocked nine responses and
left four wrong judgments unresolved. Comparing 11 baseline selections with one
admitted candidate false upstream result does **not** prove semantic improvement
or successful repair: the boundaries differ, and the candidate still misses the
required diagnoses. No rebuild or repair actually executed in this experiment.

| Arm | Actual input tokens | Actual output tokens | Total | Debugger round-trip time |
| --- | ---: | ---: | ---: | ---: |
| Baseline | 26,716 | 2,592 | 29,308 | 16,755 ms |
| Candidate | 28,720 | 3,645 | 32,365 | 20,840 ms |
| Combined | 55,436 | 6,237 | 61,673 | 37,595 ms |

Candidate total tokens increased about 10.4%. Provider latency and monetary cost
are unavailable; debugger round trips include local replay/logging overhead.
Assessment is manual and coding-agent-assisted, non-blinded, against the frozen
source facts. Native admission proves mechanical joins and permitted derivation,
not semantic truth. No semantic criterion or expected label was changed after
execution. The frozen manifest and scorecard template remain unchanged; actual
results live in the separate scorecard.

### Findings for a separately frozen revision

1. **Assessed-view confusion remains.** Captured, fan and joint-source responses
   explicitly refer to complete upstream evidence, then label it lost because the
   deficient final subject lacks the meaning. Existing instructions already say not
   to reassess that subject. Repeating the instruction alone is not a demonstrated
   remedy. `packetForLoss` supplies the final subject prominently and gives upstream
   collections the same final-field purpose; those roles need clearer separation.
2. **Selectable identifiers compete with canonical identifiers.** In extraction
   comparison 2, member `id: 1` wraps `requirement.claim_id: 2`; both answers select
   member 2. Keep native occurrence binding, but expose one unambiguous selectable
   member ID in the model-facing assessed collection.
3. **Two source-coordinate conventions remain visible.** The selectable catalogue
   uses inclusive line IDs, while supporting producer/citation locations include
   end coordinates on the next line. Seven candidate responses cite nonexistent
   catalogue lines. Their chosen endpoints often match these raw locations; that
   is a plausible confusion source, not proof of the model's internal cause.
   Preserve canonical provenance internally and project source references through
   one selectable convention for this shared request.

The next candidate should revise the shared loss-request projection, retaining
complete assigned meaning, source occurrences and necessary producer evidence while
removing competing bookkeeping from model-facing selections. Native assignment,
closed response validation, attribution, repair permissions and generic runner
semantics should stay unchanged. Test production/correction/repair/readback and
unrelated inputs, then freeze a **new** comparison; do not mutate this failed pair
or silently normalize wrong IDs. No new revision or model calls are authorized by
this result record itself.

Phase 3 remains unaccepted. The three approved Phase 4 E2E runs were conditional
on Phase 3 passing and therefore were **not executed**. Their allowance is unused;
publication, recovered success, recurrence and repair-induced harm remain unmeasured.
