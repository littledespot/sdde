# Isolation comparison results — 10 October 2026

**The captured-story judgment improved, but the unchanged acceptance gate failed.**
All 60 approved physical calls completed. Isolated calls returned the expected
preservation labels in all 24 assembled decisions, compared with 22/24 for the
batched baseline. Two isolated decisions failed native admission, leaving **22/24
correct admitted attributions in each arm**. The production lifecycle split is
therefore not promoted; live source-review handoff and E2E remain unqualified.

## Execution and controls

- Frozen [manifest](comparison.json), [criteria](README.md), and complete
  [scorecard](scorecard.json).
- Execution: `2026-10-10T10:25:32Z`–`10:27:02Z`.
- Local [execution journal](../../../../../zig-out/source-loss-isolation-comparison/2026-10-10T10-25-32Z/results/execution.json).
  That directory retains every serialized request, raw provider response,
  parsed answer, native report, candidate receipt and independent assessment.
- Same Bedrock `openai.gpt-oss-20b-1:0`, `ap-southeast-2`, low reasoning,
  temperature 0, native schema and 16,384 output allowance in both arms.
- Twelve known cases, two repetitions. Candidate requests change only the complete
  comparison supplied and its permitted comparison ID. Original IDs, member
  ordering, sources, obligation, supporting context and prompt remain unchanged.
- Actual provider request bytes matched their frozen projections. All twelve
  baseline requests also match the preceding obligation experiment's candidate
  requests. All six single-collection cases have byte-identical baseline/candidate
  requests in this experiment.
- No retries, correction, repair, model judges or E2E calls. All 60 completed with
  provider `stop`, valid JSON and valid response schemas; no truncation occurred.
  The allowance is consumed. Credential/session-token scans found no matches.

## Results

The denominator is 24 complete case/repetition decisions per arm. A candidate
decision includes all its assigned responses; successful siblings cannot
compensate for an invalid child.

| Measure | Batched baseline | Isolated candidate |
| --- | ---: | ---: |
| Physical calls | 24 | 36 |
| Complete, JSON/schema-valid decisions | 24/24 | 24/24 |
| Correct preservation labels | 22/24 | 24/24 |
| Native admission | 24/24 | 22/24 |
| Correct admitted attribution | 22/24 | 22/24 |
| Adequate assembled evidence | 21/24 | 22/24 |
| False upstream attribution | 2 | 0 |
| False candidate attribution | 0 | 0 |
| Actual input tokens | 31,140 | 47,236 |
| Actual output tokens | 6,099 | 8,227 |
| Total tokens | 37,239 | 55,463 |
| Median serial round trip per decision | 1,154 ms | 1,820 ms |

Total usage was **92,702 tokens**. Isolation used 50% more calls and 48.9% more
tokens. Round trips include debugger/transport overhead; provider latency was
unavailable. These figures do not establish dollar cost.

### Captured-story: specific improvement

Both batched repetitions recognized the greeting in comparison 1, then claimed it
was absent from comparison 2. Both collections explicitly contain the startup
greeting requirement in member 2. Those false `lost` judgments admitted incorrect
upstream role attribution.

All four isolated child responses recognized the requirement and cited member 2
and source line 6. Both assembled decisions admitted the correct candidate
attribution. Captured-description passed twice in both arms. This supports an
isolation benefit for captured-story, not batching as the only failure cause or
broad reliability.

### Candidate failures: correct loss judgments, invalid evidence selections

| Assembled trial | Defective child | Observed result |
| --- | --- | --- |
| `extraction-inherited-candidate-1` | Comparison 1 | Correctly says pump shutdown/until-recovery is absent and cites the source, but returns `members: []` for the nonempty display/record collection. |
| `unresolved-multiple-producers-candidate-2` | Comparison 1 | Correctly identifies absent eight-hour cooling and alarm requirements, cites both sources, but returns `members: []` for the nonempty temperature collection. |

The shared validator requires a nonempty assessed-member selection for a nonempty
collection. Both responses were rejected as `InvalidPreservationComparison`.
Correct semantic labels remain separately recorded; no IDs were filled in and no
verdict, validator or aggregation requirement was changed.

The unresolved case has one comparison: baseline and candidate requests are
byte-identical. Its failed repetition cannot be attributed to a batching change.
Independent response variability remains visible.

### Other evidence findings

Baseline `dual-ready` repetition 2 returns correct labels, but assessment 1
selects member 2 (the payer's literal) while its explanation names member 3 (the
inspection requirement). Native range checks admit this; semantic evidence
assessment does not. Both isolated repetitions cite the correct occurrences.

Both baseline voucher lost assessments cite only payment; the preceding
assessment supplies manager approval. The previously frozen assembled-answer
scoring rule credits their combined evidence. Per-child adequacy remains false
for those assessments. Isolated lost assessments cite both sources and pass both
measures. No scoring rule changed after viewing responses.

## Gate decision

On the original eight cases, baseline passed native admission and correct
attribution on 16/16; candidate achieved 14/16. Candidate fails:

- At least 15/16 complete, schema-valid, natively admitted decisions.
- Both correctly admitted extraction-loss and unresolved-ownership trials.
- No case-level regression.
- At least two additional correct admitted attributions over baseline.

The superiority gate is mathematically unreachable against this panel's perfect
baseline; that does not explain away the separate admission and regression
failures. No threshold was relaxed. Candidate meets captured-story's 2/2 gate and
all six trials from the three previously fresh families, now known regressions.

## Consequence and next boundary to examine

Diagnostic projection, full-assignment aggregation and per-child origin checks
are implemented and tested. Conditional production splitting, correction
orchestration, persisted multiple-call origins and live review-to-loss handoff
are not claimed complete. No E2E invocation followed the failed gate.

The next bounded investigation should examine the evidence-selection contract:
native code already assigns the complete collection, but the response also selects
`members`. The rejected answers are consistent with interpreting this field as
supporting witnesses rather than assessed members. Their internal reason for
returning an empty selection is not established.

Before changing that boundary, distinguish native assignment identity from
model-selected explanatory evidence across admission, correction, persistence and
repair. Do not silently populate evidence or permit empty selections merely to
make these responses pass. Any contract change needs explicit semantics and
negative tests, then a newly frozen comparison. Retain the captured-story benefit
as candidate evidence, not permission to promote a failed experiment or split
unrelated workflow calls.

Assessment was manual and unblinded, with separate reviewers covering all cases
and primary review of failures. Fixed obligations and one model/settings pair do
not establish faithful upstream `missing_obligation` generation, successful repair
or published specification quality.

## Offline verification

- `zig build test-specification-generation -j2 --summary all`: **290/290** passed
  before dispatch and again while admitting captured results.
- `zig build verify --summary all -j2`: **1,461/1,461 tests**, **142/142 steps**
  passed, including architecture, integration and packaging smoke checks.
- Frozen hashes, actual request byte comparisons and `git diff --check` passed.
  No production prompt, schema, workflow or validator changed.
