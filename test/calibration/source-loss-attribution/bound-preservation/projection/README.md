# Bound preservation — shared projection comparison

**Status: 32/32 approved calls executed; quality gate failed.** The preceding 32-call experiment
[failed its frozen gate](../README.md#results--10-october-2026). Its requests and
results remain unchanged. The follow-up results are recorded below. Its approval
is consumed; no repair or E2E invocation ran.

Offline verification on 10 October 2026: specification-generation **288/288 tests**;
`zig build verify --summary all` **1,455/1,455 tests, 142/142 steps**, including
integration and native packaging smoke checks. Formatting, diff and frozen hash
checks pass. Live evidence is separate from these offline results.

## Change being tested

Both arms use the same bound comparisons, native member occurrences, source
catalogue, closed response schema, admission and attribution. The baseline is the
preceding experiment's **candidate**, not its retired culprit-selection arm.

The revised production presentation:

- Assesses only the complete upstream member collections. Target field purpose
  accompanies the fixed finding; it is not a request to author that field.
- Separates the already deficient subject and producer outputs as supporting
  context, retaining their resolved business meaning and role assignments.
- Offers one comparison-local member ID per occurrence. Canonical claim/citation
  IDs and half-open source coordinates remain in native evidence. Source responses
  select only IDs in the inclusive source-line catalogue.

This bundle addresses observed subject confusion and competing selection
conventions. It does not prove why the model made its earlier decisions, prevent
false semantic labels or grant new repair permissions. Supporting text cannot
substitute for absent meaning in an assessed collection.

## Frozen plan

[comparison.json](comparison.json) binds all request hashes, native owner sources,
settings, case expectations, trial order and the unchanged quality gate. Paths for
edits and provider requests resolve against **the parent `bound-preservation/`
directory** (`paths_base: ".."`); source paths resolve against repository root.
Baseline files reference the immutable preceding candidate. Candidate files live
here. Do not update either arm after dispatch.

Eight cases × two arms × two repetitions = **32 physical calls maximum**. Reuse
the recorded Bedrock `openai.gpt-oss-20b-1:0`, low reasoning, temperature 0, native
schema, 16,384 output allowance and `ap-southeast-2` region. No retries, correction,
repair, automatic judges or E2E execution belong to this allowance. Every attempted
send consumes a trial. A transport/bootstrap uncertainty stops dispatch.

All eight inputs have now been observed. The original four development cases and
four former unused cases are reported as **development** and **known regression**;
none is a fresh holdout. Keep their source facts, labels and limitations from the
[preceding case table](../README.md#cases-and-premises).

Every candidate gate remains required: at least 15/16 completed/schema-valid/native
responses; zero false upstream/candidate attributions; both correct extraction,
signal and role diagnoses; both safe multi-producer unresolved results; at least
7/8 candidate-defect diagnoses; at most one unnecessary uncertain diagnosis;
adequate evidence on at least 14/16; at least two more correct admitted attributions
than baseline without case-level regression. Apply native admission to **both**
arms. Report verdict correctness independently of the derived owner. A more compact
packet, valid JSON or safe unresolved result alone is not semantic success.

## Offline proof and live procedure

`zig build test-specification-generation --summary all` reconstructs the canonical
cases, verifies their native assignments against the historical snapshots, checks
that every source and member meaning survives projection, and reproduces all
frozen provider bodies through the production Bedrock encoder. It also checks the
candidate against the current production packet and prompt. Regression tests cover
resolved exact/passive values, role choices, subject projections and request memory
ownership. Full verification includes production correction and repair paths.

After explicit bounded approval under [§28.8](../../../../../design/contracts/28-testing.md#288-model-protocol-correction-and-semantic-calibration):

1. Verify every manifest hash and exact parent/settings before any send. Use the
   existing [isolated debugger replay procedure](../../README.md#bounded-replay-procedure).
   Copy the whole parent comparison directory so both arms resolve. Do not import
   replay responses into a production workflow.
2. Send the manifest's 32 modified replay edits in order, exactly once each. Retain
   actual provider request/response, stop reason, tokens, latency and normalization.
   Verify serialized request equality with the frozen provider body.
3. Place each parsed response at
   `.zig-cache/source-loss-preservation/<case>.projection-<arm>.response-<1|2>.json`.
   Rerun the offline command. The existing admission helper writes the corresponding
   `.native-<1|2>.json` using production `Source.admitComparisons` for both arms.
   Missing files are unassessed, not successful. Retain these reports beside raw
   responses and the execution journal.
4. Review every trial against the unchanged source facts. Use the preceding
   [scorecard fields](../scorecard.template.json), updating run/trial metadata for
   this manifest. Score invalid references, comparison labels, admitted ownership,
   false allegations, uncertainty and evidence adequacy separately. Retain all
   failures in denominators. Disclose that this is non-blinded semantic assessment.

Only a passing Phase 3 gate permits the separately approved, conditional Phase 4
production E2E invocations. A failed gate leaves FIX01-01 incomplete.

## Results — 10 October 2026

All 32 approved requests executed once, with no retries, repairs, judges or E2E.
Every response ended with provider `stop`, passed JSON/schema checks after the
standard Bedrock prefix normalization, and was checked through production native
admission. The retained [execution journal](../../../../../zig-out/source-loss-projection-comparison/2026-10-10T07-32-15Z-v2azhjiy/results/execution.json)
and [complete scorecard](../../../../../zig-out/source-loss-projection-comparison/2026-10-10T07-32-15Z-v2azhjiy/results/scorecard.json)
include raw responses, per-trial native reports and semantic assessments.

| Measure | Baseline | Revised projection |
| --- | ---: | ---: |
| Completed, JSON/schema valid | 16/16 | 16/16 |
| Native admission | 8/16 | 16/16 |
| Correct comparison verdict sets | 11/16 | 14/16 |
| Correct admitted attribution | 6/16 | 14/16 |
| Invalid source selections | 8/16 | 0/16 |
| Invalid member selections | 0/16 | 0/16 |
| False upstream ownership | 0 admitted | 2 role attributions |
| False repairable upstream attribution | 0 admitted | 0 admitted |
| Unnecessary unresolved attribution | 2/16 | 0/16 |
| Evidence adequate for the assigned finding | 6/16 | 14/16 |
| Input tokens | 28,720 | 18,230 |
| Output tokens | 3,651 | 3,877 |
| Total tokens | 32,371 | 22,107 |

Total usage: **54,478 tokens**. Revised total tokens were 31.7% lower. Recorded
debugger roundtrip totals were 21,104 ms baseline and 21,887 ms candidate; provider
latency was unavailable. These include local replay/logging overhead, not pure
provider inference time. No dollar-cost estimate is inferred.

The revised arm correctly attributed both repetitions of loan and parking candidate
loss, joint-source candidate loss, genuine extraction loss, direct-signal loss,
wrong role assignment and safe unresolved multi-producer ownership. Baseline
passed only extraction, joint-source and unresolved cases. The improved baseline
result relative to its earlier execution also demonstrates variability; use this
concurrent paired comparison, not selected historical trials, to measure the gain.

**Remaining failure: captured-description, both repetitions.** The revised model
returned `preserved` for the full extracted collection and `lost` for the assigned
business claims. It claimed that a separate `preserved_token` member was necessary,
despite the assigned business claim explicitly stating the required greeting.
Correct assessments remain `preserved`/`preserved`, yielding candidate attribution.
Native code correctly derived `unsupported_role` from the incorrect semantic
labels. It did not authorize role repair, but this is still **false upstream
ownership**, not a successful diagnosis or harmless normalization.

Two frozen gates failed: zero false upstream ownership, and at least 7/8 correct
candidate-defect diagnoses (actual **6/8**). All other numerical gates passed.
Safety worsened on the captured case from unresolved ownership to a false known
owner, despite the overall accuracy gain. Phase 3 is therefore **not accepted**;
the conditional Phase 4 E2E runs remain unused.

Assessment is non-blinded model-assisted review of these observed regression
inputs, not deterministic semantic proof. In the wrong-role case the second
assessment cites the opening-hours line rather than the absent notification's
source line. The complete response cites the notification in its first assessment
and explains its absence correctly; the scorecard discloses this weaker local
citation precision rather than treating native validity alone as evidence quality.

The next candidate needs to distinguish **preservation of resolved meaning** from
**presence of a particular canonical content kind**. Inspect whether category
labels are necessary in this semantic comparison and clarify that a supported
obligation can be expressed by the complete collection without a separate typed
token member. Test the same obligations across embedded and separate literal
representations, plus genuine missing literal/condition controls. Do not insert
tokens into role bindings, suppress the finding, or teach the native engine to
override a semantic label. This recommendation is not yet implemented or approved
for another live comparison; historical requests and gates remain frozen.
