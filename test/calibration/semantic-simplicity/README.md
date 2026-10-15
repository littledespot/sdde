# Semantic simplicity: Phase 0 protocol

This is the offline evaluation foundation for [FIX04 §5.6](../../../fixes/FIX04.md#56-phased-rollout-and-exit-gates).
It prepares source-only fixtures and checks accounting of supplied semantic labels.
It neither classifies prose nor executes a provider or workflow. A synthetic pass
establishes that the measurement machinery works; it establishes no model benefit.

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
Schema, explicit low reasoning, the engine's fixed temperature `0.1` and a
provider-requested allowance of 16,384 output tokens. The registered GPT-OSS
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
exactly one label per source duty. Duplicate, missing or foreign observations,
duties, case variants and partitions reject. Unknown schema fields reject.

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

Freeze qualification size after baseline, before candidate selection:
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
capacity limit or token reservation; the output allowance remains provider-owned.
The scorer detects supplied unknown/over-budget evidence; it is not a dispatcher.
A future live comparison owner must enforce stops before each additional send.

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
