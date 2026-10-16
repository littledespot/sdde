# Insertion presentation attribution

**B3 cutover — 17 October 2026:** the approved native exact-value representation
supersedes this unexecuted 21-trial presentation panel. Its immutable v5 request
descriptions and pinned counts remain historical diagnostic evidence. The offline
reader accepts only that closed historical shape, cannot add native exact scope
or convert it to v6, and labels scoring as historical rather than current model
admission. `dispatch-request` fails `HistoricalDispatchUnsupported`; the execution
instructions retained below are superseded. A new experiment requires current
captures and separate approval. No model sends or workflow authority are added.

**Prepared offline, 16 October 2026. Zero model sends. Dispatch is not authorized
by this manifest.** Former FIX04 Phase 1A.3 step 2, now tracked in
[FIX05 B3](../../../fixes/FIX05.md#b3-exact-value-bookkeeping-is-left-to-the-model),
requires a committed build and separate approval before this panel runs. If the
native exact-value representation is approved, it replaces this panel, as accepted
on 17 October above. The historical plan consists of **21 single-request sends**,
without retries, corrections, repair, judges, workflow continuation or publication.

The immutable [sources](sources/provenance.json) copy the 18:58 hello-world run
`2026-10-16T07-58-59Z-ec56ff4bc24a21c0082210cf6caa8f31`: records call 13
(`request-11-inference-1`) and extraction call 1 (`request-1-inference-1`) from
`RUN-dea0536ccfa67b3b2f8db4048f28330c`. Twelve SHA-256 pins retain exact context,
provider request, provider response, model text, transport outcome and full native
request description. The descriptions were reconstructed from contiguous,
complete `request_description` fragments in that run's prompt log. Historical
captures are not modified or imported as workflow authority.

The [plan](prepared/plan.json) freezes seven arms, each repeated three times in
listed order: one round across all arms, repeated three times. Each arm retains
its exact debugger edit and expected provider request, with SHA-256 pins. Both
baseline provider bodies reconstruct byte-for-byte through the production
Converse serializer. The model remains `openai.gpt-oss-20b-1:0`, AWS Bedrock
`ap-southeast-2`, low reasoning, temperature **0.1**, native schema and **16,384**
output tokens. The selected response schema, other guidance, assignment, original
source witness and native field bindings stay identical within each captured call.

| Arm | Change to the captured user packet | Sends |
| --- | --- | ---: |
| `records_baseline` | Exact replay, no edit | 3 |
| `records_no_insertion_fields` | Remove `insertion_fields` | 3 |
| `records_grouped_rules` | Group `field_rules` by identical instruction | 3 |
| `records_both` | Remove insertion list and group rules | 3 |
| `records_no_obligation_wording` | Replace obligation wording in rule instructions only | 3 |
| `extraction_baseline` | Exact replay, no edit | 3 |
| `extraction_no_presentation` | Remove both `field_rules` and `insertion_fields` | 3 |

Grouped rules use `{fields: [...], instruction: ...}` and preserve all 15 original
field associations in three entries. No field association is dropped. The wording
arm changes “Exact copies may carry its exact-value obligation inside that prose”
to “Exact copies may be included inside that prose” and removes the identity-label
sentence about satisfying an obligation. It retains the remaining field rules and
all original source-obligation text. These experimental edits are diagnostic data;
they do not change production presentation.

## Offline commands

All commands use repository `build.zig` steps. The tool has no model dispatch,
credential lookup, HTTP client or process launch path. Its provider imports are
the existing pure request serializer and response codec; it never constructs a
transport adapter. Files are created exclusively; an existing file must already
match exactly. Use a new score output filename when adding receipts.

```sh
zig build test-attribution-replay --summary all -j2
zig build test-integration --summary all -j2
zig build attribution-replay -- prepare test/calibration/insertion-presentation/prepared
zig build attribution-replay -- validate test/calibration/insertion-presentation/prepared
zig build attribution-replay -- score test/calibration/insertion-presentation/prepared test/calibration/insertion-presentation/receipts.template.json zig-out/insertion-presentation.unattempted.score.json
```

Preparation and validation reconstruct all seven bodies, check the twelve source
pins and reject drift. The captured integration tests prove the only changed
packet keys are the permitted presentation keys and keep baseline bodies,
guidance and selected schema exact. Helper tests reject malformed rules, unsafe
paths, unsupported CLI modes and malformed insertion shapes.

## Historical execution handoff — superseded 17 October 2026

After a commit and separate explicit approval, use the existing authenticated
[single-request debugger](../../../design/decisions/0019-single-request-debugger.md)
on the retained project's `specs/hello-world` directory. Save its authenticated
`GET /api/calls` result locally. For each next trial ID from the frozen plan, this
**offline** command generates the exact one-send POST body:

```sh
zig build attribution-replay -- dispatch-request test/calibration/insertion-presentation/prepared records_baseline-1 zig-out/insertion-presentation.calls.json zig-out/insertion-presentation.records_baseline-1.post.json
```

It resolves the original parent by run/call identity and proves its complete
description and provider bytes match the frozen source. It selects the current
zero-based debugger index; never infer that index from a physical call ordinal.
Baseline bodies use `mode: exact`; other arms use `mode: modified` and the frozen
edit. Submit that body to the debugger's existing `POST /api/replay` endpoint using
its current loopback session token, matching Host and Origin headers and
`Content-Type: application/json`. The offline tool does not perform this POST.
The debugger durably creates its normal immutable request/result records under
the selected feature's `logs/debugger`; retain their paths without rewriting them.

Stop after the listed 21 sends, request/hash/settings drift, unknown usage or
uncertain transport/dispatch. Do not repeat a failed or uncertain trial. Reopening
the debugger or restarting the helper does not renew an approved allowance.
After every exchange, retain its actual input/output tokens and transport outcome.
The experiment has no workflow authority and cannot close live workflow gates.

Create a receipts file with the same closed shape as
[receipts.template.json](receipts.template.json). Append one row per attempted
trial in frozen order, e.g.:

```json
{"trial_id":"records_baseline-1","request_record":"retained/project/specs/hello-world/logs/debugger/REPLAY/request.json","response_record":"retained/project/specs/hello-world/logs/debugger/REPLAY/response.json"}
```

The paths above illustrate the row shape; use the debugger's actual immutable
record paths. Missing exchanges remain unattempted, not successes. Retain a
transport-failed/partial/cancelled result as its attempted row; do not drop it.

## Scoring limits and denominators

The historical offline scorer verifies trial order, duplicate identities, request lineage,
mode, complete description and exact provider body before reading response
measurements. It uses the production Converse decoder, envelope normalizer,
selected-schema compiler, wire guard and response-composition checker. It reports
raw field counts **before** schema/composition admission, then separately reports
schema-valid and mechanically admitted rates. Thus a rejected insertion-only
answer remains in its arm's raw denominator. The entity-name exception stays
visible as an insertion-only identity label even when other fields reject the
whole response. Malformed text shapes have their own count and do not masquerade
as typed insertions. Zero denominators produce `null` rates.

Every trial retains provider-response/model-text hashes, normalization,
schema/composition outcomes, complete native composition diagnostics, actual
usage/latency when available and its raw field counts. Extraction additionally
reports claim count, each claim's kind/citation count and the largest cited line
span. Those are structural observations; they do **not** decide whether claims
were faithfully separated, applicability was correct or meaning was preserved.
Review the immutable raw responses for that interpretation. No rubric or semantic
model judge is invoked. Mechanical diagnostic admission is distinct from
workflow admission and publication; neither is inferred here. Reports explicitly
state `captured_contract: historical_v5`, `native_exact_scope_available: false`
and `current_model_admission_assessed: false`; a historical mechanically admitted
count is not B3 admission evidence.
