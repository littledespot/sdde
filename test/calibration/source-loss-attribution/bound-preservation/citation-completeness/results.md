# Citation-completeness comparison — 11 October 2026

**The candidate passed the frozen citation and safety gates.** All 76 approved
diagnostic calls completed. The shared guidance resolved the observed missing
alarm citation in both repetitions: complete citations improved from **36/38 to
38/38 physical assessments**. Correct verdicts, relevant citations and adequate
explanations remained **38/38** in both arms; native admission and correct
attribution remained **26/26 assembled decisions** in both arms.

This qualifies the guidance on these supplied obligations and isolated collections.
It does not qualify actual source-review handoff, production batching, repair,
publication or the rubric quality of a generated specification. No whole-workflow
E2E run or additional source-review call was performed.

## Frozen execution and evidence

- [Manifest](comparison.json), [predeclared gates](README.md) and
  [completed scorecard](scorecard.json).
- Retained [execution journal](../../../../../zig-out/source-loss-citation-completeness-comparison/run/results/execution.json),
  actual provider requests/responses, model text, validation and complete native
  receipts/reports beneath that journal's directory.
- Independent unblinded assessments of the two case subsets:
  [first six cases](../../../../../zig-out/source-loss-citation-completeness-comparison/assessment-agent-a.json)
  and [remaining seven cases](../../../../../zig-out/source-loss-citation-completeness-comparison/assessment-agent-b.json).
  Codex reviewed all actual collections, source spans and explanations and reconciled
  those independent assessments. This is model-assisted semantic assessment, not
  deterministic proof or an additional live model-judge panel.

The run used the approved AWS Bedrock `openai.gpt-oss-20b-1:0` in
`ap-southeast-2`, low reasoning, temperature 0, native schema and 16,384 output
allowance. The frozen citation manifest hash was
`d206d8302fb71c4affa5bc0141304012be93df5409dd43cc7c6ea98d19f1b862`.
All actual serialized provider requests matched their pins. Both arms used the
same current native admission owner. No settings drift, unknown usage, uncertain
dispatch, absent answer, retry, correction, repair or extra send occurred.
The 76-call approval is consumed; restarting grants no further allowance.

All 76 responses used the existing `removed_leading_brace_quote` normalization.
JSON/schema success refers to the answer after that approved normalization, not
raw unframed JSON. Raw provider bodies and model text are retained unchanged.
Diagnostic replay lineage is authentic; it is not an accepted production execution
ledger, and no native production origin is fabricated.

## Results by independent measurement

| Measurement | Baseline | Candidate |
| --- | ---: | ---: |
| Physical calls completed | 38/38 | 38/38 |
| JSON/schema valid after existing normalization | 38/38 | 38/38 |
| Correct collection verdicts | 38/38 | 38/38 |
| Complete original-source citations | 36/38 | 38/38 |
| Relevant original-source citations | 38/38 | 38/38 |
| Adequate collection explanations | 38/38 | 38/38 |
| Native admitted assembled decisions | 26/26 | 26/26 |
| Correct admitted attribution | 26/26 | 26/26 |
| False attribution | 0 | 0 |
| Input tokens | 48,212 | 49,276 |
| Output tokens | 6,541 | 7,207 |
| Total actual tokens | 54,753 | 56,483 |
| Mean tokens per physical assessment | 1,440.87 | 1,486.39 |
| Mean tokens per assembled decision | 2,105.88 | 2,172.42 |
| Summed replay round-trip time | 34,158 ms | 36,950 ms |

Total accounted usage was **111,236 tokens**, below the frozen 300,000-token
experiment stop. Candidate tokens were **3.16% higher**, and summed round-trip
time was **8.17% higher**, with the same call count. Provider inference latency
was unavailable for every call; round-trip time includes debugger/transport work
and cannot be presented as provider inference latency. These measurements show a
small cost increase for better citation completeness, not a cost-saving claim.

The two failures were `unresolved-multiple-producers-baseline-1-1` and
`unresolved-multiple-producers-baseline-1-2`. Each correctly returned `lost` and
explained that both eight-hour cooling during power loss and the backup-failure
alarm were absent. Each cited only `chunk-1`, line 1, supporting cooling; neither
cited `chunk-2`, line 1, supporting the alarm. Native admission correctly accepted
the authorized coordinates and retained safe unresolved ownership. That is why
attribution remained correct while citation completeness failed separately.

Both matching candidate responses cited **both source spans**, retained the
correct `lost` verdict and explained both absent behaviors. Every other case
passed in both arms. The new smoke/exit control covered both required lines of
source 1 and omitted the unrelated calibration source. Joint obligations,
negation, recovery conditions and equal literals from different source occurrences
also passed. Relevant adjacent startup context was permitted under the frozen
criteria; no exact prose or citation-shape rule was imposed. No assessment dispute
or case-level regression remained.

## Qualification boundary and next step

The observed benefit is a citation improvement against the concurrent baseline
with unchanged judgment, explanation, admission and attribution quality. Twelve
known regressions, one new control, one model/settings pair and two repetitions
do not demonstrate general reliability across models or workflows. Fixed supplied
obligations do not establish whether the source reviewer selects faithful sources
or produces a complete `missing_obligation` in actual execution.

Next, obtain separate bounded approval for the prepared **30 actual source-review
calls**, including supported and genuine-information-gap controls. Preserve actual
admitted obligations/source selections unchanged and retain all rejected/no-answer
dispatches. Freeze and separately approve derived loss requests from those actual
receipts. E2E repair, publication and actual-output rubric qualification follow only
after that handoff passes. No successful isolated response substitutes for E2E.

Offline verification before dispatch passed **1,465/1,465 tests and 142/142 steps**,
including integration and clean packaging checks. After dispatch the current shared
native admission target passed **294/294 tests, 3/3 steps**, admitting all 52
complete decision receipts. Historical panels, thresholds and results were unchanged.
