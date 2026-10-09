# One composition example for story authoring

This comparison **completed all 16 explicitly approved diagnostic calls** on
10 October 2026: four story cases, baseline/candidate arms and two unchanged
repetitions. It tested one format example before changing production guidance.
The approval is consumed; another comparison requires a new bounded approval under
[design §28.8](../../../../design/contracts/28-testing.md#288-model-conformance-comparisons).
There were no retries, corrections, repairs, additional model judges or E2E runs.

**Decision: withhold production promotion.** Correct in-place reference
composition improved from baseline **0/6** to candidate **6/6** literal-bearing
answers. All listed candidate obligations survived, but the startup candidate
added an unstated greeting-before-time sequence. Its second repeat introduced
that sequencing relative to its paired baseline. The frozen no-regression gate
is therefore not established; uncertain materiality is not a pass. See
[results](#results) below. Production guidance remains unchanged by this experiment.

[comparison.json](comparison.json) uses the existing manifest contract with the
`composition_example` contrast. It freezes source/schema/edit hashes, proposed
labels, parent identity, model settings and trial order. The second repetition
reverses arm order. [scorecard.template.json](scorecard.template.json) starts with
all trials `not_run`; labels and assessment notes never enter a request.

| Case | Offered exact occurrences | Intended check | Calls |
| --- | --- | --- | ---: |
| Captured call 10 startup story | One greeting | Compose the reference inside the narrative instead of appending it after raw greeting text | 4 |
| Airflow pause story | One `Paused` occurrence | Preserve pause, fan stop, status duration and resumption in an unrelated domain | 4 |
| Room notification story | None | Identical-arm control: no example and no invented references | 4 |
| North/south valve story | Distinct `Closed` occurrences plus `Unknown` | Preserve source identity, repeated legitimate use and both display contexts | 4 |

All requests replay the captured call-10 parent
`request-10-inference-1` from run `RUN-30bf52923e1410d76f70edf8b9c1e06d`, captured
in `2026-10-09T20-25-01Z-114a71784dee27afd412beda5af561dd`. The retained manifest
also carries the unused call-12 capture metadata to preserve its existing shape;
**no trial selects that parent**. The baseline uses the current shared fragment
guidance and generic story prompt/purpose. The captured startup case preserves
call 10's evidence and selected schema, but its baseline guidance is the current
wording, not the original historical wording. Controlled sources are explicitly
labelled and are not claims about upstream production. These are visible
development cases, not holdouts.

## Exactly one changed input

The candidate adds one top-level `composition_example` member to the **dynamic
user packet** when an exact literal is eligible. Static guidance, task prompt,
purpose, requirements, literal catalogue and response-schema bytes are unchanged
within each pair. No production input owner changes in this experiment. With no
eligible literal, the member is omitted and both edit files are byte-identical.

The member has this shape, populated from the offered occurrence and the selected
schema rather than from a fixed greeting or ID:

```json
{
  "instruction": "Formatting illustration only; write the assigned narrative from requirements.",
  "value": ["The displayed value is \"", {"kind": "exact_copy"}, "\"."],
  "rendered_text": "The displayed value is \"<actual offered literal>\"."
}
```

The frozen files contain the actual literal, never the placeholder shown above.
For singleton eligibility the object omits `claim_id`, as required by the selected
schema. For multiple occurrences it includes the first offered occurrence's
`claim_id`. Selecting the first offered occurrence makes the illustration
repeatable; it supplies no source priority, behavior recommendation or authority
for other occurrences. There is one example, with the same format in every case,
not a catalogue of case-specific answers. Its sentence is formatting data and
must not become an invented source requirement or substitute for the narrative.

In the valve case, claim 201/source 11 is the north valve's `Closed`, claim
202/source 12 is the south valve's `Closed`, and claim 203/source 13 is `Unknown`
when a test cannot confirm position. Both confirmed statuses are required in
the latest-test banner and their respective persistent status displays. Reusing
one occurrence reference is legitimate. A narrative can cover both displays in
one clause or repeat a reference when appropriate; no fixed textual repetition
count is required. Equal bytes do not make the two source occurrences equivalent.
When output context does not identify an occurrence, assessment must retain that
ambiguity rather than guessing.

## Offline verification

Use the existing build entry point:

```sh
zig build test-rubric-evaluator --summary all
```

The comparison checks retain hashes, paired evidence/schema equality, unchanged
repetitions and the identical zero-eligibility control. Example fragments are
checked against the production selected schema and singleton construction, using
the existing typed-text decoder and checking that the displayed example matches
its selected literal and surrounding strings. These are structural and
representation checks; they do not establish useful generated narratives. The
native example check does not turn a live replay's generated answer into native
workflow admission. Shared production guidance remains unchanged by these assets.

## Bounded replay procedure

This is the retained procedure for the completed comparison. Its 16-call
allowance is consumed; the commands do not authorize another invocation.

After reviewing the frozen labels, obtain approval for **at most 16 physical
calls** before dispatch. Fix Bedrock `openai.gpt-oss-20b-1:0`, `ap-southeast-2`, low
reasoning, temperature 0 and native schema. The existing debugger retains one
send per trial; no retry, replacement, correction, repair or model judge is part
of the proposed count. Failed/empty answers consume a trial. Stop on uncertain
transport without resending, and retain the partial comparison if interrupted.

Prepare a new copy of the captured project and this comparison. Building and
opening the debugger do not send a model request:

```sh
zig build
comparison="$PWD/test/calibration/authoring-guidance/composition-example"
engine="$PWD/zig-out/bin/sdde"
capture="$PWD/zig-out/e2e-spec/2026-10-09T20-25-01Z-114a71784dee27afd412beda5af561dd"
diagnostic=$(mktemp -d /tmp/sdde-composition-example.XXXXXX)
cp -R "$capture/project" "$diagnostic/project"
cp -R "$comparison" "$diagnostic/comparison"
mkdir "$diagnostic/results"
(cd "$diagnostic/project" && "$engine" --debugger hello-world)
```

Supply the dedicated test credential through the existing credential adapter
without printing or saving it. Retain original configuration and provider assets;
the current allowlist remains authoritative. Check the original parent capture,
model/settings and all hashes before the first send. The historical context hash
identifies the original capture; compare its evidence/schema with the captured
case while accounting for the explicitly updated baseline guidance.

After approval, use the Replay tab or prepare one manifest trial through the
existing loopback API. In a second shell, set `diagnostic` to the copied directory,
`origin` to the printed loopback origin and `debugger_token` to the session URL
fragment. Select the next trial in manifest order:

```sh
comparison="$diagnostic/comparison"
trial='captured-startup-baseline-1'
curl --fail --silent --show-error \
  -H "x-sdde-debugger-token: $debugger_token" \
  "$origin/api/calls" > "$diagnostic/results/calls.json"
jq -e --arg trial "$trial" '.trials[] | select(.id == $trial)' \
  "$comparison/comparison.json" > "$diagnostic/results/selected.json"
parent=$(jq -r '.capture.story.call' "$comparison/comparison.json")
run=$(jq -r '.capture.run' "$comparison/comparison.json")
index=$(jq -er --arg run "$run" --arg parent "$parent" \
  '[to_entries[] | select(.value.run == $run and .value.id == $parent)] | if length == 1 then .[0].key else error("parent unavailable") end' \
  "$diagnostic/results/calls.json")
edit=$(jq -r '.edit' "$diagnostic/results/selected.json")
jq -n --argjson call "$index" --slurpfile edit "$comparison/$edit" \
  '{call:$call,mode:"modified",edit:$edit[0]}' > "$diagnostic/results/$trial.request.json"
```

Inspect the prepared request. Both arms select the original inference parent by
run/request identity and use modified replay. The next command makes **one paid
provider call**:

```sh
curl --fail-with-body --silent --show-error \
  -H "Origin: $origin" -H "x-sdde-debugger-token: $debugger_token" \
  -H 'Content-Type: application/json' \
  --data-binary "@$diagnostic/results/$trial.request.json" \
  "$origin/api/replay" > "$diagnostic/results/$trial.result.json"
```

Record the new call ID before selecting the next trial; never resend an ID.
Stop after 16 sends or earlier if a premise fails. Preserve the frozen comparison,
scorecard, serialized requests, raw responses and the debugger's immutable logs.
Record actual usage, request sizes and available latency; missing measurements
remain unknown. Stop the debugger when finished. Replays cannot publish artifacts
or change workflow authority, and restarting does not reset an approved count.

## Assessment before promotion

Use the existing scorecard fields to assess actual outputs, preferably with arm
names hidden. Preserve reasons, generated fragments, their resolved text and
source/output evidence. Proposed labels must not be revised after seeing an
answer to improve an arm's result. Evaluate each dimension independently:

- **Narrative purpose and source obligations:** use `field_purposes` and
  `collection_obligations` to assess coherent actor/action/result meaning and every
  listed source obligation. Preserve conditions, timing, status duration and
  distinct displays. Record missing, contradicted or invented behavior. Copying
  the formatting sentence or its displayed-value claim into the output without
  source support is example contamination, even if it contains a valid reference.
- **Every literal use in context:** in `literal_occurrences`, record each raw or
  typed occurrence and whether it fulfils its surrounding narrative role. Count
  raw literals and detached references separately. Raw greeting text followed by
  a trailing exact-copy object has two occurrences; it is not correct composition
  merely because a typed object is present. Mark a standalone reference detached
  when it does not occupy the intended position in the narrative, and report raw
  duplication when the extra literal adds no source-backed meaning.
- **Identity, repetition and ambiguity:** use `literal_expectations` plus the
  occurrence inventory to distinguish correct reference identity, wrong identity,
  unassessable identity, altered/omitted values and legitimate repeated use. The
  illustration's first occurrence does not answer for the other occurrence with
  equal bytes. A clause covering multiple display contexts can be adequate
  without repeating the literal; no mechanical mention count is a semantic judge.

Record purpose assessments as `fulfilled`, `partial`, `not_fulfilled` or
`unassessable`; source obligations as `preserved`, `partial`, `omitted`,
`contradicted` or `unassessable`. Keep occurrence representation (`typed_correct`,
`raw_prose`, `wrong_identity`, `altered`, `omitted`, `unassessable`) separate from
its placement, duplication and contamination evidence. Record false user gaps
and invented prerequisites independently. Valid JSON/schema and correct rendered
bytes do not compensate for lost meaning, duplication or invented requirements.

For the no-literal control the typed-reference denominator is zero. Report each
case/arm/repetition, usable-answer counts, explicit semantic denominators and
actual usage. Failed trials stay in the declared 16 and have unassessable semantic
results. Keep `native_admission` as `not_assessed` for replay: the debugger does
not execute native generation, semantic validation or authorized repair.

The adoption gate is declared before any calls. Advancing the example to a
production proposal requires all of the following:

- Both candidate repetitions compose references meaningfully in place for the
  captured singleton and the unrelated singleton, without substituting a raw
  literal followed by a detached reference.
- Both multi-occurrence candidate repetitions use the correct source identity in
  context; unresolved identity ambiguity does not pass.
- Candidates introduce no example contamination or regression in source
  obligations, and the zero-literal control invents no references.
- The paired baseline comparison demonstrates improved composition without
  regression in the other declared dimensions.

A tie, inconclusive result or failed condition does not justify production
promotion. This gate governs assessment of this experiment; it is not an engine
validator or a new runtime surface-form rule. Preparation and schema admission
alone establish no effectiveness. Two repetitions are a bounded diagnostic, not
reliability proof. Any later shared-owner integration must retain these
representation/meaning distinctions; whole-workflow E2E remains separate,
requires its own approval and grades actual published output.

## Results

The [retained results](../../../../zig-out/authoring-composition-comparison/2026-10-09T21-16-40Z-f080299c445f/)
contain the frozen inputs, raw provider exchanges, native debugger records,
[operational accounting](../../../../zig-out/authoring-composition-comparison/2026-10-09T21-16-40Z-f080299c445f/operational.json),
and the [completed assessment](../../../../zig-out/authoring-composition-comparison/2026-10-09T21-16-40Z-f080299c445f/assessment.md).
Exactly 16 sends were confirmed, with zero uncertain
or unrun trials; the debugger was stopped. All 16 answers passed JSON/schema
checks. Actual usage was **13,876 input + 1,794 output = 15,670 tokens**.
Provider latency was unavailable. Recorded debugger round trips include replay
and logging overhead and are not provider latency.

| Case | Baseline, both repeats | Candidate, both repeats |
| --- | --- | --- |
| Captured startup | Detached exact reference plus raw greeting or stringified reference syntax | Reference correctly replaces the greeting inside the sentence; all three required behaviors remain |
| Airflow pause | Detached reference plus raw `Paused` | Reference correctly occupies the displayed-status position; stop, duration and restart remain |
| Room notification | Coherent notification and threshold behavior; no references | Identical parsed content; no example or invented references |
| Valve status | Only three reference objects, with no behavioral narrative | Correct source occurrences in context; both displays, persistence, failed confirmation and retained prior result remain |

No candidate copied the illustrative sentence into its narrative. Multiple-ID
answers correctly distinguished the two `Closed` occurrences instead of copying
the example's first ID for both. Candidate repetitions produced identical parsed
values in each case. The no-literal control is excluded from the six-answer
reference-composition denominator.

The startup candidate says the greeting is **“followed by”** the date and time.
The source requires both outputs but specifies no order. Baseline repeat 1 also
adds order, along with an unsupported console implementation and weaker greeting
obligation; baseline repeat 2 does not add order. These defects remain separate
from whether reference objects are correctly placed. The candidate's additional
sequence prevents claiming that all assessed dimensions are non-regressing,
despite the substantial formatting improvement.

Assessment is model-assisted, non-blinded and limited to visible development
cases with two repeats. Native workflow admission, sibling field purposes,
authorized repair, publication and rubric quality were not exercised. The next
production decision still needs evidence of composition improvement without
introduced obligations or conditions; no fixture-specific wording ban or new
validator follows from this result.
