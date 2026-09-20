# 27. Observability

Part of the [proposed design](../design.md#27-observability). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

- The runner constructs one pure `WorkflowLog` binding from the selected compiled workflow's
  registry-validated four-character shortcode.
- Actions call `workflowLog.log(&delta, fact)` to append attributed telemetry without performing
  I/O; runner lifecycle facts use the same active binding.
- The resulting `NodeDelta.telemetryFactsAdded` values pass through the discrete logging actions
  described in Section 13.9.

[View the Observability events sample](../code.md#observability-events).

[View the feature logging pipeline](../diagrams/06-feature-logging.md).

Event fields include the validated four-character workflow shortcode, run/feature/stage/node IDs, parent/correlation IDs, attempt, duration, workflow model-operation/model-slot identity, token usage, diagnostic codes, repair unit kind, command ID, exit code, and evidence status. Field definitions are registry-owned and sensitive content is excluded or redacted before serialization.

[ADR 0018](../decisions/0018-debug-model-exchange-logging.md) requires `debug` and
`trace` to capture every production model attempt's complete assembled request and
available raw returned body in the registered prompt stream. This includes prompts,
format guidance, schema, reference/code inputs, malformed output and failed attempts.
Capture is attempted before response admission or disposal; retries retain separate attempt
attribution. A failed attempt with no body has a typed `transport_outcome` record
distinct from actual `provider_body` bytes. Interrupted transport also captures
all received bytes as `partial_provider_body`; their provenance never claims a
complete response. The event stream remains metadata-only.
The selected graph activates its feature log after deterministic reference preflight.
A run-local directory capability binds newly created roots to subsequent reads and
publication. Shared publication and terminal barriers finalize the active sink;
close failure blocks before completion-state publication.

Redact the invocation's authorized credential values before splitting content into
ordered bounded fragments. Valid UTF-8 is retained directly; invalid UTF-8 uses
encoding-tagged base64. Reconstruction preserves the complete sanitized body without
truncation; a storage failure follows the existing fail-closed path after required
provider usage accounting. `logs.level` alone selects capture; higher thresholds
emit metadata only and the removed `promptCapture` field rejects. Prompt records
keep their registered `debug` severity and the configured event threshold.

- Candidate diagnostics retain typed rule, target, rejected value and admissible scope.
- The producing request's assignment position in the existing identity ledger, attempt ordinal
  and operation kind survive request-body release and join only to the current execution's
  operation ledger.
- Repair updates origin only for its selected replacement; untouched siblings retain their
  original call attribution.
- Console, event and report projections consume this evidence without parsing model text again
  or creating repair authority.

### Complete execution evidence

The user-directed completeness requirement applies to successful and failed work:
retain every executed operation's outcome, JSON/schema rejection, correction attempt,
native repair, retry exhaustion, token-accounting result and terminal disposition.
An earlier error remains inspectable after recovery. Capture every available model
body under ADR 0018; retain partial/no-response provenance and credential redaction.
Diagnostic runs must enable full capture. Console output is a mirror, not a substitute
for persisted records. A harness-only trace does not satisfy production logging.

Reuse the closed event registry and shared logging lifecycle. The runner owns
execution/transition facts, validators supply typed diagnostics, and the existing
provider observation boundary owns exchange bytes. Emit each fact once with its
run/node/request/attempt association; do not introduce a second logger or re-parse
response bodies to reconstruct facts. Capture/serialization/append/flush failure must
remain an explicit terminal failure, with the existing emergency diagnostic when the
file sink is unusable. Never claim a complete record after a logging failure.

**Publication finalization (user-approved R39 contract):** retain ADR 0018 and
§25.1's close-before-write barrier. `publication.prepared` records the validated
intended `ok`/`needs_user` outcome; it is not a successful write. Actual publication
results remain in the terminal result and harness report. Non-publication terminal
outcomes are recorded before close. Close failure prevents publication, repeated
finalization preserves failure, and no event is appended after close. The feature
stream starts at activation after preflight; pre-activation errors use the existing
terminal/emergency path. No second sink or completion authority is introduced.
See the [approval record](../../fixes/IMP_001.md#r39-logging-finalization-decision).

The runner projects action starts/outcomes, model attempts and reconciled usage,
protocol/schema admission and current native rejection evidence. `retry.admitted`
and `retry.exhausted` use existing runner counts; `repair.*` observes accepted
native repair transitions and does not count or authorize them. Project only each
operation's newly produced diagnostic evidence, avoiding stale-failure attribution.

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
- unsupported reference formats.
- authority-reconciliation outcomes and gap reasons by earliest owner and requirement kind, including upstream-rework and administrative-block counts.

The metrics distinguish deterministic rejection from semantic-review rejection. This is necessary to see whether failures come from model capability, poor initial guidance, preset errors, or repository problems.

[ADR 0019](../decisions/0019-single-request-debugger.md) adds the native browser
request debugger and single-request replay. `prompt-columns/v3` retains caller
and YAML-entry attribution, exact request descriptions, body lengths and explicit
retry/repair lineage. Debugger records remain diagnostic and never grant workflow
authority; replay requires an explicit user-triggered request for one call.
