# One complete comparison per call

**Completed on 10 October 2026; the unchanged gate failed.** The user-approved
allowance covered 24 batched baseline calls and 36 isolated candidate calls and is
now consumed. No retries, corrections, repairs, model judges or E2E invocations
were included. See the [results](results.md) and [scorecard](scorecard.json):
correct labels improved from 22/24 to 24/24, but two candidate native rejections
left correct admitted attribution at 22/24 in each arm. The conditional production
split was not promoted.

The preceding [explicit-obligation comparison](../obligation/results.md) failed
its gate. Its current production packet is this experiment's **baseline**:
one explicit `missing_obligation` and all assigned comparison collections in one
call. The **candidate** presents one complete assigned comparison per call.
The hypothesis is that separating assigned collections reduces false absence
judgments when one collection lacks a standalone literal but still expresses the
complete obligation. This is a hypothesis, not an established cause or fix.

The only input change is which complete comparison is assigned to a physical
call. Keep its original comparison ID, every member and its order, the explicit
obligation, original sources, supporting producer and candidate context, guidance
and governing response contract unchanged. Do not split members, remove context,
rewrite obligations, renumber evidence or add comparison-specific instructions.
Reuse production packet/schema construction and the existing authenticated
request-debugger replay; introduce no independent provider adapter or prompt.

## Cohort, calls and controls

Reuse all twelve [obligation cases](../obligation/cases.json) and their semantic
expectations. They are now known regression cases. In particular, sterile-door,
voucher-release and dual-ready were already exercised; they are not fresh or
held-out qualification data in this experiment.

| Arm | Calls per repetition | Physical calls, two repetitions | Complete decisions to score |
| --- | ---: | ---: | ---: |
| Baseline: all assigned comparisons | 12 | 24 | 24 |
| Candidate: one whole comparison | 18 | 36 | 24 assembled decisions |
| Total | 30 | 60 | 48 |

The [manifest](comparison.json) must freeze request/resource hashes, settings,
counterbalanced order, response paths, call-to-trial associations, accounting
limits and acceptance criteria before dispatch. Compare actual
provider requests with the frozen bodies. No generated request is hand-edited.

Both arms use Bedrock `openai.gpt-oss-20b-1:0` in `ap-southeast-2`, low reasoning,
temperature 0, native schema and a 16,384-token output allowance; no seed or top-p
is supplied. Candidate call count is deliberately higher. Report total actual
input/output tokens and comparable latency per complete decision as well as per
physical call; lower error rates alone do not establish a cost improvement.

The spending stop is **300,000 accounted input-plus-output tokens**,
checked after every completed exchange. At or above that amount, send nothing
further; an in-flight completion can cross it. This is an experiment stop, not a
runtime reservation, provider ceiling or asserted dollar cap. Also stop on unknown
usage, uncertain dispatch/transport outcome, request/configuration/hash drift, or
60 physical sends. An uncertain send consumes an allowance and is never resent.
Restarting does not renew any allowance. These limits constrain the separately
approved 60-call comparison; they grant no additional sends or later experiments.

## Assembly and assessment

For each candidate case/repetition, retain every physical response and its
comparison ID, source/member selections, verdict, explanation, request identity,
origin, usage and timing in the experiment log. Aggregate only a complete set of
responses for the original native assignment. Assembly preserves the returned
assessments; it does not repair text, fill missing evidence, select a verdict or
invent one model origin for several calls. Submit the complete response through
the existing production native comparison admission and attribution owners.

Missing, duplicate, foreign, malformed or rejected pieces cannot become a
successful complete decision. One incomplete piece fails the entire assembled
trial. Retain partial responses for diagnosis without scoring a partial success.
The denominators remain 24 complete decisions per arm and 60 planned physical
calls, including failed and undispatched work. Report planned, dispatched and
completed calls separately from complete, schema-valid, natively admitted and
semantically correct decisions.

Freeze the [scorecard](scorecard.template.json) before viewing responses. Score
each verdict and its evidence independently of native admission, then the derived
owner and existing repair permission. Adequate evidence identifies the source
obligation and explains presence or absence in the complete assigned collection.
A missing standalone member does not establish missing meaning. Retain disputed
judgments; disclose unblinded manual assessment and do not change labels to favor
the candidate. Reviewers should explicitly inspect these controls:

| Control | Required semantic distinction |
| --- | --- |
| Captured description and captured story | The greeting behavior survives both upstream collections even without a standalone literal member. |
| Inherited extraction and wrong-role assignment | Genuine absence first arises at extraction or at the role's consumed collection; candidate repair is not a fallback. |
| Joint-two-sources and voucher-release | Several members can jointly preserve an obligation; payment alone does not preserve required manager approval. |
| Sterile-door | Staying locked under pressure preserves the prohibition against unlocking under pressure. |
| Dual-ready | The inspection/inspector obligation remains distinct from the payment/payer obligation despite identical literal bytes. |

## Unchanged gates and later work

Apply every existing gate to complete baseline or assembled candidate decisions,
not to individual candidate pieces. On the original eight-case/two-repeat subset,
require at least 15/16 complete, schema-valid and natively admitted decisions;
zero false upstream or candidate attributions; both correct extraction, signal,
role and unresolved results; at least 7/8 correct candidate-defect results;
at most one unnecessary uncertainty; adequate evidence on at least 14/16;
at least two more correct admitted attributions than concurrent baseline; and no
case-level regression. Both captured-story trials and all six trials from the
three previously fresh families must also complete, pass admission, have adequate
evidence and match their predeclared correct outcomes. Those six trials keep the
same gate without being presented as unseen data. A high baseline can make the
improvement gate inconclusive; do not lower it after execution.

A failed gate leaves semantic acceptance open and grants no additional calls or
automatic tuning loop. Passing would support only this tested experiment. Step 3
production implementation is conditional on passing and requires a coordinated
shared lifecycle change: native assignment partitioning, complete collection,
per-comparison origins, correction, accounting, revision checks, repair consumers
and persisted readback. Experiment-side aggregation is not a production fallback
or a second attribution policy.

Step 4 must still qualify the actual source-review → loss-review handoff using
later prepared, separately bounded live calls. This panel starts from fixed
admitted obligations and cannot prove that the source reviewer produces faithful,
complete obligations. Real review output must survive admission unchanged before
its loss assessments are scored. Production recovery, publication and rubric
acceptance remain separate E2E requirements and are not established by this
diagnostic experiment.
