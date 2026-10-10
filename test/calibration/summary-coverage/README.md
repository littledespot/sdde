# Summary coverage guidance comparison

**Prepared; no live calls have run.** The production mechanics use union coverage
and proven exact-duplicate normalization under [§16.4](../../../design/contracts/16-reference-ingestion.md#164-semantic-extraction-flow).
Live meaning preservation and completion improvement remain unproved. This
comparison tests the changed guidance, while offline regression evidence tests
native admission and normalization. Neither is an E2E publication/rubric result.

The proposed bound is **16 physical calls**: four cases × two arms × two unchanged
repetitions. Approval must explicitly cover these calls before dispatch under
[§28.8](../../../design/contracts/28-testing.md#288-model-conformance-comparisons).
There are no retries, corrections, repairs, model judges or E2E runs. Failed or
empty responses consume a trial; uncertain transport stops the comparison without
resending. Prior approvals do not cover this plan.

[comparison.json](comparison.json) freezes the parent identity, settings, case
evidence, proposed obligation labels, edit-file SHA-256 values and trial order.
It is planning data, not a new harness or runtime contract. Each `*.edit.json`
uses the existing debugger's closed `Edit` shape (`content`, `schema`). The
[scorecard](scorecard.template.json) starts every trial as `not_run`.

| Case | Purpose |
| --- | --- |
| Captured startup call 4 | Reproduce the complete assignment that returned a combined summary plus repeated details. |
| Loan renewal | Preserve conditions, refusal, unchanged due date and success-only notification across unrelated source requirements. |
| Valve occurrences | Preserve north/south requirements with equal `Closed` bytes from distinct source occurrences. |
| Reservoir control | Preserve one obligation and its condition/duration without inventing detail or excessive subdivision. |

The startup baseline retains the captured content and selected-schema bytes. The
other cases are explicitly controlled packets in the same input shape, with
internally consistent claim/citation/token selections and child summaries. They
are visible development cases, not held-out or end-to-end evidence. Their original
source text is retained in the manifest; the model sees it through the citations.

Within each pair **only the shared summary-assignment coverage clause changes**:
baseline requires every assigned claim exactly once across statements; candidate
requires the collection to cover every assigned claim and permits combined,
split and overlapping expressions. Prompts, purpose, original evidence, accepted
child summaries and selected schema are byte-identical within the pair. The
second repetition reverses arm order. Models never see assessment labels.

All trials select parent `request-4-inference-1` in
`RUN-fbe2842d3c70b12334e33cdb10a47a17`, captured in
`zig-out/e2e-spec/2026-10-10T00-32-22Z-4b66d7fb9b7b4b4d9bce6f612fe04e41`.
Replay inherits Bedrock `openai.gpt-oss-20b-1:0`, region `ap-southeast-2`, low
reasoning, temperature 0, output allowance 16,384 and native schema transport.
Do not silently substitute a later capture or settings. A missing parent, changed
hash, unavailable configured model or changed setting requires re-preparation.

## Replay procedure

Build and open the debugger without sending a request:

```sh
zig build
engine="$PWD/zig-out/bin/sdde"
capture="$PWD/zig-out/e2e-spec/2026-10-10T00-32-22Z-4b66d7fb9b7b4b4d9bce6f612fe04e41"
comparison="$PWD/test/calibration/summary-coverage"
diagnostic=$(mktemp -d /tmp/sdde-summary-coverage.XXXXXX)
cp -R "$capture/project" "$diagnostic/project"
cp -R "$comparison" "$diagnostic/comparison"
mkdir "$diagnostic/results"
(cd "$diagnostic/project" && "$engine" --debugger hello-world)
```

Use the dedicated test credential through the existing credential adapter, without
printing or saving it. Retain captured configuration/provider assets and inspect
the parent description and all manifest hashes. In a second shell, set
`diagnostic` to the copied directory, `origin` to the printed loopback origin and
`debugger_token` to the session URL fragment. After approval, select one manifest
trial in order and prepare its request:

```sh
comparison="$diagnostic/comparison"
trial='captured-startup-baseline-1'
curl --fail --silent --show-error \
  -H "x-sdde-debugger-token: $debugger_token" \
  "$origin/api/calls" > "$diagnostic/results/calls.json"
jq -e --arg trial "$trial" '.trials[] | select(.id == $trial)' \
  "$comparison/comparison.json" > "$diagnostic/results/selected.json"
parent=$(jq -r '.parent.call' "$comparison/comparison.json")
run=$(jq -r '.parent.run' "$comparison/comparison.json")
index=$(jq -er --arg run "$run" --arg parent "$parent" \
  '[to_entries[] | select(.value.run == $run and .value.id == $parent)] | if length == 1 then .[0].key else error("parent unavailable") end' \
  "$diagnostic/results/calls.json")
edit=$(jq -r '.edit' "$diagnostic/results/selected.json")
jq -n --argjson call "$index" --slurpfile edit "$comparison/$edit" \
  '{call:$call,mode:"modified",edit:$edit[0]}' > "$diagnostic/results/$trial.request.json"
```

Inspect the serialized request. The following command sends **one paid provider
call** and must not run before approval:

```sh
curl --fail-with-body --silent --show-error \
  -H "Origin: $origin" -H "x-sdde-debugger-token: $debugger_token" \
  -H 'Content-Type: application/json' \
  --data-binary "@$diagnostic/results/$trial.request.json" \
  "$origin/api/replay" > "$diagnostic/results/$trial.result.json"
```

Record the returned identity before selecting the next trial. Stop after 16 sends
or earlier if a premise fails. Preserve immutable logs, raw responses, prepared
requests, the frozen manifest and scored evidence. Restarting does not renew the
call allowance. Replay cannot publish artifacts or grant workflow authority.

## Independent assessment

Review with arm labels hidden where practical. Keep denominators per
case/arm/repetition; failed trials remain in the declared 16. Assess separately:

- Completion, stop reason, repetition/truncation, actual usage and available latency.
- Invalid or repeated IDs within one statement, missing claim coverage, exact
  duplicate statements and legitimate overlap. Use the **same union-coverage and
  exact-equivalence criteria for both arms**, not the old disjointness rule for
  one arm. Different IDs, token occurrences or paraphrases are not interchangeable.
- Every listed obligation: `preserved`, `partial`, `omitted`, `contradicted` or
  `unassessable`, supported by source/output excerpts. Account for conditions,
  negation, timing and obligation strength. Attached IDs do not establish meaning.
- Unsupported additions, false conflicts/user gaps, altered literals and mistaken
  source identity. Token-only evidence is not a selectable semantic claim. Native
  token projection does not excuse losing its surrounding behavioral meaning.
- False-acceptance risk: a structurally acceptable union may contain an unsupported
  proposition or omit meaning. Report it even if all claim IDs are present.

The debugger validates JSON/schema, **not native summary admission**; leave
`native_admission` as `not_assessed`. Manual structural scoring must not be labelled
execution of the native validator/normalizer. Both arms share the production
normalization contract; its mechanical benefit is established separately with
offline captured-shaped regressions, including duplicate collapse, union coverage,
source-occurrence preservation and repair after normalization. This plan adds no
parallel validator or replay-to-workflow authority path.

The declared quality gate is: both candidate repetitions complete summaries
preserving every captured-case obligation, with no unsupported additions or altered
literal/source identity; no candidate introduces new missing/altered obligations,
unsupported additions or false source-identity equivalence relative to its paired
baseline; unrelated/control cases remain meaningful; and at least one measured
completion, repetition or meaning-preservation dimension improves. A tie or
unassessable result establishes no improvement. Structural acceptance alone does
not meet the gate. Two repetitions are diagnostic evidence, not a reliability
estimate. Actual E2E publication and rubric quality require separately approved
complete workflow runs after this bounded comparison.

This single-model pilot also does not exercise downstream behavior with source
preservation enabled versus disabled. That comparison and broader cross-model
acceptance remain open in FIX01; diagnostic success cannot close them.
