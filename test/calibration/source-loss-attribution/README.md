# Source-loss attribution comparison

**Completed; the candidate failed the declared quality gate.** All **16 approved
diagnostic calls** ran once under
[design §28.8](../../../design/contracts/28-testing.md#288-model-conformance-comparisons),
using the existing request debugger/replay service. Four cases have two arms and
two unchanged repetitions; the second repetition reverses arm order. There are
no corrections, retries, repairs, model judges or whole-workflow E2E runs.
Failed or empty answers consume their trial. Uncertain transport stops dispatch
without resending. The approved allowance is consumed; this retained procedure
does not authorize another run.

[comparison.json](comparison.json) retains the unchanged pre-run plan, parent,
model settings, source
evidence, proposed labels, file/schema hashes and trial order. Each edit uses the
existing closed `Edit` shape, `content` and `schema`.
[scorecard.template.json](scorecard.template.json) remains an unused-results template;
[scorecard.json](scorecard.json) records the completed assessment.
These files are diagnostic data, not another harness, validator or runtime
authority. The pre-run labels never entered a model request; the assessment method
and limits are recorded below.

| Case | Retained or controlled premise | Proposed attribution |
| --- | --- | --- |
| Captured description | Call 14 blames extraction although the exact greeting survives claims and both relevant signals; call 8 authored a literal JSON-like marker in the description. | Candidate |
| Downstream loan | Eligibility and no-reservation conditions survive extraction and reconciliation but disappear from the description. | Candidate |
| Source-only extraction | Pump shutdown and its duration occur on source line 1 but have no extracted claim; the surviving claim and signal concern a separate display obligation on line 2. | Extraction chunk |
| Reconciliation condition | The extraction claim retains operator confirmation before fan restart; the signal drops that condition. | Reconciliation signal |

All four cases are visible development cases, not a held-out reliability sample.
The unknown-ownership contract remains covered by native offline tests; this
bounded live comparison does not measure semantic reliability for genuinely
unknown ownership.

The baseline captured edit retains **exactly** call 14's content and selected
schema. Its model response compared the source with the defective candidate
while naming the extraction chunk; that is the failure to measure. The candidate
edit is **manually projected against the current production builders**, not
captured from a new production run. It resolves the full assembled business
subject, keeps the admitted `fixed_review.finding` unchanged, and retains each
actual producer output with its associated evidence. Its nullable `location` is
non-null only for a native-eligible repair target; supporting-only outputs retain
`location: null` and cannot be selected as a repair location.
Producer and claim meaning use the shared resolved-text projection; literal
values remain accompanied by their source/citation identities.
Its source, producer and candidate facts are inherited from the same capture.
The other three cases are explicitly constructed, brief-only feature-description
assignments; they make no claim about what upstream production would generate.

All controlled cases have one current, bound claim. In the source-only case
that claim supports only the separate display requirement. The missing pump
meaning has no extracted claim. The new `candidate` answer is mechanically
available for the feature description, but choosing it is semantically wrong in
that case. Claim presence never proves preservation of the omitted meaning.
Retained dispositions and preserved token classifications remain available as
supporting-only producer evidence. Their visibility grants no repair authority.
Reference-owned source/signal/token/conflict reviews cannot select `candidate`;
native regression tests cover that boundary separately.

The single comparison factor is the **attribution request contract as a bundle**:
dedicated packet, resolved subject, inline producer evidence, attribution guidance
and explicit `candidate` response. It does not isolate which part helps. The old
response uses `unlocalized` for both preserved upstream meaning and uncertainty;
the new response distinguishes those cases. Source evidence, the fixed omission,
producer state, candidate meaning, model and settings stay fixed within each
pair. Every actual producer output remains visible, including supporting-only
outputs; repair eligibility never filters evidence of preserved upstream meaning. The
localized source-line/comparison arm retains its existing eligible locations.

## Offline preparation and integrity

The files were checked for JSON parsing, exact captured-baseline equality,
paired fixed-review/source equality, inline producer/evidence association, valid
source coordinates, selected schema arms/ordinals, unchanged repeat reuse and
manifest hashes. These are fixture integrity checks, not native workflow admission
or semantic proof. Production builder/schema/repair tests remain their existing
owners. Recheck the recorded production-source hashes after the implementation
settles; any drift requires review and re-freezing before approval.

All trials use `request-14-inference-1` from
`RUN-ebb17bc64a64a01ef7d1134b87e37f35`, captured in
`zig-out/e2e-spec/2026-10-10T02-17-38Z-e9ca8a70c7f7cb4c45f002ba9ded8dee`.
Replay inherits Bedrock `openai.gpt-oss-20b-1:0`, `ap-southeast-2`, low reasoning,
temperature 0, output allowance 16,384 and native schema transport. A missing
capture, changed hash, unavailable model or changed setting requires
re-preparation; do not substitute another parent or silently change settings.

## Bounded replay procedure

This is the procedure used for the completed comparison. Its 16-call allowance
is consumed. A further dispatch requires a separately bounded approval.

1. Review the premises, labels and pinned hashes, then obtain explicit approval
   for the declared 16 physical calls. Prior diagnostic/E2E approval does not
   cover this plan.
2. Build with `zig build`. Copy the retained capture's complete `project`
   directory, including its configuration/provider assets and logs, into a fresh
   temporary diagnostic directory. Copy this comparison directory beside it.
   Preserve the original capture unchanged.
3. From the copied project, run the built executable with `--debugger hello-world`.
   Use only the dedicated test credential through the existing credential adapter;
   never print or retain it. Opening the debugger or reading its API sends no
   model request.
4. Read `/api/calls` with the session's `x-sdde-debugger-token` header. Locate the
   original parent by both manifest `parent.run` and `parent.call`. Its array index
   is the replay `call` value; call number 14 is not a stable API index. Always use
   this original parent rather than the preceding diagnostic trial.
5. After approval, submit exactly one manifest trial at a time to `/api/replay`
   with the required Origin/token headers and this shape:

   ```json
   {"call":0,"mode":"modified","edit":{"content":[],"schema":"..."}}
   ```

   Replace `0` with the resolved index and `edit` with the complete parsed file
   named by that trial. Both arms use the same one-send modified replay owner.
   Its existing selected-schema compiler supports the new response arm; no new
   response parser or provider transport is introduced.
6. Record the returned identity immediately. Preserve each serialized request,
   raw response and validation in `logs/debugger`, plus the frozen manifest,
   scorecard and retained failure evidence. Record complete provider-request
   bytes and the prompt/schema/evidence contributions separately; the manifest
   starts full provider bytes as unknown. Record actual provider usage and latency
   when available, never estimate them as actual tokens. Stop at 16 physical
   sends or earlier on a failed premise. Restarting does not renew the allowance.

## Assessment

Assess with arm names hidden where practical. Keep failed trials in each declared
denominator. The debugger reports provider extraction and JSON/schema admission;
it does **not** reconstruct the native workflow, authorize a repair or publish.
Keep `native_loss_admission` as `not_assessed` for these replays.

- Score the fixed missing meaning against source, extracted claims, signal and
  resolved candidate text. IDs, valid spans, fluent explanations and JSON/schema
  admission are not entailment evidence. Retain excerpts for every judgment.
- Score **wrong upstream localization** independently. For the two downstream
  cases, baseline `unlocalized` and candidate `candidate` are equivalent correct
  avoidance of upstream blame. Do not count the new tag alone as improved
  localization. Candidate `unlocalized` avoids blame but fails to establish the
  intended explicit downstream attribution; report that distinction separately.
- Score **unnecessary upstream rebuilding risk** from an incorrectly selected
  upstream location, separately from actual rebuilding. These isolated requests
  execute no rebuild and cannot measure regenerated siblings or their token cost.
- Score **candidate-local repair potential** as established, unestablished,
  incorrectly claimed or unassessable under the existing target/evidence rules.
  Baseline `unlocalized` does not distinguish preserved meaning from uncertainty.
  The new answer makes that distinction inspectable, but successful local repair
  and repair-induced harm remain `not_executed` in both arms.
  The captured description is bound to claims 1–3; adding exact-copy claim 4 is
  outside its current repair authority. Correct downstream attribution does not
  establish that an exact-reference repair can succeed under those restrictions.
- For genuine upstream loss, require the right eligible producer, valid cited
  source lines and a comparison describing missing meaning in that producer's
  output. An explanation of the candidate defect alone is insufficient. Preserve
  the source-only case despite its missing extracted claim.
- Report unknown ownership, unsupported evidence, false clarification gaps,
  attempts to reassess the fixed verdict, malformed output, stopping, usage and
  latency separately. No new vote, reconsideration or retry policy is authorized.

The proposed quality gate requires both candidate repetitions to avoid upstream
blame in the captured and unrelated downstream cases, correctly localize both
genuine upstream cases, and add no
unsupported comparison or false gap. At least one attribution dimension must
improve over its paired baseline; a tie, new tag alone, or unassessable result
establishes no semantic improvement. Two repetitions provide diagnostic evidence,
not a reliability estimate. Unknown-ownership semantic quality, candidate-local
repair success, repair-induced harm,
whole-workflow completion, publication and actual-output rubric quality remain
open and require separately approved production execution.

## Results — 10 October 2026

The [retained artifact directory](../../../zig-out/source-loss-attribution-comparison/2026-10-10T03-17-07Z-3200c9a3354527fb/)
contains the frozen inputs, copied project, all 16 native debugger request/response
pairs and per-trial raw provider requests, responses, validation and identities.
The [execution record](../../../zig-out/source-loss-attribution-comparison/2026-10-10T03-17-07Z-3200c9a3354527fb/results/execution.json)
confirms 16 sends in the original order, no retries/corrections/repairs/judges/E2E,
and no uncertain or unrun trial. The debugger was stopped. Credential and session
token scans found no matches in the retained artifacts.

All 16 responses passed the existing decoder and JSON/schema checks; 14 used the
existing `removed_leading_brace_quote` normalization. This is admission after
ordinary response handling, not 16 pristine raw JSON answers. Every provider
finish reason was `stop`. Actual usage was **25,112 input + 2,056 output = 27,168
tokens**. Provider latency was unavailable. Recorded debugger round trips totaled
14,765 ms and include replay/logging overhead; they are not provider latency.

| Case | Baseline, repetitions 1 / 2 | Candidate, repetitions 1 / 2 |
| --- | --- | --- |
| Captured description | Wrong extraction / wrong extraction | Wrong extraction / wrong extraction |
| Downstream loan | Wrong extraction / wrong extraction | Correct candidate / wrong extraction |
| Source-only extraction | Correct extraction location / correct extraction location | Unlocalized / unlocalized |
| Reconciliation condition | Wrong extraction / wrong extraction | Wrong extraction / wrong extraction |

Baseline selected the correct location in 2/8 trials, but both explanations merely
restated the candidate defect. They did not describe loss in the extraction
output. Candidate selected the correct attribution in 1/8 trials. Neither arm
correctly named the reconciliation signal. Baseline reconciliation repetition 2
described the defective signal accurately while naming extraction. Candidate
captured repetition 2 explicitly said the greeting was present upstream while
also naming extraction. These are attribution errors despite valid response shapes.

Wrong upstream selections were 6/8 baseline and 5/8 candidate. The lower candidate
count does not establish improvement: it also missed both genuine extraction
losses. Four candidate answers cited nonexistent source lines: captured repetition
2 included line 8 although the catalogue ends at 7; loan repetition 2 and both
reconciliation repetitions included line 2 although their catalogues end at 1.
This manual mechanical check predicts rejection of those unchanged responses;
native loss admission was **not executed**. Only one candidate wrong selection
had a valid source range, versus six baseline selections. Actual upstream
rebuilding, repairs and repair-induced harm were not executed or measured.

| Arm | Input tokens | Output tokens | Total tokens |
| --- | ---: | ---: | ---: |
| Baseline | 11,384 | 1,081 | 12,465 |
| Candidate | 13,728 | 975 | 14,703 |

The candidate used 18% more total tokens without meeting the quality gate.
Complete serialized request bytes were stable across unchanged repetitions:

| Case | Baseline bytes | Candidate bytes |
| --- | ---: | ---: |
| Captured description | 10,858 | 14,254 |
| Downstream loan | 6,927 | 7,574 |
| Source-only extraction | 6,713 | 7,050 |
| Reconciliation condition | 6,952 | 7,647 |

The manifest retains prompt/schema/evidence byte contributions separately; no
estimated tokens are presented as provider usage. Frozen model/settings, edit
hashes and original parent identity were verified before dispatch. Startup first
failed because the historical copied workflow still supplied the obsolete
`retry-limit` option on `reuse-summary`. Removing that one option made the copied
YAML identical to current canonical workflow YAML. The execution record retains
both hashes. The original capture, frozen request/schema bytes and provider
settings stayed unchanged. A subsequent client setup error was corrected before
any POST; neither setup attempt sent a provider request.

Assessment is model-assisted, non-blinded and independently reviewed against the
same frozen evidence. It is not deterministic semantic proof. The failed gate
does not establish improved semantic attribution, successful R6 recovery or a
basis for production promotion. Candidate-local repair success, unknown-ownership
semantic quality, publication and rubric quality remain unmeasured.
