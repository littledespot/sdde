# Record-authoring input comparison

This is a proposed **12-call diagnostic**, not integration or E2E execution.
It uses the existing request debugger and `application/request_replay.zig` for
one send per trial. It cannot publish or make a workflow result authoritative.
No new model runner, retry loop, semantic validator or transport is introduced.

[comparison.json](comparison.json) freezes the premises, paired request edits,
hashes, model settings and trial order. The baseline revision is
`35ded131928ecc0a7b55c92fe5d714f5db99405f`. The captured baseline is the exact
call-12 content/schema from run
`2026-10-09T07-32-23Z-4dea51d8871d149cc721f69b011070b6`, identified separately by
its context hash; the revision identifies the pre-change repository, not the
historical run's build revision.

| Premise | Origin | Exact literals | Calls |
| --- | --- | ---: | ---: |
| Startup, greeting and UTC | Retained failing call 12 | 1 | 4 |
| Room temperature threshold notification | Manually prepared unrelated premise | 0 | 4 |
| Connectivity success/failure display | Manually prepared unrelated premise | 2 | 4 |

Each premise has baseline and candidate arms, each repeated twice unchanged.
The second round reverses arm order. All cases are visible development premises;
none is claimed to be a blind holdout. Labels remain **proposed** until reviewed.
They and the scorecard never enter a model request.

The candidate changes only the dependent `brief` and `entities` representation
to resolved business text and removes the excluded entity-family definition.
Source requirements, original sources, preserved literal IDs/values, source
assignment, aggregate record requirements, guidance and selected response schema
remain identical within each pair. The captured entity explanation remains weak
in both arms; improving it would confound this comparison. Controlled premises
are diagnostic data, not claims about what upstream production would generate.

The unrelated cases use the production schema restricted to zero or two exact
choices respectively. The captured case uses its unchanged singleton schema.
Do not use the singleton schema for every case. Frozen schemas are evidence,
not runtime defaults or a second schema authority.

## Offline validation

```sh
zig build test-rubric-evaluator --summary all
```

The tests check closed edit decoding, hashes, paired facts and guidance,
unchanged repeats, label isolation and equality with the production compiler's
selected zero/singleton/multiple-reference schemas. They also exercise native
singleton construction without treating reference-only content as meaningful.
Production generation tests separately cover the shared dependent-text projection,
exact/passive resolution, initial generation, repair and correction.

These checks make no provider calls. Passing them does not establish improved
authored meaning. The debugger reports provider decoding, JSON and schema
admission. It does not reconstruct the captured native generation graph;
`native_record_admission` must remain `not_assessed` for replay results. Production
native admission is verified by offline tests and subsequently by real E2E.

## Bounded live procedure

Follow [design §28.8](../../../design/contracts/28-testing.md#288-model-conformance-comparisons):
review the frozen premises and obtain explicit approval for these **12 physical
calls** before dispatch. No correction, repair, model judge or automatic repeat
is included. Failed/empty answers consume their trial; do not silently replace
them. Any additional call requires a new bounded approval.

1. Verify the manifest/edit/schema hashes and the parent call's captured content,
   schema and model binding. Preserve a copy of the manifest with the results.
   Stop if the retained capture or pinned settings are unavailable or differ.
2. Build with `zig build`. Copy the retained run's project to a new diagnostic
   directory so original logs remain immutable. Retain its workflow/configuration
   assets for the original binding; do not silently substitute current settings.
3. From that copied project, start the built executable with `--debugger hello-world`.
   Supply only the dedicated test Bedrock credential to that process through its
   existing credential adapter; do not print or persist it. Opening the debugger
   and reading `/api/calls` does not dispatch a model call.
4. Find the parent **by** manifest `capture.run` and `capture.call` in `/api/calls`.
   Its returned array index is the replay `call` value; physical call 12 is not a
   stable API index. Always select this original parent, never the previous trial.
5. In the manifest's trial order, POST to the debugger's existing `/api/replay`:

   ```json
   {"call":0,"mode":"modified","edit":{"content":[],"schema":"..."}}
   ```

   Replace `0` with the resolved parent index and `edit` with the complete parsed
   file named by that trial. Use the debugger session's required Origin and
   `x-sdde-debugger-token` headers. This example is a shape, not a dispatch command.
   Both arms use modified replay so both receive the same one-send path and
   immutable parent ancestry. Model/settings are inherited from that parent.
6. Record the returned call ID for each trial and retain its serialized request,
   raw response and validation from `logs/debugger`. Confirm provider requests
   differ only by the declared user-packet projection; record complete request
   bytes, input/output usage, latency and failures. Stop after 12 sends.

The dedicated diagnostic files can be submitted by a one-off loopback client;
it must only call the existing debugger endpoint, not rebuild provider requests
or bypass replay authorization. No new command is required in the E2E harness.

## Meaning assessment

Copy [scorecard.template.json](scorecard.template.json) beside the retained
results. Assess the actual generated content, preferably with arm names hidden
until assessment is complete. Resolve exact references to the premise's catalogue
for inspection. Do not infer meaning from attached claim IDs, valid JSON,
reference presence, fixed wording or string-length/keyword rules.

Keep these dimensions separate:

- **Field purpose:** for every emitted field, record its family/field, generated
  value, `fulfilled`, `partial`, `not_fulfilled` or `unassessable`, and a reason.
  Use the shared production family/field definitions. In an acceptance criterion,
  the precondition, trigger and result must have their respective meanings.
  A literal-only expected result can be appropriate; literal-only conditions or
  requirements must not pass merely because the literal appears in the source.
- **Aggregate obligations:** assess each listed source obligation across the
  whole record collection as `preserved`, `partial`, `omitted`, `contradicted`
  or `unassessable`, with record/field evidence. Do not require every obligation
  in every individual record. Record absent mandatory families separately, and
  record invented conditions or weakened obligation strength.
- **Exact literals:** assess each expected value as `preserved_in_context`,
  `present_wrong_context`, `altered`, `omitted` or `unassessable`, with evidence.
  Correct bytes alone cannot compensate for lost behavior. For the prose-only
  case the exact-literal denominator is zero, not a perfect score.

Operational/protocol failures remain in the 12 declared trials. Their semantic
results are unassessable, not successful zeros. Report admitted-answer counts
alongside every semantic denominator, each case/arm/repeat and actual token and
latency totals; missing usage is unknown. Preserve disagreement and the rationale
for any adjudication. Do not modify labels after observing an arm's answers to
make that arm win.

No composite score or automatic promotion rule is added. Review whether the
candidate reduces lost obligations or misused fields without increased wrong
conditions, lost literal meaning or unusable answers, including the unrelated
cases. Two repeats are a bounded diagnostic, not reliability proof. Actual E2E
publication and rubric evaluation remain separate, explicitly approved evidence.
