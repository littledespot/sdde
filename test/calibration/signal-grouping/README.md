# Signal-grouping input comparison

This is a prepared **12-call diagnostic**, not integration or E2E execution.
It uses the existing request debugger and `application/request_replay.zig`;
there is no new runner, retry policy, provider adapter or semantic validator.
No live trial has been run. [comparison.json](comparison.json) pins the request
edits, settings, proposed labels and order. Obtain explicit bounded approval
under [§28.8](../../../design/contracts/28-testing.md#288-model-conformance-comparisons)
before dispatch.

| Premise | Purpose | Trials |
| --- | --- | ---: |
| Captured startup, greeting and UTC | Reproduce call 6's token-evidence scope and repetition failure | 4 |
| Prescription renewal | Unrelated business/technical categories and an exact status label | 4 |
| Irrigation coverage | Unrelated conditions, existing signal coverage and legitimate overlap | 4 |

Each premise has baseline and candidate arms, repeated twice unchanged; the
second round reverses arm order. The captured baseline is the exact content and
schema retained from call 6 in run
`2026-10-09T08-25-10Z-0aa73527d76068ef6d1484ca7b764d1d`. The recorded revision
identifies the pre-change repository; the captured run used a dirty build and
is independently identified by its context hash.

The controlled premises are declared diagnostic facts, not evidence that an
upstream live workflow produced them. All cases are visible development cases;
none is a blind holdout. Labels remain proposed until reviewed and never enter
model requests. These are live-comparison inputs, not scripted provider responses.

Within each pair, claims, citations, token evidence, summaries, dispositions,
accepted signals and eligible IDs are identical. The treatment is the complete
proposed input contract: signal prompt, scoped constraint presentation, eligible
content variants and derived membership cardinality. Uniqueness is explicit in
guidance and remains native admission policy: the closed schema profile does not
support `uniqueItems`. Complete schema guidance and native schema admission carry
`maxItems`; the existing Bedrock structural projection omits that keyword. These
restrictions must not be described as preventing provider repetition. This tests that
bundle; it does not isolate the causal contribution of an individual change.
Both arms retain native token ownership and the same single-call boundary.
Frozen schemas are evidence, not a second runtime authority.

## Offline checks

```sh
zig build test-rubric-evaluator --summary all
```

Tests check closed edits, frozen hashes, invariant facts, exact repeats, label
isolation, the production prompt/constraint owner and production schema
projection. They make no external calls and do not judge authored meaning.
The production tests separately check complete native admission, correction,
repair and assembly of native token signals.

## Bounded live procedure

Use the existing request-debugger procedure described in
[record-authoring](../record-authoring/README.md#bounded-live-procedure), with
this manifest, its retained parent run and **request-6-inference-1**. Resolve
the parent's index from `/api/calls`; physical call 6 is not an API index.
Select that original parent for every trial. Both arms use modified replay with
the complete edit file, inherited model/settings and immutable ancestry.

1. Review the premises and freeze a copy of the manifest with the results.
   Verify every edit/schema hash, captured parent content/schema and settings.
   Stop if the captured parent or pinned settings are unavailable or differ.
2. Build with `zig build`, copy the captured project to a fresh diagnostic
   directory, and open the existing debugger there. Preserve the original
   configuration/binding and logs. Use only the dedicated test credential;
   never print or persist it.
3. After approval for these 12 sends, submit the edits in manifest order through
   `/api/replay`, using the session's Origin and debugger-token protections.
   Retain each call ID, serialized request, raw response, admission result,
   actual token usage and latency. Stop after 12 physical calls.

There are no correction, repair, judge or replacement calls in this allowance.
An empty, failed or truncated answer consumes its trial. Additional calls and
whole-workflow E2E require their own bounded approvals. Replayed answers cannot
be imported as workflow authority or substituted for published-output grading.

## Assessment

Copy [scorecard.template.json](scorecard.template.json) beside the results and
assess responses with arm names hidden where practical. Keep these dimensions
separate, with evidence and reasons rather than a composite pass score:

- **Completion/protocol:** provider completion, repetition/truncation, JSON and
  schema admission. An operational failure is not a semantic success.
- **Membership:** IDs outside `assignment.claim_ids`, duplicate IDs within a
  signal, repeated complete member sets (including accepted signals), and
  uncovered retained semantic claims. Attaching an ID does not prove meaning.
- **Category:** content's category must match every selected claim; unrelated
  categories cannot be merged into one signal. Assess through supplied facts,
  not keywords in the authored text.
- **Meaning:** for every source obligation, assess the assembled accepted and
  new semantic signals as preserved, partial, omitted, contradicted or
  unassessable. Record changed triggers, conditions, obligation strength and
  unsupported additions. There is no expected sentence or fixed group count.
- **Exact evidence:** assess the status/greeting meaning and any reproduced
  literal bytes. The model must not select token-only claims; native code adds
  those signals. The token-free case has a zero denominator, not a perfect score.

For irrigation, claims 1 and 2 already have an accepted signal. Claim 3 still
needs coverage. A new `[3]` signal or a meaningful overlapping `[2,3]` signal can
both be valid; repeating the accepted `[1,2]` set is not. Do not reward overlap
or force a partition. Inspect meaning across the assembled collection.

The debugger checks JSON/schema admission; it does not reconstruct and validate
the native reconciliation graph. Keep `native_signal_admission` as
`not_assessed` for these replays, even if a human sees plausible membership.
Native admission is proven separately offline and subsequently by live E2E.

Report each case/arm/repeat, all 12 declared attempts, admitted-answer counts
and semantic denominators. Failed trials are unassessable, not successful zeros.
Preserve assessment disagreements; do not change labels after observing outputs.
Two repeats can identify regressions but do not establish reliable production
improvement. Actual E2E publication and rubric quality remain separate evidence.
