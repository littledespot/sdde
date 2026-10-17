# Current authored-source association qualification

This is a frozen diagnostic preparation for the Phase 5 replacement. It tests
actual brief, primary-story, entity-decision and source-bound record responses.
The retired 22-call role panel remains a separate historical comparison: role
classification and authored content are different tasks and their results must
not be reported as a paired improvement estimate.

Three controlled cases retain complete original sources: the captured startup
display requirements, equipment inspection duties distributed across two source
groups, and loan renewal with an explicitly undecided extension duration. The
first retains its original exact greeting occurrence. The second tests joint
support for narrative fields and independent complete collection assessment for
each record group. The third must not invent a duration or manufacture an
unrelated clarification. All cases are development evidence, not a held-out
qualification set.

There are 24 logical trials: three cases × four tasks × two repetitions.
Records run once per current native group; the startup case includes its separate
preserved-token group and equipment has two business groups. Consequently there
are **28 physical sends**, not 24. Every record-group response, including an empty
one, remains in its logical collection trial and cost denominator. The manifest
is authoritative for the prepared count; never omit a group to meet a call budget.

The pinned controls are AWS Bedrock `openai.gpt-oss-20b-1:0` in
`ap-southeast-2`, low reasoning, temperature 0.1, native schema and a 16,384 output
allowance. Seed and top-p are absent. Stop before another send once measured
input-plus-output usage reaches 200,000 tokens. There are no retries, corrections,
repairs, model judges, live review calls, workflow continuations or E2E runs.
Neither this file nor a successful offline check authorizes dispatch.

`cases.json` and `scorecard.template.json` are preparation sources. The owning
test uses `specification_session.packet`, the current result-schema restrictions
and the existing provider encoder. The full static JSON guidance, task prompt
and dynamic packet are retained in their production order. It also passes
explicit MOCK context seeds through generation parse/validation, current native
association admission, record consistency and complete session assembly, then
builds a source-review packet from the admitted authored associations. These
probes establish mechanics; seeds and their review projections are neither live
outputs nor evidence of faithful authored meaning.

The prepared parent is authentic extraction Call 1, `request-1-inference-1` in
`RUN-5603b655c6e6a7498c6980fc0d447584`; it is a diagnostic lineage, not an
authoring workflow origin. Its descriptor uses the same pinned model controls.
Offline preparation loads that capture through the canonical debugger store and
rebuilds both its exact request and every modified authoring request through the
existing replay provider's `prepare` method. The credential environment is empty,
the transport is fake, and the test asserts zero exchanges. Current compiled-step
authorization for its exact `g7-extract-content` binding must also pass before
launch; neither preflight is live model evidence.
In a clean checkout without the retained archive, every native packet/admission
probe still runs, while the separate parent preflight reports `unavailable`.
That state cannot authorize or freeze a runnable live panel; never manufacture
an archive or workflow origin to replace it.

```sh
zig build test-specification-generation --summary all -j2
```

Official generated packets, edits, provider requests, seed probes and
`preparation.json` are written beneath `.zig-cache/authoring-associations/v14-text/`.
Freeze those exact bytes into an isolated run directory after offline checks and
review every manifest pin before requesting approval. Later changes to dependencies
require regeneration and a fresh frozen plan. Do not edit generated projections.

Launch only after bounded approval of all 28 sends, the AWS destination and
the synthetic/captured requirements, derived evidence, non-public guidance and
schemas. Reuse the authenticated native request debugger's `/api/replay`
modified-request route with each complete frozen `edit.json` object. Select one
actual parent call by its retained run/id, preserve the pinned settings and check
the actual serialized provider request against each request hash. The existing
`scripts/e2e-call.sh` has no edit-file input; it cannot launch this panel.
No separate network client or production fallback is introduced here.

Journal each send before dispatch. Retain authentic parent/replay linkage, response
bytes, stop reason, input/output usage and transport timing. A transport failure
or unknown dispatch state stops the panel; do not retry an uncertain send. Never
create workflow model origins from replay sequence numbers. Diagnostic receipts
can be rechecked through native admission but grant no publication or repair
capability.

For actual response admission, use the frozen unit/context/binding with the same
schema, `specification_generation.parse`, `validate` and `specification_session.admit`.
Check record consistency before appending each group. For collection-level
assessment retain **actual** earlier group outputs, not their MOCK seed responses.
Controlled later-unit requests use the explicitly documented seed brief/entity
decision; they do not establish the reliability of the production authoring
handoff. After admission project review subjects from actual associations and
resolve the full original sources independently. No expected-value omission or
loss request substitutes for discovering a real defect.

The same offline test is also the concrete receipt-admission entry point. After
an approved replay, place this closed run manifest at
`.zig-cache/authoring-associations/v14-text/live-run.json`, using the SHA-256 of the
frozen `preparation.json` and the authentic selected parent:

```json
{
  "schema": "authoring-diagnostic-run/v1",
  "preparation_sha256": "actual frozen preparation SHA-256",
  "parent": {"run": "actual retained parent run", "call": "actual parent call"}
}
```

Store each receipt under the prepared trial and member name:
`<trial-id>.<unit>.receipt.json` for narrative units, or
`<trial-id>.records-<group-id>.receipt.json` for record batches. These file names
come from the closed prepared schedule. Receipt values cannot choose a path.
The receipt contract is:

```json
{
  "schema": "authoring-diagnostic-receipt/v1",
  "trial_id": "the prepared trial ID",
  "input": "the exact frozen packet body",
  "request_sha256": "SHA-256 of the actual provider request bytes",
  "response_sha256": "SHA-256 of the actual response body, or empty bytes if absent",
  "result": "replace this placeholder with the existing canonical request and response records",
  "replay_elapsed_ns": null
}
```

`result` contains the existing canonical `request_debugger.RequestRecord` and
`ResponseRecord` as `request` and `response`. The replay HTTP route returns the
updated call list. Read the corresponding authentic canonical records from the
private debugger project's `logs/debugger/<replay-id>.request.json` and
`<replay-id>.response.json`; preserve those files and the HTTP result separately
in the original archive. Do not derive records from the call-list summary. The
redundant inspector `validation` is excluded and recomputed. This
is not another provider-response format. Keep the raw provider body and authentic
request/replay identities. Use a measured replay
duration when available; leave it null otherwise. The reader rechecks the full
request/response hashes, parent, unique replay identities and model controls. It
recomputes usage, stop reason and final text through the existing Bedrock decoder,
then checks the native schema, association and current record dispatch. It does
not trust a replay inspector's claim that the candidate was valid.
After selected-wire schema validation, it uses the production `constructBound`
owner to restore engine-determined singleton fields before typed generation
parsing. Those fields are intentionally absent from the wire schema; echoed IDs
remain rejected. Construction affects only the transient native candidate and
never rewrites the original provider response or receipt.

Rerun the offline command to write `admission.json`. With no manifest/receipts,
all trials are `not_run`. Missing collection members remain `incomplete` and
cannot enter complete native admission. Actual batches are aggregated together;
the reader never fills a missing response with a seed, inherits groups from an
offered catalogue, or converts replay IDs into workflow origins. Known usage is
retained even when a candidate is rejected or a record trial clarifies early.
Malformed, stale, foreign and duplicate receipts remain rejected observations.
`costs_complete` stays false whenever a received receipt cannot be bound or its
usage is unavailable; an empty cost list must never be scored as zero expenditure.
Original receipt archives are never rewritten. Review-projection failures are
reported separately from unit admission, including incompatibility with
controlled sibling seeds; they are not evidence of an authored-unit defect.

Assess the metrics independently using the unscored template:

- Completion and native admission: malformed, truncated, missing/foreign groups,
  illegal cardinality, stale bindings and every not-sent trial stay visible.
- Association selection: current whole groups, correct source occurrences,
  unrelated selections and unsupported positive content. Attached IDs are not
  semantic entailment.
- Meaning: original conditions, triggers, negation, relationships and obligation
  strength; field-purpose adequacy and complete record-collection obligations.
- Uncertainty: faithful narrow clarification for the undecided duration, no
  invented duration, no false missing-authority claim for supplied requirements.
- Exact literals: retain the greeting occurrence where its literal is needed;
  rendering the literal alone is not sufficient behavioral prose.
- Actual calls, input/output tokens and timings, including rejected, empty and
  interrupted trials. Reduced call count is not a quality result.

All sufficient-source logical trials must complete, pass current native admission
and fulfil their specific assigned purposes without unsupported additions. The
brief preserves the intended feature meaning jointly: its title names the feature,
its description explains the behavior and its goal explains the purpose. Do not
require each of those fields to repeat every source clause. The entity basis must
justify its decision, rather than restate every behavioral duty. The story must
provide a coherent user narrative. Each complete record collection must preserve
its assigned group obligations; individual records must fulfil their own field
and family purposes, rather than each restating the entire group.
The genuine-gap case must preserve the known behavior and identify the actual gap
where it prevents the assigned task; do not require an arbitrary exact answer.
Every selected group and explanation must be semantically justified. The case
`support_examples` illustrate relevant group occurrences, not an exact-ID oracle
for every field. Permit a different selection when it genuinely supports the
particular output. Presence, nonemptiness and even an expected ID are not meaning
proof. Exact literals must be correct where an authored value uses a literal; do not
require titles, goals or explanations to copy a literal they do not need. The
assembled specification’s separate aggregate exact-preservation gate remains
unchanged, and this controlled panel does not replace it. A failure is an unqualified candidate, not a
reason to weaken required-output, source-review or publication gates. Whole-workflow
publication, recovery and rubric quality still require the separately approved
Phase 11 E2E evidence.
