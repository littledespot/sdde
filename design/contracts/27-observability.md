# 27. Observability

Part of the [proposed design](../design.md#27-observability), as amended by the
[accepted ADRs](../design.md#32-accepted-and-deferred-implementation-choices).

- The runner constructs one pure `WorkflowLog` binding from the selected compiled workflow's
  registry-validated four-character shortcode.
- Actions call `workflowLog.log(&delta, fact)` to append attributed telemetry without performing
  I/O; runner lifecycle facts use the same active binding.
- The resulting `NodeDelta.telemetryFactsAdded` values pass through the discrete logging actions
  described in Section 13.9. Under [ADR 0032](../decisions/0032-engine-routines.md) (feature logging not yet
  implemented), those actions become the steps of a feature-logging engine routine, once its
  logging preconditions hold.
  - The event outcomes, emergency diagnostic and finalization rules here are unchanged.
  - Cancellation under a log lock is reported as a logging failure; ADR 0032 leaves
    changing that shared sink contract undecided.

[View the Observability events sample](../code.md#observability-events).

Event fields include the validated four-character workflow shortcode, run/feature/stage/node IDs, parent/correlation IDs, attempt, duration, workflow model-operation/model-slot identity, token usage, diagnostic codes, stage-action step ID, repair unit kind, command ID, exit code, and evidence status. Field definitions are registry-owned and sensitive content is excluded or redacted before serialization.

Under [ADR 0030](../decisions/0030-engine-owned-model-request.md),
the stages of one `request-model` step are not YAML nodes. The runner still emits one
event for each stage it runs, attributed to the originating step with a stable stage name,
so a report can name the exact stage where a request stopped.

Under [ADR 0031](../decisions/0031-stage-actions.md), a stage action's internal steps are
functions, not nodes, so they emit no events of their own. The stage action's event records its
outcome, and a failure records the failing internal step (from the action's closed internal-step
enum) as `step_id` beside the diagnostic code. For a Zig error, the step comes from a stage-owned
diagnostic slot, which the binding hands the runner's step slot before the unchanged error
propagates; the runner records it in the `action.failed` event ([F0002](../features/F0002-LogService.md)).

[ADR 0018](../decisions/0018-debug-model-exchange-logging.md)'s prompt capture at
`debug` and `trace` (every production model attempt's complete assembled request and
available raw returned body, including malformed output and failed attempts), its
credential redaction, fragmenting and failure rules, and event emission follow
[§26.5](26-security.md#265-secrets-and-logging): an event an ADR requires to be logged
is emitted at every level. A partial or no-body capture never claims a complete
response, and the event stream remains metadata-only. The selected graph activates its
feature log after deterministic reference preflight; a run-local directory capability
binds newly created roots to subsequent reads and publication.

- Candidate diagnostics retain typed rule, target, rejected value and admissible scope.
- The shared diagnostic projection distinguishes a response origin, an assembled-candidate
  diagnostic, and missing required response provenance. Coverage validation and a
  producerless rejection (a classification rejection naming only missing entries, which
  have no producer) initially describe the assembled candidate; repair authorization
  supplies a producer only after selecting a supported replacement. Observers retain the
  native revision, dependencies and targets without inventing a call association. Missing
  required or ambiguous response associations still reject; diagnostic attribution grants
  no repair authority.
- The producing request's assignment position in the existing identity ledger, attempt ordinal
  and operation kind survive request-body release and join only to the current execution's
  operation ledger.
- Repair updates origin only for its selected replacement; untouched siblings retain their
  original call attribution.
- Console, event and report projections consume this evidence without parsing model text again
  or creating repair authority.
- Model-text capture status belongs to the captured call. A later correlation or reporting
  error cannot relabel successfully saved text as a capture failure.
- Capture rejection retains one typed diagnostic: the failing boundary, closed
  cause, call origin when available, direction and logging failure code. Lineage,
  source-snapshot projection, serialization, redaction, chunking and persistence
  failures remain distinguishable without recording credentials or raw bodies in
  diagnostics. A subsequent logging/finalization failure cannot replace the first
  capture cause; both remain failed evidence. A capture failure is the call's one cause: a
  rejection formed from that call's result (its own error, an accounting failure raised before
  usage is applied, an unreadable result) is not kept beside it, and the report shows the
  capture failure alone. A blocked request capture leaves the call `not_sent` in the token
  ledger and a blocked response capture still accounts the call's usage, including a budget
  overshoot, so only a second fault in the same call can leave its usage unaccounted.
  CLI failure output and terminal reports expose the typed diagnostic. Action and
  terminal event codes retain the boundary and closed cause; the terminal event
  retains the call correlation and attempt when known.
- An authorized assembled-candidate repair has explicit native provenance, `repair`
  call kind, its own original call and no fabricated parent. Response-produced
  repairs and context follow-ups still require a known producing call. The shared
  lineage validator owns both capture and prompt admission; debugger readback
  preserves the distinction using the existing call/original/parent columns.

### Complete execution evidence

Completeness applies to successful and failed work:
retain every executed operation's outcome, JSON/schema rejection, correction attempt,
native repair, retry exhaustion, token-accounting result and terminal disposition.
An earlier error remains inspectable after recovery. Capture every available model
body under ADR 0018; retain partial/no-response provenance and credential redaction.
Diagnostic runs must enable full capture. Console output is a mirror, not a substitute
for persisted records. A harness-only trace does not satisfy production logging.

A later failure does not erase an earlier one. The terminal rejection stays the later
failure, with its own status and diagnostic, which is all
[ADR 0041](../decisions/0041-failed-run-incomplete-publication.md) reads. The runner
keeps the first rejection it replaced as the run's first cause, whole, with an `authority`
reason ([§6](06-pipeline-nodes.md#runner-rejection-reasons)) when it has one, set once so
the earliest replacement wins. A capture failure is recorded while its call runs, so it is never kept
as a first cause (its terminal carries a later logging failure), and one failure seen twice, such as a
sink that stays broken, replaced nothing. The
E2E report (`first_cause`), the step event of the rejected step and the offline step trace
(`:first=`) carry both; the feature log's terminal event keeps the terminal code only and
gains no event, column or code.

Reuse the closed event registry and shared logging lifecycle. The runner owns
execution/transition facts, validators supply typed diagnostics, and the existing
provider observation boundary owns exchange bytes. Emit each fact once with its
run/node/request/attempt association; do not introduce a second logger or re-parse
response bodies to reconstruct facts. Capture/serialization/append/flush failure must
remain an explicit terminal failure, with the existing emergency diagnostic when the
file sink is unusable. Never claim a complete record after a logging failure.

**Publication finalization:** retain ADR 0018 and
§25.1's close-before-write barrier. `publication.prepared` records the validated
intended `ok`/`needs_user` outcome; it is not a successful write. Actual publication
results remain in the terminal result and harness report. Non-publication terminal
outcomes are recorded before close. Close failure prevents publication, repeated
finalization preserves failure, and no event is appended after close. The feature
stream starts at activation after preflight; pre-activation errors use the existing
terminal/emergency path. No second sink or completion authority is introduced.

The runner projects action starts/outcomes, model attempts and reconciled usage,
protocol/schema admission and current native rejection evidence. `retry.admitted`
and `retry.exhausted` use existing runner counts; `repair.*` observes accepted
native repair transitions and does not count or authorize them. Project only each
operation's newly produced diagnostic evidence, avoiding stale-failure attribution.
The [§22.6 normalization](22-repair.md#226-unparseable-output) emits one warning
`model.response_normalized`, which records that the engine fixed the response. Its
diagnostic is `REMOVED_LEADING_BRACE_QUOTE` for the two-byte opening artifact,
`REMOVED_REPEATED_FIELD_PREFIX` for an opening artifact repeating the object's first
member name, including the string-value opener, or `REMOVED_PARTIAL_FIELD_PREFIX`
for one repeating only a nonempty start of that name.
Each is emitted only after strict syntax failure and successful remainder parsing.
Correlation identifies the original request/attempt, whose raw response stays intact. Emit this when
decoding succeeds even if subsequent schema validation fails; a separate schema
event retains that failure. Logging rejection prevents continuation.

Every provider-applied non-candidate stop emits one warning `model.provider_stopped`
after `model.completed` for the same request and attempt
([ADR 0011](../decisions/0011-provider-owned-request-limits.md#no-output-token-allowance)).
Its diagnostic is the exact closed stop reason (`OUTPUT_LIMIT`, `CONTENT_FILTERED`,
`UNSUPPORTED_TOOL_REQUEST`, `MALFORMED_OUTPUT` or `CONTEXT_LIMIT`), with the outcome and
the provider's reported input and output tokens. This applies to all inference. The event never retries, reclassifies or excuses the stop, and its
logging rejection prevents continuation.

An `OUTPUT_LIMIT` stop is re-sent once under
[ADR 0039](../decisions/0039-configured-temperatures-and-runaway-resend.md), and every
re-send is logged:

- after the runaway's `model.provider_stopped`, one warning `model.runaway_resent` for
  the runaway attempt, with its operation, slot, `OUTPUT_LIMIT` diagnostic and reported
  tokens, emitted at the re-send's provider-call step once every send check has passed
  and immediately before the send;
- the re-send's own `model.requested` and `model.completed` under the next attempt
  number;
- if the re-send also runs away, its own `model.provider_stopped`, then failure events
  carrying the diagnostic `RunawayRepeated`.

Logging rejection prevents the re-send. The temperature each attempt sent is recorded in
its request description (`model-request-debug/v18`), not in a log field. A re-send that
succeeds removes neither event.

At `debug` or `trace`, ADR 0018's capture logs every runaway in full in the prompt
stream, for the runaway attempt and for its re-send: the assembled request, its request
description (both configured temperatures and the sampling), the provider request with
the temperature sent, and the complete returned output with its stop reason and token
counts. A repeated runaway's output is captured before the failure events and the stop.
Higher levels log only the events.

Under [ADR 0041](../decisions/0041-failed-run-incomplete-publication.md) (accepted, on
hold since 30 October 2026; not implemented), when a failed Specify run publishes its
validated content as a failed incomplete specification, the runner emits one warning
`run.incomplete_published` after the failure events and before the publication writes,
with the failure's diagnostic code. Its logging rejection prevents publication.

Useful metrics:

- model calls and tokens by stage/unit;
- initial-pass and post-repair validation rate;
- repairs by diagnostic code and preset;
- average atomic repairs per accepted unit;
- schema-failure rate by workflow model operation;
- preset path rejection rate;
- command pass/failure duration;
- task throughput and blocked dependency count;
- abandoned workflow execution count;
- unsupported reference formats;
- authority-reconciliation outcomes and gap reasons by earliest owner and requirement kind, including upstream-rework and administrative-block counts.

The metrics distinguish deterministic rejection from semantic-review rejection. This is necessary to see whether failures come from model capability, poor initial guidance, preset errors, or repository problems.

[ADR 0019](../decisions/0019-single-request-debugger.md) adds the native browser
request debugger and single-request replay. `prompt-columns/v3` retains caller
and YAML-entry attribution, exact request descriptions, body lengths and explicit
retry/repair lineage. Debugger records remain diagnostic and never grant workflow
authority; replay requires an explicit user-triggered request for one call.

### Bound preservation comparison origins

Retain the original review-finding origin and the separate comparison-call origin.
A protocol-corrected comparison records the admitted attempt, while the finding
origin remains unchanged. Native invalid-comparison diagnostics identify that
comparison attempt; unresolved ownership and known unsupported repair remain
distinct from invalid evidence. Origins are observations, never evidence authority
or a requirement for log replay during readback.

The execution snapshot records the single configured `workflowTokenBudget`, aggregate
actual tokens and unavailable-usage state. Every inference is charged once,
including retries and stopped output, with no per-class pool or subtotal (ADR 0011).
A global budget rejection is fatal. Exhausted protocol correction records no new
attempt or operation.
