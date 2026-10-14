# Entity-applicability guidance comparison

**Superseded preparation — 10 October 2026:** the review arms predate Phase 2's
required original-source premise for omissions. Their frozen schemas and hashes
are retained as historical preparation, not current production evidence. Do not
run the commands below as a current comparison. Prepare and freeze new paired
review requests using the production packet/schema before requesting approval;
do not silently replace one arm or reuse this manifest's hashes.

This is a prepared, **not run**, 32-call diagnostic using the existing request
debugger. It compares the shared decision purpose and field-purpose guidance;
it does not execute a workflow, repair a candidate or establish E2E success.
[comparison.json](comparison.json) freezes eight cases, paired edits, hashes,
model settings, proposed labels and trial order. Two unchanged repetitions use
opposite arm orders in the second round. No labels enter model requests.

| Case | Assigned work | Proposed assessment |
| --- | --- | --- |
| Captured startup | Author decision and basis | No entities; explain why greeting/UTC display needs none |
| Room temperature display | Author decision and basis | No entities; a displayed sensor value is insufficient |
| Equipment register | Author decision and basis | Entities required for identifiable, updateable equipment |
| Course enrolment | Author decision and basis | Learners, courses and their enrolment relationship required |
| Parking decision | Author decision or clarification | Ask the unresolved aggregate-versus-individual tracking choice |
| Review good | Review correct decision and meaningful basis | Supported, with no invented omission |
| Review irrelevant | Review correct decision and irrelevant basis | Identify inadequate explanation; behavior remains present |
| Review wrong | Review incorrect decision and fluent basis | Identify unjustified entity decision; fluency is insufficient |

The retained parents are calls 11 and 27 of
`2026-10-09T08-54-06Z-0efdbc7422d397f5c8192fe26ef96323`. Their debugger IDs are
`request-11-inference-1` and `request-26-inference-1`: display numbering is not
request identity. `captured-startup.baseline` preserves call 11's content/schema;
`review-irrelevant.baseline` preserves call 27's content/schema. The latter
retains the greeting-only basis and the complete surrounding business context.
The manifest distinguishes the checkout baseline revision from the historical
build identity, which reports a modified checkout.

Authoring candidates replace only the shared entity task description, shared
fragment guidance and the concise entity task prompt. Review candidates replace
only the shared task description; the source-review prompt is unchanged. Evidence,
literal catalogues and response schemas stay identical within each pair. The
controlled authoring cases have no exact literals and use the corresponding
production-selected schema. The wrong-decision review includes its unjustified
entities in a structurally consistent business context; both arms see those same
records. All eight cases are visible development cases, not blind holdouts.
This compares the requested guidance change as a whole, not the causal effect
of each individual sentence.

## Offline checks

```sh
zig build test-rubric-evaluator --summary all
```

The existing build entry point checks strict edit/manifest decoding, frozen
hashes, evidence equality, repeat identity, label isolation and production schema
selection. Candidate task text and prompts are checked for consistency across the frozen
requests; their hashes retain historical wording when production guidance changes.
Review subjects receive native structural validation. Exact-copy-only bases
remain schema-admissible where the literal catalogue permits them; this is not
an assertion that they explain anything. Unknown response fields remain rejected.
Production tests separately cover guidance across generation, correction, review
and existing authorized repair. No new semantic validator or repair permission
is introduced.

## Bounded dispatch procedure

Under [design §28.8](../../../design/contracts/28-testing.md#288-model-conformance-comparisons),
review the proposed labels and obtain explicit approval for **at most 32 physical
calls** before dispatch. The model is Bedrock `openai.gpt-oss-20b-1:0` in
`ap-southeast-2`, low reasoning, temperature 0, native schema. No retries,
corrections, repairs, model grading or extra calls are included. Unusable answers
consume their trial. Stop on transport uncertainty and inspect the saved debugger
record; never automatically repeat a send. An interrupted comparison is partial,
not permission to restart its trial count.

Build and prepare a fresh copy; these commands make no provider calls:

```sh
zig build
comparison="$PWD/test/calibration/entity-applicability"
engine="$PWD/zig-out/bin/sdde"
capture="$PWD/zig-out/e2e-spec/2026-10-09T08-54-06Z-0efdbc7422d397f5c8192fe26ef96323"
diagnostic=$(mktemp -d /tmp/sdde-entity-comparison.XXXXXX)
cp -R "$capture/project" "$diagnostic/project"
cp -R "$comparison" "$diagnostic/comparison"
mkdir "$diagnostic/results"
(cd "$diagnostic/project" && "$engine" --debugger hello-world)
```

Supply the dedicated test Bedrock credential to that debugger process through
its existing credential adapter; never print it or save it in the comparison.
Retain the copied project's original configuration/provider catalogue. Stop if
the capture or pinned binding is unavailable. The debugger's current provider
allowlist still applies. Opening it and reading `/api/calls` do not dispatch.

After approval, use the Replay tab or the existing loopback API for **one trial
at a time** in manifest order. For the API, set `origin` to the printed loopback
origin and `debugger_token` to its session URL fragment; these are debugger
session data, not provider credentials. From a second shell, set `diagnostic`
to the directory created above. The following prepares one selected trial:

```sh
comparison="$diagnostic/comparison"
trial='captured-startup-baseline-1'
curl --fail --silent --show-error \
  -H "x-sdde-debugger-token: $debugger_token" \
  "$origin/api/calls" > "$diagnostic/results/calls.json"
jq -e --arg trial "$trial" '.trials[] | select(.id == $trial)' \
  "$comparison/comparison.json" > "$diagnostic/results/selected.json"
case_id=$(jq -r '.case' "$diagnostic/results/selected.json")
phase=$(jq -r --arg case "$case_id" '.cases[] | select(.id == $case) | .phase' \
  "$comparison/comparison.json")
parent=$(jq -r --arg phase "$phase" '.capture[$phase].call' "$comparison/comparison.json")
run=$(jq -r '.capture.run' "$comparison/comparison.json")
index=$(jq -er --arg run "$run" --arg parent "$parent" \
  '[to_entries[] | select(.value.run == $run and .value.id == $parent)] | if length == 1 then .[0].key else error("parent unavailable") end' \
  "$diagnostic/results/calls.json")
edit=$(jq -r '.edit' "$diagnostic/results/selected.json")
jq -n --argjson call "$index" --slurpfile edit "$comparison/$edit" \
  '{call:$call,mode:"modified",edit:$edit[0]}' > "$diagnostic/results/$trial.request.json"
```

Before the first send, verify both parent descriptions against the manifest's
model/settings and both captured baseline edits, as well as context/edit/schema
hashes. Check that the selected parent is the original inference, not a replay.
Inspect the prepared request. This next command makes **one paid provider call**:

```sh
curl --fail-with-body --silent --show-error \
  -H "Origin: $origin" -H "x-sdde-debugger-token: $debugger_token" \
  -H 'Content-Type: application/json' \
  --data-binary "@$diagnostic/results/$trial.request.json" \
  "$origin/api/replay" > "$diagnostic/results/$trial.result.json"
```

Record the returned new call ID in the scorecard before selecting the next trial.
Never resend a trial ID, including after a failure. Both arms use modified replay
and the original parent, so they inherit the same provider settings and one-send
path. Preserve the manifest, edits and scorecard with `logs/debugger`, which owns
immutable serialized requests, raw responses and protocol/schema diagnostics.
Record complete request bytes, actual tokens, latency and failures. Stop after
32 sends or earlier if a required premise fails. No result enters workflow state.

## Separate meaning assessments

Copy [scorecard.template.json](scorecard.template.json) into the result directory.
Prefer assessment with arm names hidden until labels are applied; preserve
reviewer disagreement and reasons. Do not revise expected labels after seeing
answers to improve an arm's result. Each assessment needs the actual generated
value and source/candidate evidence, not merely a verdict tag or a keyword.

- **Decision accuracy:** `correct`, `incorrect`, `unassessable`. For authoring,
  assess the disposition separately from the basis; a correct disposition does
  not rescue an irrelevant explanation. For review, assess whether its detail
  correctly judges the supplied disposition. Returning `candidate_omission`
  alone never establishes accuracy.
- **Explanation quality:** `meaningful`, `partial`, `irrelevant`, `unsupported`,
  `unassessable`. For authoring, the basis must connect relevant requirements to
  the decision and explain why. For review, assess whether the finding correctly
  identifies the supplied basis's adequacy, independently of the decision. A
  fluent rationale for a wrong decision can still be unsupported.
- **Genuine gap handling:** `appropriate_clarification`, `false_clarification`,
  `missed_gap`, `no_gap_correctly_resolved`, `unassessable`. The parking case needs
  its unresolved tracking choice, not an invented answer. Complete cases need
  no declaration that entities are absent. Record `false_user_gap` separately.
- **Review defect detection:** `correct`, `partial`, `missed`, `invented`,
  `unassessable`, based on the diagnosis. The proposed finding tags are routing
  hypotheses, not semantic pass conditions. Adjudicate any defensible alternative
  interpretation with its rationale. The irrelevant-basis case needs a basis
  defect; the wrong-decision case needs an applicability defect.
- **False omission findings:** count each distinct allegation that source behavior
  represented in the supplied context was removed, with its quoted allegation
  and counterevidence. All three controlled review cases preserve the startup,
  greeting and UTC obligations. For the captured bad-basis case, alleging that
  `not_applicable` removes those obligations repeats call 27's defect, even if the
  response also identifies the weak basis or uses the expected finding tag.

Transport, JSON and schema admission are separate operational measures.
`native_admission` remains `not_assessed`: replay does not reconstruct the native
workflow's semantic validation, repair or authority reconciliation. Unusable
answers stay in the declared trials with unassessable semantics. Report per-case,
per-arm and per-repeat results, usable-answer counts, explicit denominators,
false omission counts, false gaps, unknown usage and total actual cost/latency
without combining these dimensions into one score.

No semantic improvement has been demonstrated by preparing these inputs or
passing offline checks. Two repeats can identify a diagnostic signal; they cannot
establish general reliability. Whole-workflow publication and actual-output
rubric evaluation remain separately approved E2E work. The shared purpose also
reaches authoring-role selection; these isolated diagnostics do not measure its
live selections or prove unchanged coverage earlier in the workflow.
