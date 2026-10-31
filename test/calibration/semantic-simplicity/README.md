# Semantic simplicity: protocol and baseline harness

This is the offline evaluation foundation for [FIX05 B5, now FIX06 H4](../../../fixes/FIX06.md#h4-experiment-stops-qualified-scope-and-the-formal-baseline-b4-b5)
(former FIX04 §5.6).
It prepares source-only fixtures and checks accounting of supplied semantic labels.
The Phase 0 scenario neither classifies prose nor executes a provider or workflow.
The separate Phase 2 harness below can acquire explicitly approved production
workflows and import source-backed assessments. A synthetic pass establishes
measurement mechanics; it establishes no model benefit.

## Frozen inputs and ownership

- [protocol.json](protocol.json) fixes one current small-model cohort, development
  counts, thresholds, limits and uncertainty method. `live_authorized: false` is
  mandatory. This file cannot authorize dispatch.
- [cases.json](cases.json) retains exact original source bytes and evaluator-only
  duties, supporting quotations, literals, permissible alternatives, prohibited
  inventions and expected terminal outcomes/questions. These are evaluation labels,
  never generation obligations supplied by an oracle.
- [specimens.json](specimens.json) contains six labelled candidate specimens:
  faithful, faithful paraphrase, omission, invention, false clarification and a
  harmful repair of an initially faithful candidate. They test accounting of those
  labels, rather than an automatic semantic judge.
- [generation_comparison.zig](../../harness/generation_comparison.zig) owns closed
  decoding, source projection, counterbalanced trial planning, feature aggregation,
  qualification sizing and seeded paired uncertainty. The
  [integration scenario](../../integration/generation_protocol_tests.zig) loads the
  fixed panel, checks all specimens and writes dry-run artifacts.

Source paths and case/duty IDs in these fixtures are development identifiers, not
validated production path or evidence capabilities. Production requests must use
the existing ingestion, grouping, association and request owners. No generated
projection is imported as authority.

## Cases and partitions

The panel contains **24 independent features / 72 case variants**. Each feature
has a base case, a meaning-preserving equivalent and a requirement-changing
control; all three stay in the same partition. Eight features are development
(six sufficient-source cases, one genuine gap and one conflict). Sixteen features
are reserved for qualification (twelve sufficient, two gaps and two conflicts).
Small and medium feature sizes and unrelated application domains are represented.
Conditions, exceptions, negation, cross-source support, entities, exact values,
several duties and role-specific scenarios occur in the source-backed labels.

The equivalent variants reorder independent normative statements and add an
explicitly nonnormative note. They preserve meaningful order, boundaries and
exact literals. This tests one combined representation intervention; it does not
isolate paraphrasing from context distraction. Changed controls alter an actual
requirement or resolve/remove evidence, with correspondingly different labels.

The labels and all equivalent/changed triplets received a separate model-assisted
source review before candidate experiments. That review corrected ambiguous
cancellation boundaries, an overbroad Given-condition prohibition, an exclusivity
condition and a missing approval restriction. No material dispute remains in the
reviewed fixture set. This is not human approval or deterministic semantic proof.
Mechanical tests prove quotation/literal membership and closed structure only.
Later scoring disagreements must be retained and adjudicated before promotion.

Qualification cases may be loaded for structural checks, but their source-only
projections are not exported by this scenario and they must not be used for prompt
or candidate tuning. Choose the first N qualification features in inventory order
after applying the frozen Phase 2 sizing rule; retain that exact list before
candidate selection or access to qualification responses. A discovered label
defect requires a new versioned experiment freeze, not silent holdout retuning.

## Model and comparison

On 16 October 2026 the user switched the selected test model back to
**GPT-OSS-20B on Bedrock**. The prospective protocol freezes
`aws-bedrock / openai.gpt-oss-20b-1:0 / ap-southeast-2`, using Converse, native JSON
Schema, explicit low reasoning and the engine's fixed temperature `0.1` on the
protocol's explicit `generation_slot` (`spec_generation`). No role requests an
allowance below the model maximum: since 18 October 2026 the protocol records
`max_output_tokens` 16,384, every request sends it, and the frozen binding rejects any
other value (ADR 0011 "Model maximum output"). Since 24 October 2026 (schema 4) it also
records the catalogue deadline `request_timeout_ms` 180,000 (ADR 0030 "Request
deadline"), which the frozen binding checks against every request description (the
deadline is never sent on the wire); schema 3 added the Bedrock `family` (ADR 0029). Every other role retains the
exact model and effort in the frozen `.sddtoolkit.json`; the current `repair` role
selects low effort. Capture, budget-evidence import and scoring validate each request
against its own configured slot, while retaining the selected cohort's model,
region, native schema and fixed temperature. Every role sends the same frozen
maximum. The registered GPT-OSS
profile sends `additionalModelRequestFields.reasoning_effort: "low"`; it does not
send Luna's additional strict-output field. This selection does not qualify model
quality. Record the evaluation date and exact binding/capture, and stop for
configuration drift.

The shared [live-test cost policy](../../harness/model_cost_policy.zig) permits
only this exact Bedrock tuple before credentials/network, for generation,
diagnostics and rubric evaluation. Luna, direct OpenAI API selection and other
GPT-OSS IDs or aliases are not allowed test alternatives. The native-schema judge
contract is preserved. Offline mocks may exercise other provider contracts
without creating paid requests.

The closed prospective protocol requires `reasoning_effort: "low"` and
`temperature: 0.1`. Omitted/null controls, other effort/temperature values and the
superseded Luna-only protocol fields reject. The native schema remains the
engine's acceptance contract.
Any reasoning actually supplied by the API is retained separately as owned
diagnostics; absent or redacted reasoning is never invented as readable text.

Arm A is current per-group generation; C is whole-collection generation over the
same original sources and complete record duties. Three repetitions of each
case variant produce **144 paired-arm feature workloads**: 8 × 3 × 3 × 2.
Counterbalance A/C dispatch order across case/repetition pairs. These are workload
counts, not API-send counts: A's assignments and every retry/review/repair must be
included. The dry run simulates two sends for A and one for C solely to test that
assignment counts cannot alter feature weighting; it makes zero actual sends.

Phase 1 must qualify the current binding with a fresh authentic production-path
exchange. Phase 2 freezes the unchanged baseline revision and its production-built
requests. Before each separately approved live experiment, retain exact prompt,
schema, packet, source association, ordering and effective setting bytes for its
arms, plus physical-send accounting. This offline source projection is not such a
request and cannot supply a production origin to a diagnostic result. B/D arms
are excluded from this freeze; adding one requires a new bounded protocol.

## Scoring and decision rules

Every trial has one observation, including explicit unattempted/provider-failed,
malformed, truncated and blocked outcomes. Complete/clarification candidates have
exactly one label per source duty for complete evidence. Partial labels remain
explicitly incomplete/disputed and cannot pass qualification. Duplicate or foreign
observations/duties, missing planned observations, invalid case variants and
partition mismatches reject. Unknown schema fields reject.

The observation retains an explicit **initial assessment** separately from final
assessment and correction count. Score first-pass fidelity, robust bundles,
representation sensitivity and repeat inconsistency from original responses.
Recovered output never substitutes for original labels. Issue-event counts are
cumulative across the whole chain and cannot be less than initial counts;
material/false-gap incidence includes initial and final assessments, and omitted
duties count their union once per workload/duty. Correcting an invention, omission
or false clarification therefore retains the observed harm. A later harmful review or
repair can count harm while initial generation remains faithful. Scores include
all complementary assignments for a complete feature workload; never compare
per-call pass rates across A/C. Reduce repeats/variants within each independent
feature, then give features equal weight. Genuine-gap controls have their own
expected-question/terminal score; they cannot count as useful completion.

Synthetic and diagnostic evidence scopes always report zero useful completions
and no workflow authority, even if a supplied label claims publication. Actual
production qualification and published-output evaluation belong to Phase 5.
Semantic labels are supplied by source-based assessment; keyword overlap,
record counts, a closed schema or a model claim cannot produce a fidelity label.

The scorecard also reports each arm's complete-workload send/token totals and
median/worst observed tokens and elapsed time. Missing usage or elapsed evidence
makes the corresponding summaries unavailable. Synthetic resources are explicitly
separated from actual consumption; cost per useful completion is unavailable
because these scopes cannot publish useful output.

The frozen numerical gates are engineering choices for this panel:

| Gate | Threshold |
| --- | --- |
| Complete initial fidelity | ≥ 85% |
| Robust success across each three-variant bundle | ≥ 75% |
| Published useful completion, Phase 5 only | ≥ 80% |
| Material-harm and false-gap incidence | ≤ 5% each |
| Meaningful improvement | ≥ 10 absolute percentage points; other primary measure cannot decline |
| Primary brittleness reduction | ≥ 10 points in representation sensitivity; ≥ 6 common-original-success features |
| Complete workload token/latency ratios to A | ≤ 1.25 / ≤ 1.50 |

Also require no new material regression on a previously faithful control or
worsening in a declared risk stratum, and improvement in at least two independent
features from different domains. Clarification cases must retain their expected
outcomes. These conditions are not relaxed by a favorable average. A baseline
with no headroom for the target improvement does not justify decomposition.

Use a paired feature bootstrap with 10,000 resamples, seed 20261015 and a 95%
percentile interval. A benefit requires the mean to meet the effect gate and its
lower interval bound to exceed zero; compute the preselected brittleness outcome
separately. This is exploratory panel uncertainty, not a validated population-rate
claim. Model-assisted scoring and absence of human adjudication remain explicit
qualification limits.

Freeze qualification size after baseline, before candidate selection, using the
sample standard deviation of complete first-pass fidelity across independent
well-posed development features (the explicitly selected protocol metric):
`N = max(8, ceil((1.96 × baseline_feature_stddev / 0.15)^2))`.
The 8–16 feature bound and 0.15 half-width target are a planning approximation,
not a guarantee that a small convenience panel has 95% precision. Demand above
16 is infeasible under this freeze; do not clamp it or sample until a preferred
answer emerges. The paired interval and all regressions must still be reported.

The prospective experiment stops at **1,000 physical sends or 2,000,000 actual
input-plus-output tokens**, including corrections, failures, review and repair.
After unknown usage, uncertain delivery, configuration drift or a material scoring
dispute, stop and report the evidence as inconclusive. Record all overshoot and
unattempted trials. Equality prohibits further sends but a fully observed panel
that finishes exactly at its limit remains complete evidence; overshoot is
inconclusive. These experiment-wide stops add no engine-local per-call
capacity limit or token reservation; the model's own output maximum applies.
The scorer detects supplied unknown/over-budget evidence. The baseline acquisition
owner enforces these stops immediately before every physical transport send;
provider usage is reconciled against the exact native origin before another send.

## Execute Phase 0

```sh
zig build test-rubric-evaluator
zig build test-integration
zig build verify
```

If the default Zig global cache is not writable, use the same registered steps
with `--global-cache-dir /private/tmp/sdde-zig-global-cache`.
The integration scenario writes `.zig-cache/semantic-simplicity/phase0/`:
`development-plan.json`, 24 development `source-inputs/*.json` files and
`dry-run.json`, including fixture SHA-256 identities, counts, synthetic accounting,
authority exclusions and unmeasured/live-not-run status. These are regenerated
projections, not hand-maintained source files. Retained evidence and limitations
are recorded in [phase0-results.md](phase0-results.md).
The retained 15 October results and `phase0-dry-run.json` describe the earlier
Luna freeze and remain historical. A fresh integration run writes the current
GPT-OSS model and new protocol SHA-256 to the cache report; that offline report
does not qualify an authentic exchange or reuse historical quality results.

## Prepare, acquire and assess Phase 2

The [baseline harness](../../harness/baseline/cli.zig) runs unchanged arm A alone:
**72 workloads**, with actual production predecessors, three repetitions and all
three development variants. It has separate `prepare`, `acquire --live` and
`score` commands. Controlled-predecessor compatibility/diagnostic captures cannot
be imported as full workflow runs or useful product completions. No Phase 2 live
panel or qualification claim is established by the offline tests.

Before freezing, copy [budget-plan.example.json](budget-plan.example.json) to an
explicitly selected plan. Record which phases share the experiment stops, the
configured workflow budget, native E2E evidence directories and the user's budget
decision. The example deliberately has no evidence and an unresolved decision.
The feasibility check reads actual selected-binding requests/responses/usage,
includes review and repair, and projects the worst observed complete workflow
over the declared workload range. Stopped chains remain lower bounds. This is a
declared planning assumption, not a guarantee about unseen candidate costs. It
cannot change engine policy, grant live approval or reduce the frozen panel.

Run preparation offline with explicit repository-relative inputs:

```sh
./scripts/baseline.sh prepare \
  --protocol test/calibration/semantic-simplicity/protocol.json \
  --cases test/calibration/semantic-simplicity/cases.json \
  --template-case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json \
  --budget-plan test/calibration/semantic-simplicity/budget-plan.example.json \
  --rubric test/calibration/semantic-simplicity/rubric.json
```

Preparation writes `budget-feasibility.json` and build reconstruction inputs under
`zig-out/baseline/<UTC-run>/`. It writes a freeze and A-only plan only when the
source/build is committed, the explicit decision is recorded, and native cost
evidence supports the declared budget. Otherwise it exits unsuccessfully with a
blocked report and no API call. The currently observed budget-stopped diagnostics
alone cannot meet this prerequisite. Resolving that prerequisite requires the
user's budget and scope decision in
[FIX05 B4, now FIX06 H4](../../../fixes/FIX06.md#h4-experiment-stops-qualified-scope-and-the-formal-baseline-b4-b5); the harness does not raise the workflow budget.
The explicit [publication rubric](rubric.json) is frozen separately from the
template case. Its binary criteria require every material criterion to pass;
source-specific Hello World expectations never assess other panel features.
Rubric bytes and evaluator expectations remain outside generation files.

After reviewing that concrete freeze and obtaining explicit approval for the
listed live workloads, acquisition uses:

```sh
./scripts/baseline.sh acquire --freeze zig-out/baseline/<UTC-run>/freeze.json --live
```

The executable rejects source/build/toolchain/settings drift before credentials.
Only `acquire` loads `.env.e2e` through the launcher. Every exchange keeps the
production context, exact request bytes, raw provider response and extracted model
output, with native origin and hashes. Original candidate snapshots remain
separate from later candidates and actual publications. All sends, failures,
unknown usage, overshoot and unattempted workloads stay visible in
`acquisition.json`; unknown usage or uncertain delivery prevents further sends.
Before credentials, an exclusive claim binds the exact freeze hash to one
acquisition. Repeating the command or copying the freeze cannot reset its budget;
failed and interrupted acquisitions cannot resume. Retained allowance reports
show consumed and unspent resources. Declared later phases remain reserved and
unexecuted; their dispatch must consume shared accounting when implemented.

Scoring never dispatches. Supply a closed assessment document, initially
`{"schema":3,"entries":[]}`, to export evaluator-only assessment packets:

```sh
./scripts/baseline.sh score \
  --freeze zig-out/baseline/<freeze-run>/freeze.json \
  --cases test/calibration/semantic-simplicity/cases.json \
  --acquisition zig-out/baseline/<acquisition-run>/acquisition.json \
  --assessments zig-out/baseline/assessments.json
```

The scorer verifies the native capture and writes `assessment-inputs.json`,
`score.json` and `report.md` to a fresh result directory. The evaluator packet
contains development sources/expectations and exact native output targets; it is
never materialized into the generation project. Qualification sources remain
unexported. The [assessment contract](../../harness/baseline/assessment.zig)
requires per-duty judgments, exact source/output quotations, assessor provenance,
separate initial/final labels, cumulative issues and explicit disputes. Missing
labels remain incomplete rather than becoming invented omissions. Model-assisted
labels are semantic judgments, never deterministic proof or workflow authority.
Keep assessment documents under the output root so supplying labels does not
alter the frozen source/build inputs.
The separate `upstream` judgments bind each original extraction/reconciliation
assignment's native origin, exact output identity/hash, source quotations and
assessed outcome. Every original upstream assignment must be assessed; a later
correction cannot supply its missing label. Native mechanical failure requires
native rejection evidence. Corrective/context follow-up observations remain
separate, and a faithful initial specification does not erase an upstream loss.
Qualification sizing continues to use the frozen specification-generation
fidelity metric.
For each upstream judgment, inspect that call's exact retained request/context
under the packet's native directory. Assess its assigned chunk or reconciliation
scope; do not demand every full-feature duty from each individual chunk response.

Review-finding judgments bind the exact native origin, subject, ordinal and
predicted kind, and supply a source-backed `expected_kind`. Reports show
confusion counts and each type's precision/recall for original, latest and
corrective findings. Source/signal/token/conflict, principles and omission
preservation comparisons use their native closed vocabularies. Missing, disputed
or unverifiable projections remain unmeasured. A declared wrong type cannot be
omitted from a complete cumulative harmful-diagnosis assessment.
Canonical partial repairs retain their predecessor origin. Their changed fields
and inherited verdict are measured only through exact, previously verified native
history; foreign, missing or unverified history cannot establish finding accuracy.
`final_current_issues` describes defects still present in the final output;
cumulative issue events retain harm from the entire chain. This permits a
separate correction-assisted fidelity measure without erasing earlier harm or
substituting recovered output for first-pass fidelity.
For a native publication, `published_rubric` binds the exact publication and
frozen rubric hashes to a canonical criterion assessment and provenance. Useful
completion requires native publication, current source fidelity and a met rubric
threshold. Missing or disputed judgments stay unknown. The report retains sends,
input/output/total tokens and elapsed-time median/worst distributions, plus all
dispatched cost per useful completion, including failed-workload costs. This
measures observed baseline publications without granting Phase 5 qualification.

Reports retain per-feature fidelity, robustness, representation sensitivity,
repeat variability, native failure chronology, supplied semantic failure-stage
attribution, whole-workload latency and stage send/token shares. Qualification
sizing uses complete first-pass fidelity as explicitly selected by the user;
incomplete evidence cannot select holdout IDs. Counts outside the frozen sample
or observed-cost envelope are reported infeasible without shrinking the sample.
Forecasts include actual baseline consumption and every declared future phase,
including selection. Repeat inconsistency covers each frozen variant; missing
variants and mechanical failures cannot masquerade as material representation
failures. Per-feature and risk-stratum reports retain category incidence and
exact cumulative event counts. An explicit advance/retain/revise/inconclusive
decision and recurring failure examples accompany the scorecard. Unknown causes,
incomplete rubric evidence or unresolved scoring prevent advancement.
Resource totals cover the native production workflow; the cost of acquiring
externally supplied semantic judgments is not measured by this offline command.

Offline verification entry points are `zig build test-baseline`,
`zig build test-baseline-launcher`, `zig build test-integration`,
`zig build smoke-baseline` and `zig build verify`. The build graph keeps live
dispatch out of automated verification; isolated native smoke processes have
model connections compiled out.
