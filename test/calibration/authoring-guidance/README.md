# Fragment and record-purpose guidance comparisons

These frozen diagnostic comparisons have a combined limit of **28 physical
calls**. The first approved batch completed; its [report and scorecard](../../../zig-out/authoring-guidance-comparison/2026-10-09T20-49-59Z-e95af2cbb164/report.md)
record all 28 responses. GWT preconditions improved in the tested startup and
buzzer cases; the captured exact-copy defect remains. The approval for that
batch is consumed; another dispatch requires a new bounded approval.

The comparisons use the existing request debugger, two arms and two unchanged
repetitions per case. They do not execute workflows. [comparison.json](comparison.json) freezes the requests,
source/schema/edit hashes, model settings, proposed labels and trial order.
[scorecard.template.json](scorecard.template.json) keeps operational admission,
semantic field purpose, obligation coverage and typed-reference use separate.

| Contrast | Case | Exact catalogue | Calls |
| --- | --- | --- | ---: |
| Fragment guidance only | Captured call 10: primary story | One greeting | 4 |
| Fragment guidance only | Captured call 12: records | One greeting; repeated use permitted | 4 |
| Fragment guidance only | Room temperature notification story | None | 4 |
| Fragment guidance only | Left/right panel status records | Three identities: `Ready`, `Ready`, `Busy` | 4 |
| Record purposes and collection guidance only | Captured call 12: startup records | One greeting | 4 |
| Record purposes and collection guidance only | Push-button buzzer records | None | 4 |
| Record purposes and collection guidance only | Chamber cleaning records | None; legitimate prerequisite obligation | 4 |

The fragment contrast changes only `generation.context.json`'s `exact_copy`
guidance. The source assignment, task prompt, field-purpose definitions, evidence
and schema remain identical within each pair. The record-purpose contrast changes
only the acceptance-criterion field descriptions in the shared purpose and the
record prompt's collection-coverage sentence. It retains the baseline fragment
guidance, evidence, sibling-family definitions and schema. These are separate
controlled contrasts; they do **not** measure the interaction of both changes in
the combined production candidate. That remains subsequent, separately approved
whole-workflow E2E work with published-output evaluation.

The baseline parents are calls 10 and 12 of
`2026-10-09T20-25-01Z-114a71784dee27afd412beda5af561dd`, identified in the manifest
by run and request IDs. Both captured baseline edits preserve the corresponding
content and selected schema exactly. The captured build identity is recorded
separately from the checkout revision and reports a modified checkout. Controlled
cases are manually prepared diagnostic inputs, not upstream-generation claims.
All cases are visible development cases, not holdouts. Repetition two reverses
arm order; labels and assessment notes never enter the requests.

The panel case distinguishes equal literal bytes by claim and source identity:
claim 4/source 1 is the left panel's `Ready`; claim 5/source 2 is the right panel's
`Ready`; claim 6/source 3 is `Busy` when a check cannot complete. Repeated use of
one reference across records is legitimate. A `then` field containing only the
status reference can be meaningful when its criterion already identifies the
panel check and resulting status. Do not demand added prose merely because the
field has one reference fragment. If generated context does not determine the
source occurrence, mark its identity unassessable rather than choosing one.

The chamber case requires closing and locking the door, starting only while
closed and locked, and unlocking after cleaning. A closed/locked prerequisite is
legitimate for the start criterion. The collection must also preserve the
obligation to produce that state as an observable result. Replacing every
obligation-shaped prerequisite with an outcome would be a regression.

## Offline verification

```sh
zig build test-rubric-evaluator --summary all
```

The existing build entry point checks closed edit/manifest decoding, hashes,
unchanged repeats, factor isolation, source/occurrence identities, label isolation
and equality with the production compiler's selected zero/singleton/multiple
reference schemas. Reference-only results remain schema-admissible. Historical
record and entity comparisons retain their frozen guidance and hashes when the
current production wording changes; their tests still check the original paired
changes and family membership. Production tests separately prove shared guidance
propagation and existing native validation. None of these checks judges meaning
or makes a provider call.

## Bounded live procedure

Review the frozen labels and obtain explicit bounded approval before dispatch,
as required by [design §28.8](../../../design/contracts/28-testing.md#288-model-conformance-comparisons).
Approval would cover at most **28 calls**: 16 fragment trials and 12 record-purpose
trials. No retry, correction, repair, model judge or replacement call is included.
The fixed binding is Bedrock `openai.gpt-oss-20b-1:0`, `ap-southeast-2`, low reasoning,
temperature 0, native schema. Stop if the retained capture or binding differs.

Build and copy the retained project so original logs remain immutable. These
commands do not call a model:

```sh
zig build
comparison="$PWD/test/calibration/authoring-guidance"
engine="$PWD/zig-out/bin/sdde"
capture="$PWD/zig-out/e2e-spec/2026-10-09T20-25-01Z-114a71784dee27afd412beda5af561dd"
diagnostic=$(mktemp -d /tmp/sdde-authoring-comparison.XXXXXX)
cp -R "$capture/project" "$diagnostic/project"
cp -R "$comparison" "$diagnostic/comparison"
mkdir "$diagnostic/results"
(cd "$diagnostic/project" && "$engine" --debugger hello-world)
```

Supply the dedicated test credential through the debugger's existing credential
adapter without printing or persisting it. Preserve the copied configuration and
provider catalogue. The current provider allowlist remains authoritative. Opening
the debugger and reading its call list do not send a model request.

After approval, use the Replay tab or the loopback API for one manifest trial at
a time. In a second shell, set `diagnostic` to the copied directory, `origin` to
the printed loopback origin and `debugger_token` to the session URL fragment.
Select the next manifest trial ID and prepare its request:

```sh
comparison="$diagnostic/comparison"
trial='fragments-captured-story-baseline-1'
curl --fail --silent --show-error \
  -H "x-sdde-debugger-token: $debugger_token" \
  "$origin/api/calls" > "$diagnostic/results/calls.json"
jq -e --arg trial "$trial" '.trials[] | select(.id == $trial)' \
  "$comparison/comparison.json" > "$diagnostic/results/selected.json"
case_id=$(jq -r '.case' "$diagnostic/results/selected.json")
parent_kind=$(jq -r --arg case "$case_id" '.cases[] | select(.id == $case) | .parent' \
  "$comparison/comparison.json")
parent=$(jq -r --arg parent "$parent_kind" '.capture[$parent].call' \
  "$comparison/comparison.json")
run=$(jq -r '.capture.run' "$comparison/comparison.json")
index=$(jq -er --arg run "$run" --arg parent "$parent" \
  '[to_entries[] | select(.value.run == $run and .value.id == $parent)] | if length == 1 then .[0].key else error("parent unavailable") end' \
  "$diagnostic/results/calls.json")
edit=$(jq -r '.edit' "$diagnostic/results/selected.json")
jq -n --argjson call "$index" --slurpfile edit "$comparison/$edit" \
  '{call:$call,mode:"modified",edit:$edit[0]}' > "$diagnostic/results/$trial.request.json"
```

Before dispatch, verify parent content/schema and model/settings against the
frozen captures and check manifest/edit/schema hashes. Inspect the prepared
request. Select the original inference parent by run/request identity, never a
previous replay or a display number. Both arms use the same modified-replay path.
The next command sends **one paid provider request**:

```sh
curl --fail-with-body --silent --show-error \
  -H "Origin: $origin" -H "x-sdde-debugger-token: $debugger_token" \
  -H 'Content-Type: application/json' \
  --data-binary "@$diagnostic/results/$trial.request.json" \
  "$origin/api/replay" > "$diagnostic/results/$trial.result.json"
```

Record its new call ID in the scorecard before selecting the next trial. Never
resend a trial ID. Failed/empty answers consume their trial; uncertain transport
requires inspecting the saved diagnostic record before doing further work, not
retrying. Stop after 28 sends or earlier if a premise fails. An interrupted run
is partial and does not reset the approved count. Preserve manifests, edits,
scorecards and `logs/debugger`'s immutable requests, raw responses and diagnostics.
Record complete request bytes, actual tokens, latency and errors. Replays cannot
publish artifacts or change workflow authority.

## Independent assessment

Assess the actual generated values, preferably with arm labels hidden, then
record reasons and source/output evidence in the scorecard. Preserve disagreement
and any adjudication. Do not change labels after seeing an arm's output to make
it win. Schema success, string length and matching keywords are not semantic
judges. Report these dimensions independently for each contrast:

- **Field purpose:** for every emitted field, record its record family/path,
  resolved value and `fulfilled`, `partial`, `not_fulfilled` or `unassessable`.
  Distinguish starting situation, trigger and observable consequence. A legitimate
  prerequisite can appear in `given`; a tested result cannot become an assumed
  success merely to avoid expressing it. Assess story meaning as a narrative.
- **Collection obligations:** assess every manifest obligation across the whole
  story/record collection as `preserved`, `partial`, `prerequisite_only`, `omitted`,
  `contradicted` or `unassessable`, citing its field locations. `prerequisite_only`
  means the required behavior is only assumed, with no observable obligation
  elsewhere; it does not count as preservation. Record mandatory-family coverage,
  invented prerequisites and false user gaps separately.
- **Typed literal occurrences:** inventory every generated occurrence of an exact
  value and its surrounding meaning. Record field/path, raw fragment, resolved
  bytes, typed claim/source identity, and `typed_correct`, `raw_prose`,
  `wrong_identity`, `altered`, `omitted` or `unassessable`, with evidence. Use the
  catalogue and field context to distinguish duplicate bytes; repetition does
  not create a new identity. Correct rendering and typed representation are
  separate: raw prose can preserve meaning while failing typed reference use,
  and a typed reference can still sit in the wrong semantic field. Summarize each
  expected literal's coverage without requiring a fixed number of repetitions.

A literal-only field may pass field-purpose assessment; there is no universal
prose-fragment rule. For the zero-literal cases, the exact-reference denominator
is zero, not a perfect score. Count operational failures among the declared 28
trials and mark their semantics unassessable. Report usable-answer counts and
explicit denominators alongside each dimension and each case/arm/repetition;
unknown usage remains unknown. No composite score hides losses in other dimensions.

`native_admission` remains `not_assessed` for replay: the debugger decodes and
checks the response schema but does not execute the native generation graph,
semantic validators or workflow repairs. Two repetitions can reveal a diagnostic
signal; they cannot prove reliability. Preparation and offline success establish
no live improvement. Combined-candidate E2E publication and actual-output grading
remain separate work requiring their own approval.
