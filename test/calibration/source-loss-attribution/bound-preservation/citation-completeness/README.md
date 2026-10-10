# Citation completeness comparison and actual reviewer handoff

**Citation comparison passed; actual source-review handoff failed.** All
76 explicitly approved calls completed; complete/relevant citations improved from
36/38 to 38/38 assessments, with 38/38 correct verdicts and 26/26 correct native
attributions in both arms. [Results](results.md) and [scorecard](scorecard.json)
retain the independent measurements and qualification limits. The allowance is
consumed. The separately approved **30/30** actual-review calls also completed:
only **15/26** faithful omission handoffs, **2/2** supported controls and **0/2**
genuine-gap controls. See [handoff results](handoff-results.md) and its
[scorecard](handoff-scorecard.json). Its allowance is consumed; failed semantic
qualification blocks downstream loss dispatch and E2E. No such calls ran.
The preceding
[native-scope comparison](../native-scope/results.md) improved admission, but its
second unresolved-ownership candidate answer omitted the alarm source despite a
correct loss verdict and explanation. This experiment asks whether shared source
purpose guidance improves complete, relevant citations without changing meaning,
admission or attribution. It does not repeat the earlier response-contract study.

The [manifest](comparison.json) and [scorecard template](scorecard.template.json)
declare both arms, settings, order, denominator and gates before execution.
Historical panels, results and gates remain unchanged.

## One changed factor

Reuse the twelve [canonical cases](../obligation/cases.json). Their baseline files
are byte-identical to native-scope's candidate edit/provider requests. The
[frozen baseline prompt](baseline.prompt.md) has SHA256
`79348d80c19922afe03ef3c9333a2d323410aabfe15db3b2e759f5a400061859`.
The candidate uses the current production loss packet, closed schema and
`support-loss.prompt.md`, which explains that source spans collectively support
the entire supplied obligation, including conditions, negation and obligation
strength; several necessary spans may be cited and unrelated spans omitted.

Both arms use the same native-owned collection response contract: comparison ID,
verdict, source spans and explanation; no returned member selection. Every
request includes the same explicit obligation, original sources, one complete
assigned collection and supporting context. Business-input bytes, projected
schema bytes, model and all controls are identical between its arms. Isolation is
a diagnostic projection; production still assesses its full assignment in one
call. The model's labels and citations remain untrusted candidate data.

One [new control](citation.controls.json) supplies an alarm-on-smoke requirement
and an unlocked exit while smoke persists across two lines of source 1. Source 2
supplies an unrelated calibration-log requirement. Full obligation support needs
both lines from source 1; citing every offered source would fail relevance. The
retained cohort additionally covers the missing alarm citation, joint source
support, obligation strength, negation, until-recovery conditions, unrelated lines,
identical literals from different source occurrences and unresolved ownership.
New control data is separate; no retained case authority was copied.

| Panel | Cases | Collections per repetition | Arms | Repetitions | Physical sends |
| --- | ---: | ---: | ---: | ---: | ---: |
| Citation purpose | 13 | 19 | 2 | 2 | 76 |
| Actual source review, separate conditional approval | 15 | 15 | 1 | 2 | 30 |

The citation panel has 38 physical assessments and 26 complete attribution
decisions per arm, 52 decisions overall. Twelve cases are known regressions;
only the new compound/irrelevant-source control is new qualification data.

Both panels use AWS Bedrock `openai.gpt-oss-20b-1:0` in `ap-southeast-2`, low
reasoning, temperature 0, native schema and 16,384 output tokens. Neither seed nor
top-p is supplied. There are no retries, corrections, repairs, additional model
judges or whole-workflow E2E calls. Payloads include synthetic/captured
requirements, derived evidence, non-public project guidance and JSON schemas.

Stop the citation panel after 76 sends or 300,000 accounted input-plus-output
tokens; the separately approved review panel stops after 30 sends or 200,000
tokens. Check actual usage after each exchange. Unknown usage, uncertain
dispatch/transport or any body/config/hash drift stops the panel without resend.
One in-flight completion may cross its spending stop. Restarting renews no
allowance; these are experiment stops, not runtime/provider token ceilings.

## Admission, separate measurements and gates

The same current native owner admits both arms. Retain every actual provider
request, raw response, model answer, validation result, origin and cost. Each
isolated receipt binds its original comparison ID, full current assignment,
case/arm/repetition, authentic replay response ID and frozen request hash. Only a
complete set reaches full native attribution. No member IDs, verdicts, citations
or explanations are filled in. Missing, duplicate, foreign or stale evidence
remains rejected. Planned, sent, completed and rejected denominators stay visible.

Score these independently, per physical assessment and complete decision:

- Collection verdict accuracy, including preserved meaning, genuine loss and
  uncertain or unresolved ownership.
- Citation **completeness**: the union of that assessment's spans supports the
  whole supplied obligation, including joint requirements and conditions.
- Citation **relevance**: cited content supports the target, rather than padding
  the answer with all available sources or borrowing a same-text occurrence.
- Explanation adequacy: explains preservation or loss in the assigned complete
  collection; source support alone cannot establish collection preservation.
- Initial JSON/schema and native admission, derived attribution, false ownership,
  and actual calls, input/output tokens and latency.

The new candidate must complete and admit all 26 decisions, give all 38 correct
verdicts, provide complete/relevant citations and adequate explanations for all
38 physical assessments, and derive all 26 correct attributions. Both captured
alarm repetitions must cite cooling and alarm support. No false ownership or
case-level regression is allowed. The manifest supplies source/line expectations
for manual assessment only; they are never sent as model answers or interpreted
by the generic engine as semantic proof. Prefer independent reviewers and retain
disputes; assessment is unblinded and model-assisted semantics are not proof.

Report citation benefit against the **concurrent same-contract baseline**. If
both arms are perfect, the result establishes nonregression in this panel, not
superiority. The historical requirement for two additional admitted attributions
tested removing returned members; it remains in its historical panel and does
not apply to this new citation-purpose hypothesis. Historical assembled citation
scoring remains unchanged. This new study predeclares completeness separately
for every isolated assessment, including a lost collection: a sibling's citation
cannot silently supply its missing support.

Cost requires known actual usage and compliance with the spending stop. Report
per-assessment/per-decision totals and paired ratios; no estimated-dollar cap or
unmeasured efficiency claim applies. A failed safety/citation gate does not
authorize retries, semantic promotion, reviewer-handoff qualification or E2E.

## Offline preparation and controlled launch

The existing fixture owner constructs packets and restricted schemas through
production owners, then compares its exports with the frozen files:

```sh
zig build test-specification-generation --summary all -j2
zig build verify --summary all -j2
git diff --check
```

The first command also admits new receipts placed in
`.zig-cache/source-loss-citation-completeness`, writing each arm's native report.
Its mock probes prove construction, exact bindings, origin separation, stale and
foreign rejection, and complete-only aggregation. They establish no live
semantic quality, successful recovery or publication.

There is no new engine command or alternate dispatch path. Launch approved trials
through the existing authenticated request debugger, using a private copy of the
retained project and current workflow assets. The native entry point is
`zig-out/bin/sdde --debugger hello-world`, run from that private project copy.
Keep credentials and the printed loopback session token private. The existing
API/retained replay orchestration does this:

1. Verify every manifest pin and empty trial/receipt destinations; bootstrap the
   debugger without running a workflow or inference call.
2. `GET /api/calls`; select **exactly one** record whose `run` and `id` equal the
   panel's pinned parent. Retain its index, actual linked source call and settings.
   The citation parent is `request-16-inference-1`; the source-review parent is
   `request-15-inference-1`, both in the manifest's retained run.
3. For each ordered frozen trial, journal the physical dispatch first, then
   `POST /api/replay` with `{ "call": <that integer index>, "mode": "modified",
   "edit": <the complete frozen edit.json object> }`. Authenticate with the
   existing `x-sdde-debugger-token` and exact loopback `Origin` headers.
4. Identify the single newly linked call, verify its parent, content/schema and
   **actual serialized provider bytes** against the pinned request. Retain all
   outputs, failures and actual usage; enforce stops before the next send.
5. Construct receipts from actual answers and identities, then invoke the first
   offline command for native admission. Score the frozen metrics independently.

`scripts/e2e-call.sh` preserves captured content/schema and exposes no edit-file
option; it cannot launch these modified frozen arms. Do not invent such a flag.
The retained replay recipe uses the existing debugger API; adapt its manifest
selection and both-current-owner aggregation, then review its preflight and exact
approval bounds before dispatch. Neither README nor manifests grant permission.

## Actual source-review handoff, after citation qualification

**Executed and failed its frozen semantic gates.** The following receipt and
launch descriptions record the prepared mechanics; they do not renew the consumed
30-call approval. New work must address shared review direction and assigned
coverage, rather than substituting fixed obligations into failed responses.

The separate [handoff plan](handoff.preparation.json) proposes 30 review calls:
the thirteen omission cases, a supported maintenance-locking case and a genuinely
unselected release policy, each twice. It pins the authentic captured source
review parent and generated requests. Oracle obligations are scoring data only;
they are absent from these actual review assignments.

Save a review receipt for every received trial:

```json
{
  "input": "the exact frozen source-review user-input string",
  "origin": {
    "trial_id": "case-review-1",
    "parent_run": "the pinned source-review run",
    "parent_call": "the pinned source-review call",
    "replay_run": "actual debugger run",
    "replay_id": "actual linked replay call/response ID",
    "request_sha256": "hash of actual provider request bytes",
    "response_sha256": "hash of exact response_bytes"
  },
  "response_bytes": "the actual captured model text bytes"
}
```

`response_bytes` is the existing replay inspector's `validation.model_text`
(`request_replay.zig`), after Bedrock response/reasoning framing extraction. Keep
the raw provider response separately. Do not take raw `choices.message.content`
or reserialize `validation.parsed` into a replacement answer. If extraction fails
or model text is absent, retain that physical dispatch, raw response and
validation failure in the denominator; no receipt is invented and native
admission is reported as not reached. Invalid JSON/schema replies likewise
remain failures even where their model text can be retained for diagnostics.

The fixture rejects unknown receipt fields, changed canonical input, request or
response hash, foreign parent, wrong case/repetition and blank replay identity.
It reuses the existing model-envelope parser, retaining raw model text/hash and
any approved prefix normalization, then calls existing source-review admission
with the parser's unmodified JSON remainder. No parsed value or citation is
filled or rewritten.
Receipt rejection and model decoding/admission diagnostics remain reportable;
operational allocation failure is propagated. Bare response filenames no longer
cause a handoff or downstream admission.

The external execution journal must verify authentic parent/replay linkage,
provider bytes, response hashes and globally unique replay identities against the
actual debugger archive. Local receipt checks bind observations to the frozen
plan and current input; they do not independently authenticate an archive or make
model findings authoritative.

Authentic diagnostic replay lineage is an observation, not a forged production
`model_candidate_origin.Origin`. The replay archive lacks the accepted execution
ledger needed to derive a new native origin, so reports explicitly set
`native_origin_available: false`. Do not borrow the captured parent's native
origin or convert replay sequence numbers into request ordinals. Production unit
tests separately exercise genuine native-origin propagation; this diagnostic
limitation remains disclosed.

For an admitted omission, native construction retains the exact admitted
`missing_obligation` and source IDs and rebuilds the full current comparison
assignment. Checks compare both values with the actual downstream wire obligation
and offered source catalogue. Reports retain that assignment and source-review
receipt lineage. Supported/gap findings generate no loss packet. No prior
fixed-obligation answer is imported as an actual handoff finding.

The source-review gate requires all 26 faithful omission findings, both supported
and both genuine-gap controls, no false control omission, unchanged admitted
obligations/source selections, and retained schema/native rejection denominators.
Check triggers, conditions, negation, strength and unsupported additions
semantically, rather than treating JSON or citations as faithfulness.

**Downstream live loss requests are not yet frozen or approved.** Derive them only
after real review admission and handoff assessment. Freeze their actual changed
obligations, assignments, requests, settings and origin chain, then seek approval
for that exact count. The fixture exports such candidate packets but never
implicitly consumes bare downstream responses. Recovery, publication and actual
output rubric quality require subsequent separately approved whole-workflow E2E.
